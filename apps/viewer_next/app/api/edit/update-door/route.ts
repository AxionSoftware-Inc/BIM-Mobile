import { NextRequest, NextResponse } from "next/server";

import { executeEditRouteCommand, isFiniteNumber, readNumber } from "../_bridge";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type RequestBody = {
  door_id?: unknown;
  offset_meters?: unknown;
  width_meters?: unknown;
  height_meters?: unknown;
};

export async function POST(request: NextRequest) {
  let body: RequestBody;
  try {
    body = (await request.json()) as RequestBody;
  } catch {
    return NextResponse.json({ success: false, command: "update_door_properties", message: "Request body must be JSON.", validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: "Request body must be JSON." }, { status: 400 });
  }
  try {
    const doorId = isFiniteNumber(body.door_id) ? body.door_id : Number(body.door_id);
    if (!Number.isFinite(doorId) || doorId <= 0) {
      throw new Error("door_id is required");
    }
    const payload = {
      door_id: Math.trunc(doorId),
      offset_meters: readNumber(body.offset_meters, "offset_meters"),
      width_meters: readNumber(body.width_meters, "width_meters"),
      height_meters: readNumber(body.height_meters, "height_meters"),
    };
    if (payload.offset_meters < 0.0 || payload.width_meters <= 0.0 || payload.height_meters <= 0.0) {
      return NextResponse.json({ success: false, command: "update_door_properties", message: "offset_meters, width_meters, and height_meters must be valid.", validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: "offset_meters, width_meters, and height_meters must be valid." }, { status: 400 });
    }
    const envelope = await executeEditRouteCommand("update_door_properties", payload);
    return NextResponse.json(envelope.body, { status: envelope.status });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return NextResponse.json({ success: false, command: "update_door_properties", message, validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}
