import { NextRequest, NextResponse } from "next/server";

import { executeEditRouteCommand, isFiniteNumber, readNumber } from "../_bridge";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type RequestBody = {
  opening_id?: unknown;
  offset_meters?: unknown;
};

export async function POST(request: NextRequest) {
  let body: RequestBody;
  try {
    body = (await request.json()) as RequestBody;
  } catch {
    return NextResponse.json({ success: false, command: "move_hosted_opening", message: "Request body must be JSON.", validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: "Request body must be JSON." }, { status: 400 });
  }
  try {
    const openingId = isFiniteNumber(body.opening_id) ? body.opening_id : Number(body.opening_id);
    if (!Number.isFinite(openingId) || openingId <= 0) {
      throw new Error("opening_id is required");
    }
    const payload = {
      opening_id: Math.trunc(openingId),
      offset_meters: readNumber(body.offset_meters, "offset_meters"),
    };
    if (payload.offset_meters < 0.0) {
      return NextResponse.json({ success: false, command: "move_hosted_opening", message: "offset_meters must not be negative.", validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: "offset_meters must not be negative." }, { status: 400 });
    }
    const envelope = await executeEditRouteCommand("move_hosted_opening", payload);
    return NextResponse.json(envelope.body, { status: envelope.status });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return NextResponse.json({ success: false, command: "move_hosted_opening", message, validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}
