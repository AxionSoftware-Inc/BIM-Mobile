import { NextRequest, NextResponse } from "next/server";

import { executeEditRouteCommand, isFiniteNumber, readNumber } from "../_bridge";

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

export async function POST(request: NextRequest) {
  let body: InsertWindowRequest;
  try {
    body = (await request.json()) as InsertWindowRequest;
  } catch {
    return NextResponse.json({ success: false, command: "insert_window", message: "Request body must be JSON.", validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: "Request body must be JSON." }, { status: 400 });
  }

  try {
    const hostWallId = isFiniteNumber(body.host_wall_id) ? body.host_wall_id : Number(body.host_wall_id);
    if (!Number.isFinite(hostWallId) || hostWallId <= 0) {
      throw new Error("host_wall_id is required");
    }
    const payload = {
      host_wall_id: Math.trunc(hostWallId),
      offset_meters: readNumber(body.offset_meters, "offset_meters"),
      width_meters: readNumber(body.width_meters, "width_meters"),
      height_meters: readNumber(body.height_meters, "height_meters"),
      sill_height_meters: isFiniteNumber(body.sill_height_meters) ? body.sill_height_meters : 0.9,
      clearance_meters: isFiniteNumber(body.clearance_meters) ? body.clearance_meters : 0.05,
    };
    if (payload.offset_meters < 0.0) {
      return NextResponse.json({ success: false, command: "insert_window", message: "offset_meters must not be negative.", validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: "offset_meters must not be negative." }, { status: 400 });
    }
    if (payload.width_meters <= 0.0 || payload.height_meters <= 0.0) {
      return NextResponse.json({ success: false, command: "insert_window", message: "width_meters and height_meters must be greater than zero.", validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: "width_meters and height_meters must be greater than zero." }, { status: 400 });
    }
    if (payload.sill_height_meters < 0.0) {
      return NextResponse.json({ success: false, command: "insert_window", message: "sill_height_meters must not be negative.", validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: "sill_height_meters must not be negative." }, { status: 400 });
    }

    const envelope = await executeEditRouteCommand("insert_window", payload);
    return NextResponse.json(envelope.body, { status: envelope.status });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return NextResponse.json({ success: false, command: "insert_window", message, validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}
