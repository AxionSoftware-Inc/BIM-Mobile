import { execFile } from "node:child_process";
import { copyFile, mkdir, stat } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

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

export async function copyArtifactsToSampleDir(sampleDir: string, artifactPaths: NonNullable<{
  project_json?: string;
  debug_report_json?: string;
  floorplan_svg?: string;
  walls_obj?: string;
  metadata_json?: string;
}>) {
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

export async function refreshWorkingProject(workingProject: string, artifactPaths: NonNullable<{
  project_json?: string;
}>) {
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

export async function runHelperCommand<T extends { success: boolean; error?: string; artifact_paths?: { project_json?: string; debug_report_json?: string; floorplan_svg?: string; walls_obj?: string; metadata_json?: string } }>(
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
