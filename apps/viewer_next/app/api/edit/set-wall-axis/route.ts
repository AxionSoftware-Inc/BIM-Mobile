import { mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { NextRequest, NextResponse } from "next/server";

import { copyArtifactsToSampleDir, ensureDevConfiguration, isFiniteNumber, readNumber, refreshWorkingProject, runHelperCommand } from "../_bridge";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type RequestBody = {
  wall_id?: unknown;
  start?: { x?: unknown; y?: unknown };
  end?: { x?: unknown; y?: unknown };
};

type HelperResult = {
  success: boolean;
  error?: string;
  validation?: { issues?: number; warnings?: number; errors?: number };
  artifact_paths?: { project_json?: string; debug_report_json?: string; floorplan_svg?: string; walls_obj?: string; metadata_json?: string };
};

export async function POST(request: NextRequest) {
  let body: RequestBody;
  try {
    body = (await request.json()) as RequestBody;
  } catch {
    return NextResponse.json({ success: false, error: "Request body must be JSON." }, { status: 400 });
  }
  try {
    const wallId = isFiniteNumber(body.wall_id) ? body.wall_id : Number(body.wall_id);
    if (!Number.isFinite(wallId) || wallId <= 0) {
      throw new Error("wall_id is required");
    }
    const payload = {
      type: "set_wall_axis",
      wall_id: Math.trunc(wallId),
      start: {
        x: readNumber(body.start?.x, "start.x"),
        y: readNumber(body.start?.y, "start.y"),
      },
      end: {
        x: readNumber(body.end?.x, "end.x"),
        y: readNumber(body.end?.y, "end.y"),
      },
    };
    const config = await ensureDevConfiguration();
    const workDir = await mkdtemp(path.join(os.tmpdir(), "tbe-edit-"));
    const commandPath = path.join(workDir, "set_wall_axis.json");
    const outputDir = path.join(workDir, "export");
    await writeFile(commandPath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
    const { stdout, stderr, result } = await runHelperCommand<HelperResult>(config.helper, config.repoRoot, config.workingProject, commandPath, outputDir);
    if (!result.success) {
      throw new Error(result.error ?? stderr ?? "Helper failed.");
    }
    if (!result.artifact_paths) {
      throw new Error("Helper did not return artifact paths.");
    }
    await copyArtifactsToSampleDir(config.sampleDir, result.artifact_paths);
    await refreshWorkingProject(config.workingProject, result.artifact_paths);
    return NextResponse.json({ success: true, request: payload, validation: result.validation ?? { issues: 0, warnings: 0, errors: 0 }, artifactPaths: result.artifact_paths, commandOutput: result, message: "Wall axis updated successfully.", stdout, stderr });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = message.includes("not configured") ? 503 : 500;
    return NextResponse.json({ success: false, error: message }, { status });
  }
}
