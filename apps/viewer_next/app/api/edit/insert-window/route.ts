import { execFile } from "node:child_process";
import { mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

import { NextRequest, NextResponse } from "next/server";

import {
  copyArtifactsToSampleDir,
  ensureDevConfiguration,
  isFiniteNumber,
  readNumber,
  refreshWorkingProject,
} from "../_bridge";

const execFileAsync = promisify(execFile);

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type InsertWindowRequest = {
  host_wall_id?: unknown;
  offset_meters?: unknown;
  width_meters?: unknown;
  height_meters?: unknown;
  sill_height_meters?: unknown;
  clearance_meters?: unknown;
};

type HelperResult = {
  success: boolean;
  error?: string;
  wall_id?: number;
  opening_id?: number;
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

export async function POST(request: NextRequest) {
  let body: InsertWindowRequest;
  try {
    body = (await request.json()) as InsertWindowRequest;
  } catch {
    return NextResponse.json({ success: false, error: "Request body must be JSON." }, { status: 400 });
  }

  try {
    const hostWallId = isFiniteNumber(body.host_wall_id) ? body.host_wall_id : Number(body.host_wall_id);
    if (!Number.isFinite(hostWallId) || hostWallId <= 0) {
      throw new Error("host_wall_id is required");
    }
    const payload = {
      type: "insert_window",
      host_wall_id: Math.trunc(hostWallId),
      offset_meters: readNumber(body.offset_meters, "offset_meters"),
      width_meters: readNumber(body.width_meters, "width_meters"),
      height_meters: readNumber(body.height_meters, "height_meters"),
      sill_height_meters: isFiniteNumber(body.sill_height_meters) ? body.sill_height_meters : 0.9,
      clearance_meters: isFiniteNumber(body.clearance_meters) ? body.clearance_meters : 0.05,
    };
    if (payload.offset_meters < 0.0) {
      return NextResponse.json({ success: false, error: "offset_meters must not be negative." }, { status: 400 });
    }
    if (payload.width_meters <= 0.0 || payload.height_meters <= 0.0) {
      return NextResponse.json({ success: false, error: "width_meters and height_meters must be greater than zero." }, { status: 400 });
    }
    if (payload.sill_height_meters < 0.0) {
      return NextResponse.json({ success: false, error: "sill_height_meters must not be negative." }, { status: 400 });
    }

    const config = await ensureDevConfiguration();
    const workDir = await mkdtemp(path.join(os.tmpdir(), "tbe-edit-"));
    const commandPath = path.join(workDir, "insert_window.json");
    const outputDir = path.join(workDir, "export");
    await writeFile(commandPath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");

    let stdout = "";
    let stderr = "";
    try {
      const result = await execFileAsync(config.helper, [
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
      stdout = result.stdout;
      stderr = result.stderr;
    } catch (error) {
      const shellError = error as { stdout?: string; stderr?: string; message?: string };
      stdout = shellError.stdout ?? "";
      stderr = shellError.stderr ?? "";
      if (stdout.trim()) {
        try {
          const helperResult = JSON.parse(stdout.trim()) as HelperResult;
          if (!helperResult.success) {
            return NextResponse.json(
              {
                success: false,
                error: helperResult.error ?? stderr ?? shellError.message ?? "Helper failed.",
                stdout,
                stderr,
              },
              { status: 400 },
            );
          }
        } catch {
          // fall through to generic error below
        }
      }
      throw new Error(stderr || shellError.message || "Helper command failed.");
    }

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
      message:
        helperResult.validation?.errors && helperResult.validation.errors > 0
          ? "Window inserted, but validation reported errors."
          : "Window inserted successfully.",
      stdout,
      stderr,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = message.includes("not configured") ? 503 : 500;
    return NextResponse.json({ success: false, error: message }, { status });
  }
}
