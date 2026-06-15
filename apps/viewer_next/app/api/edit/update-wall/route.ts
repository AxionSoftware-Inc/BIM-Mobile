import { NextRequest, NextResponse } from "next/server";

import { executeEditRouteCommand, isFiniteNumber, readNumber } from "../_bridge";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type RequestBody = {
  wall_id?: unknown;
  height_meters?: unknown;
  thickness_meters?: unknown;
  wall_type_id?: unknown;
};

export async function POST(request: NextRequest) {
  let body: RequestBody;
  try {
    body = (await request.json()) as RequestBody;
  } catch {
    return NextResponse.json({ success: false, command: "update_wall_properties", message: "Request body must be JSON.", validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: "Request body must be JSON." }, { status: 400 });
  }
  try {
    const wallId = isFiniteNumber(body.wall_id) ? body.wall_id : Number(body.wall_id);
    if (!Number.isFinite(wallId) || wallId <= 0) {
      throw new Error("wall_id is required");
    }
    const payload: Record<string, unknown> = {
      wall_id: Math.trunc(wallId),
      height_meters: readNumber(body.height_meters, "height_meters"),
      thickness_meters: readNumber(body.thickness_meters, "thickness_meters"),
    };
    if (isFiniteNumber(body.wall_type_id) && body.wall_type_id > 0) {
      payload.wall_type_id = Math.trunc(body.wall_type_id);
    }
    if (Number(payload.height_meters) <= 0 || Number(payload.thickness_meters) <= 0) {
      return NextResponse.json({ success: false, command: "update_wall_properties", message: "height_meters and thickness_meters must be greater than zero.", validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: "height_meters and thickness_meters must be greater than zero." }, { status: 400 });
    }
    const envelope = await executeEditRouteCommand("update_wall_properties", payload);
    return NextResponse.json(envelope.body, { status: envelope.status });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return NextResponse.json({ success: false, command: "update_wall_properties", message, validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}
