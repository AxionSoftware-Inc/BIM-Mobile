import { NextRequest, NextResponse } from "next/server";

import { executeEditRouteCommand, isFiniteNumber } from "../_bridge";

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

export async function POST(request: NextRequest) {
  let body: CreateWallRequest;
  try {
    body = (await request.json()) as CreateWallRequest;
  } catch {
    return NextResponse.json(
      {
        success: false,
        command: "create_wall",
        message: "Request body must be JSON.",
        validation: { errors: 0, warnings: 0 },
        updatedFiles: [],
        output: "",
        error: "Request body must be JSON.",
      },
      { status: 400 },
    );
  }

  try {
    const start = body.start ?? {};
    const end = body.end ?? {};
    const startX = Number(start.x);
    const startY = Number(start.y);
    const endX = Number(end.x);
    const endY = Number(end.y);
    if (!Number.isFinite(startX) || !Number.isFinite(startY) || !Number.isFinite(endX) || !Number.isFinite(endY)) {
      return NextResponse.json(
        {
          success: false,
          command: "create_wall",
          message: "start.x/start.y/end.x/end.y must be finite numbers.",
          validation: { errors: 0, warnings: 0 },
          updatedFiles: [],
          output: "",
          error: "start.x/start.y/end.x/end.y must be finite numbers.",
        },
        { status: 400 },
      );
    }
    const payload = {
      start: { x: startX, y: startY },
      end: { x: endX, y: endY },
      height_meters: isFiniteNumber(body.height_meters) ? body.height_meters : 3.0,
      thickness_meters: isFiniteNumber(body.thickness_meters) ? body.thickness_meters : 0.2,
      ...(isFiniteNumber(body.level_id) ? { level_id: body.level_id } : {}),
      ...(isFiniteNumber(body.wall_type_id) ? { wall_type_id: body.wall_type_id } : {}),
    };
    const length = Math.hypot(payload.end.x - payload.start.x, payload.end.y - payload.start.y);
    if (length < 0.05) {
      return NextResponse.json(
        {
          success: false,
          command: "create_wall",
          message: "Wall length is too short.",
          validation: { errors: 0, warnings: 0 },
          updatedFiles: [],
          output: "",
          error: "Wall length is too short.",
        },
        { status: 400 },
      );
    }

    const envelope = await executeEditRouteCommand("create_wall", payload);
    return NextResponse.json(envelope.body, { status: envelope.status });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return NextResponse.json(
      {
        success: false,
        command: "create_wall",
        message,
        validation: { errors: 0, warnings: 0 },
        updatedFiles: [],
        output: "",
        error: message,
      },
      { status: message.includes("not configured") ? 503 : 500 },
    );
  }
}
