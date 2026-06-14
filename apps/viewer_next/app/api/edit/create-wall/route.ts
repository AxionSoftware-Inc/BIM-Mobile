import { execFile } from "node:child_process";
import { mkdtemp, mkdir, stat, writeFile, copyFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

import { NextRequest, NextResponse } from "next/server";

const execFileAsync = promisify(execFile);

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type CreateWallRequest = {
  start?: { x?: unknown; y?: unknown };
  end?: { x?: unknown; y?: unknown };
  height_meters?: unknown;
  thickness_meters?: unknown;
  level_id?: unknown;
  wall_type_id?: unknown;
};

type HelperResult = {
  success: boolean;
  error?: string;
  wall_id?: number;
  validation?: {
    issues?: number;
    warnings?: number;
    errors?: number;
  };
  artifact_paths?: {
    project_json?: string;
    debug_report_json?: string;
    floorplan_svg?: string;
    walls_obj?: string;
    metadata_json?: string;
  };
};

function resolveConfiguredPath(repoRoot: string | null, value: string | undefined) {
  if (!value) {
    return null;
  }
  return path.isAbsolute(value) ? value : repoRoot ? path.resolve(repoRoot, value) : path.resolve(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function readNumber(value: unknown, label: string) {
  if (!isFiniteNumber(value)) {
    throw new Error(`${label} must be a finite number`);
  }
  return value;
}

async function ensureDevConfiguration() {
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

async function copyArtifactsToSampleDir(sampleDir: string, artifactPaths: NonNullable<HelperResult["artifact_paths"]>) {
  await mkdir(sampleDir, { recursive: true });
  if (artifactPaths.project_json) {
    await copyFile(artifactPaths.project_json, path.join(sampleDir, "project.json"));
  }
  if (artifactPaths.debug_report_json) {
    await mkdir(path.join(sampleDir), { recursive: true });
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

async function refreshWorkingProject(workingProject: string, artifactPaths: NonNullable<HelperResult["artifact_paths"]>) {
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

export async function POST(request: NextRequest) {
  let body: CreateWallRequest;
  try {
    body = (await request.json()) as CreateWallRequest;
  } catch {
    return NextResponse.json({ success: false, error: "Request body must be JSON." }, { status: 400 });
  }

  try {
    const start = body.start ?? {};
    const end = body.end ?? {};
    const payload = {
      type: "create_wall",
      start: {
        x: readNumber(start.x, "start.x"),
        y: readNumber(start.y, "start.y"),
      },
      end: {
        x: readNumber(end.x, "end.x"),
        y: readNumber(end.y, "end.y"),
      },
      height_meters: isFiniteNumber(body.height_meters) ? body.height_meters : 3.0,
      thickness_meters: isFiniteNumber(body.thickness_meters) ? body.thickness_meters : 0.2,
      ...(isFiniteNumber(body.level_id) ? { level_id: body.level_id } : {}),
      ...(isFiniteNumber(body.wall_type_id) ? { wall_type_id: body.wall_type_id } : {}),
    };

    const length = Math.hypot(payload.end.x - payload.start.x, payload.end.y - payload.start.y);
    if (length < 0.05) {
      return NextResponse.json({ success: false, error: "Wall length is too short." }, { status: 400 });
    }

    const config = await ensureDevConfiguration();
    const workDir = await mkdtemp(path.join(os.tmpdir(), "tbe-edit-"));
    const commandPath = path.join(workDir, "create_wall.json");
    const outputDir = path.join(workDir, "export");
    await writeFile(commandPath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");

    const { stdout, stderr } = await execFileAsync(config.helper, [
      "--project",
      config.workingProject,
      "--command",
      commandPath,
      "--output",
      outputDir,
    ], {
      cwd: config.repoRoot,
      maxBuffer: 10 * 1024 * 1024,
      env: process.env,
    });

    let helperResult: HelperResult;
    try {
      helperResult = JSON.parse(stdout.trim()) as HelperResult;
    } catch {
      throw new Error(`Helper output was not valid JSON. ${stdout || stderr || ""}`.trim());
    }
    if (!helperResult.success) {
      throw new Error(helperResult.error ?? stderr ?? "Helper failed.");
    }

    if (!helperResult.artifact_paths) {
      throw new Error("Helper did not return artifact paths.");
    }

    await copyArtifactsToSampleDir(config.sampleDir, helperResult.artifact_paths);
    await refreshWorkingProject(config.workingProject, helperResult.artifact_paths);

    return NextResponse.json({
      success: true,
      request: payload,
      validation: helperResult.validation ?? { issues: 0, warnings: 0, errors: 0 },
      artifactPaths: helperResult.artifact_paths,
      commandOutput: helperResult,
      message: helperResult.validation?.errors && helperResult.validation.errors > 0
        ? "Wall created, but validation reported errors."
        : "Wall created successfully.",
      stdout,
      stderr,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = message.includes("not configured") ? 503 : 500;
    return NextResponse.json({ success: false, error: message }, { status });
  }
}
