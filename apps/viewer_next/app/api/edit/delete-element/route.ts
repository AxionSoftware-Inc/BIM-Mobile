import { NextRequest, NextResponse } from "next/server";

import { executeEditRouteCommand, isFiniteNumber } from "../_bridge";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type DeleteElementRequest = {
  element_id?: unknown;
};

export async function POST(request: NextRequest) {
  let body: DeleteElementRequest;
  try {
    body = (await request.json()) as DeleteElementRequest;
  } catch {
    return NextResponse.json({ success: false, command: "delete_element", message: "Request body must be JSON.", validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: "Request body must be JSON." }, { status: 400 });
  }

  try {
    const elementId = isFiniteNumber(body.element_id) ? body.element_id : Number(body.element_id);
    if (!Number.isFinite(elementId) || elementId <= 0) {
      throw new Error("element_id is required");
    }
    const envelope = await executeEditRouteCommand("delete_element", { element_id: Math.trunc(elementId) });
    return NextResponse.json(envelope.body, { status: envelope.status });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return NextResponse.json({ success: false, command: "delete_element", message, validation: { errors: 0, warnings: 0 }, updatedFiles: [], output: "", error: message }, { status: message.includes("not configured") ? 503 : 500 });
  }
}
