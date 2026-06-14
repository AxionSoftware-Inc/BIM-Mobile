import { mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { NextRequest, NextResponse } from "next/server";

import { copyArtifactsToSampleDir, ensureDevConfiguration, isFiniteNumber, readNumber, refreshWorkingProject, runHelperCommand } from "../_bridge";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type RequestBody = {
  window_id?: unknown;
  offset_meters?: unknown;
  width_meters?: unknown;
  height_meters?: unknown;
  sill_height_meters?: unknown;
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
    const windowId = isFiniteNumber(body.window_id) ? body.window_id : Number(body.window_id);
    if (!Number.isFinite(windowId) || windowId <= 0) {
      throw new Error("window_id is required");
    }
    const payload = {
      type: "update_window_properties",
      window_id: Math.trunc(windowId),
      offset_meters: readNumber(body.offset_meters, "offset_meters"),
      width_meters: readNumber(body.width_meters, "width_meters"),
      height_meters: readNumber(body.height_meters, "height_meters"),
      sill_height_meters: isFiniteNumber(body.sill_height_meters) ? body.sill_height_meters : 0.9,
    };
    const config = await ensureDevConfiguration();
    const workDir = await mkdtemp(path.join(os.tmpdir(), "tbe-edit-"));
    const commandPath = path.join(workDir, "update_window.json");
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
    return NextResponse.json({ success: true, request: payload, validation: result.validation ?? { issues: 0, warnings: 0, errors: 0 }, artifactPaths: result.artifact_paths, commandOutput: result, message: "Window updated successfully.", stdout, stderr });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = message.includes("not configured") ? 503 : 500;
    return NextResponse.json({ success: false, error: message }, { status });
  }
}
