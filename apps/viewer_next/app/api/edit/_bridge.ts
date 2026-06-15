import { execFile } from "node:child_process";
import { mkdtemp, copyFile, mkdir, stat, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export type EditCommandName =
  | "create_wall"
  | "insert_door"
  | "insert_window"
  | "delete_element"
  | "set_wall_axis"
  | "update_wall_properties"
  | "update_door_properties"
  | "update_window_properties"
  | "move_hosted_opening";

export type EditArtifactPaths = {
  project_json?: string;
  debug_report_json?: string;
  floorplan_svg?: string;
  walls_obj?: string;
  metadata_json?: string;
};

export type EditValidationSummary = {
  errors: number;
  warnings: number;
};

export type EditRouteResponse = {
  success: boolean;
  command: EditCommandName;
  message: string;
  validation: EditValidationSummary;
  updatedFiles: string[];
  output: string;
  error: string | null;
  artifactPaths?: EditArtifactPaths;
  commandOutput?: unknown;
};

export type EditRouteEnvelope = {
  status: number;
  body: EditRouteResponse;
};

export function resolveConfiguredPath(repoRoot: string | null, value: string | undefined) {
  if (!value) {
    return null;
  }
  return path.isAbsolute(value) ? value : repoRoot ? path.resolve(repoRoot, value) : path.resolve(value);
}

export function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

export function readNumber(value: unknown, label: string) {
  if (!isFiniteNumber(value)) {
    throw new Error(`${label} must be a finite number`);
  }
  return value;
}

export async function ensureDevConfiguration() {
  const repoRoot = process.env.TBE_REPO_ROOT ?? null;
  const helper = resolveConfiguredPath(repoRoot, process.env.TBE_APPLY_COMMAND);
  const workingProject = resolveConfiguredPath(repoRoot, process.env.TBE_WORKING_PROJECT);
  const sampleDir = resolveConfiguredPath(repoRoot, process.env.TBE_VIEWER_SAMPLE_DIR);
  if (!repoRoot || !helper || !workingProject || !sampleDir) {
    throw new Error(
      "Local edit bridge is not configured. Set TBE_REPO_ROOT, TBE_APPLY_COMMAND, TBE_WORKING_PROJECT, and TBE_VIEWER_SAMPLE_DIR.",
    );
  }
  return { repoRoot: path.resolve(repoRoot), helper, workingProject, sampleDir };
}

export function updatedFilesFromArtifactPaths(artifactPaths: EditArtifactPaths) {
  const files: string[] = [];
  if (artifactPaths.project_json) {
    files.push("project.json");
  }
  if (artifactPaths.debug_report_json) {
    files.push("debug_report.json");
  }
  if (artifactPaths.floorplan_svg) {
    files.push("floorplan.svg");
  }
  if (artifactPaths.walls_obj) {
    files.push("walls.obj");
  }
  if (artifactPaths.metadata_json) {
    files.push("metadata.json");
  }
  return files;
}

export async function copyArtifactsToSampleDir(sampleDir: string, artifactPaths: EditArtifactPaths) {
  await mkdir(sampleDir, { recursive: true });
  if (artifactPaths.project_json) {
    await copyFile(artifactPaths.project_json, path.join(sampleDir, "project.json"));
  }
  if (artifactPaths.debug_report_json) {
    await copyFile(artifactPaths.debug_report_json, path.join(sampleDir, "debug_report.json"));
  }
  if (artifactPaths.floorplan_svg) {
    await copyFile(artifactPaths.floorplan_svg, path.join(sampleDir, "floorplan.svg"));
  }
  if (artifactPaths.walls_obj) {
    await copyFile(artifactPaths.walls_obj, path.join(sampleDir, "walls.obj"));
  }
  if (artifactPaths.metadata_json) {
    await copyFile(artifactPaths.metadata_json, path.join(sampleDir, "metadata.json"));
  }
}

export async function refreshWorkingProject(workingProject: string, artifactPaths: EditArtifactPaths) {
  let target = workingProject;
  try {
    const info = await stat(workingProject);
    if (info.isDirectory()) {
      target = path.join(workingProject, "project.json");
    }
  } catch {
    target = path.join(workingProject, "project.json");
  }
  if (artifactPaths.project_json) {
    await mkdir(path.dirname(target), { recursive: true });
    await copyFile(artifactPaths.project_json, target);
  }
}

export async function writeEditCommandFile(commandName: EditCommandName, payload: unknown) {
  const workDir = await mkdtemp(path.join(os.tmpdir(), "tbe-edit-"));
  const commandPath = path.join(workDir, `${commandName}.json`);
  const outputDir = path.join(workDir, "export");
  await writeFile(commandPath, `${JSON.stringify({ type: commandName, ...((payload as Record<string, unknown>) ?? {}) }, null, 2)}\n`, "utf8");
  return { workDir, commandPath, outputDir };
}

export async function runHelperCommand<T extends { success: boolean; error?: string; artifact_paths?: EditArtifactPaths }>(
  helper: string,
  repoRoot: string,
  workingProject: string,
  commandPath: string,
  outputDir: string,
): Promise<{ stdout: string; stderr: string; result: T }> {
  let stdout = "";
  let stderr = "";
  try {
    const result = await execFileAsync(helper, [
      "--project",
      workingProject,
      "--command",
      commandPath,
      "--output",
      outputDir,
    ], {
      cwd: repoRoot,
      maxBuffer: 10 * 1024 * 1024,
      env: process.env,
    });
    stdout = result.stdout;
    stderr = result.stderr;
  } catch (error) {
    const shellError = error as { stdout?: string; stderr?: string; message?: string };
    stdout = shellError.stdout ?? "";
    stderr = shellError.stderr ?? "";
    if (stdout.trim()) {
      try {
        const helperResult = JSON.parse(stdout.trim()) as T;
        return { stdout, stderr, result: helperResult };
      } catch {
        // fall through to generic error below
      }
    }
    throw new Error(stderr || shellError.message || "Helper command failed.");
  }

  const result = JSON.parse(stdout.trim()) as T;
  return { stdout, stderr, result };
}

export function bridgeConfigMessage() {
  return "Local edit bridge is not configured. Set TBE_REPO_ROOT, TBE_APPLY_COMMAND, TBE_WORKING_PROJECT, and TBE_VIEWER_SAMPLE_DIR.";
}

export function summarizeValidation(validation?: { errors?: number; warnings?: number }) {
  return {
    errors: validation?.errors ?? 0,
    warnings: validation?.warnings ?? 0,
  };
}

function statusFromErrorMessage(message: string) {
  if (message.includes("not configured")) {
    return 503;
  }
  if (
    message.includes("must be") ||
    message.includes("required") ||
    message.includes("too short") ||
    message.includes("outside valid wall intervals") ||
    message.includes("overlap") ||
    message.includes("inside host wall") ||
    message.includes("cannot be zero length")
  ) {
    return 400;
  }
  return 500;
}

export async function executeEditRouteCommand<T extends { success: boolean; error?: string; validation?: { errors?: number; warnings?: number }; artifact_paths?: EditArtifactPaths }>(
  command: EditCommandName,
  payload: Record<string, unknown>,
): Promise<EditRouteEnvelope> {
  try {
    const config = await ensureDevConfiguration();
    const { commandPath, outputDir } = await writeEditCommandFile(command, payload);
    const { stdout, stderr, result } = await runHelperCommand<T>(config.helper, config.repoRoot, config.workingProject, commandPath, outputDir);
    const validation = summarizeValidation(result.validation);
    if (!result.success) {
      const message = result.error ?? stderr ?? `${command} failed.`;
      return {
        status: statusFromErrorMessage(message),
        body: {
          success: false,
          command,
          message,
          validation,
          updatedFiles: [],
          output: stdout.trim() || stderr.trim(),
          error: message,
        },
      };
    }
    if (!result.artifact_paths) {
      return {
        status: 500,
        body: {
          success: false,
          command,
          message: "Helper did not return artifact paths.",
          validation,
          updatedFiles: [],
          output: stdout.trim() || stderr.trim(),
          error: "Helper did not return artifact paths.",
        },
      };
    }
    await copyArtifactsToSampleDir(config.sampleDir, result.artifact_paths);
    await refreshWorkingProject(config.workingProject, result.artifact_paths);
    const updatedFiles = updatedFilesFromArtifactPaths(result.artifact_paths);
    const output = stdout.trim() || stderr.trim();
    const message = updatedFiles.length > 0 ? `${command} completed successfully.` : `${command} completed successfully.`;
    return {
      status: 200,
      body: {
        success: true,
        command,
        message,
        validation,
        updatedFiles,
        output,
        error: null,
        artifactPaths: result.artifact_paths,
        commandOutput: result,
      },
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      status: statusFromErrorMessage(message),
      body: {
        success: false,
        command,
        message,
        validation: { errors: 0, warnings: 0 },
        updatedFiles: [],
        output: "",
        error: message,
      },
    };
  }
}
