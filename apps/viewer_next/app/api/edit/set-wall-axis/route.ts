import { NextRequest, NextResponse } from "next/server";

import { executeEditRouteCommand, isFiniteNumber, readNumber } from "../_bridge";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type RequestBody = {
  wall_id?: unknown;
  start?: { x?: unknown; y?: unknown };
  end?: { x?: unknown; y?: unknown };
};

export async function POST(request: NextRequest) {
  let body: RequestBody;
  try {
    body = (await request.json()) as RequestBody;
  } catch {
    return NextResponse.json({ success: false, command: "set_wall_axis", message: "Request body must be JSON.", validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: "Request body must be JSON." }, { status: 400 });
  }
  try {
    const wallId = isFiniteNumber(body.wall_id) ? body.wall_id : Number(body.wall_id);
    if (!Number.isFinite(wallId) || wallId <= 0) {
      throw new Error("wall_id is required");
    }
    const start = body.start ?? {};
    const end = body.end ?? {};
    const payload = {
      wall_id: Math.trunc(wallId),
      start: { x: readNumber(start.x, "start.x"), y: readNumber(start.y, "start.y") },
      end: { x: readNumber(end.x, "end.x"), y: readNumber(end.y, "end.y") },
    };
    const length = Math.hypot(payload.end.x - payload.start.x, payload.end.y - payload.start.y);
    if (length < 0.05) {
      return NextResponse.json({ success: false, command: "set_wall_axis", message: "Wall axis is too short.", validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: "Wall axis is too short." }, { status: 400 });
    }
    const envelope = await executeEditRouteCommand("set_wall_axis", payload);
    return NextResponse.json(envelope.body, { status: envelope.status });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return NextResponse.json({ success: false, command: "set_wall_axis", message, validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}
