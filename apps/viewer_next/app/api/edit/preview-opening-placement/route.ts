import { NextResponse } from "next/server";
import { computeOpeningPlacementPreview } from "../../../../lib/openingPlacement";
import { isFiniteNumber, readNumber } from "../_bridge";

type PreviewRequestBody = {
  project_json?: unknown;
  host_wall?: unknown;
  host_wall_id?: unknown;
  kind?: unknown;
  requested_offset_meters?: unknown;
  width_meters?: unknown;
  height_meters?: unknown;
  sill_height_meters?: unknown;
  clearance_meters?: unknown;
  svg_point?: unknown;
  model_point?: unknown;
};

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as PreviewRequestBody;
    const hostWallId = readNumber(body.host_wall_id, "host_wall_id");
    const kind = body.kind === "window" ? "window" : body.kind === "door" ? "door" : null;
    if (!kind) {
      return NextResponse.json(
        {
          success: false,
          command: "preview_insert_door",
          message: "kind must be door or window.",
          validation: { errors: 0, warnings: 0 },
          updatedFiles: [],
          output: "",
          error: "kind must be door or window.",
        },
        { status: 400 },
      );
    }

    const requestedOffset = readNumber(body.requested_offset_meters, "requested_offset_meters");
    const widthMeters = readNumber(body.width_meters, "width_meters");
    const heightMeters = readNumber(body.height_meters, "height_meters");
    const clearanceMeters = body.clearance_meters === undefined ? 0.05 : readNumber(body.clearance_meters, "clearance_meters");
    const sillHeightMeters = body.sill_height_meters === undefined ? undefined : readNumber(body.sill_height_meters, "sill_height_meters");

    if (requestedOffset < 0 || widthMeters <= 0 || heightMeters <= 0 || clearanceMeters < 0) {
      return NextResponse.json(
        {
          success: false,
          command: kind === "door" ? "preview_insert_door" : "preview_insert_window",
          message: "requested_offset_meters, width_meters, height_meters, and clearance_meters must be valid.",
          validation: { errors: 0, warnings: 0 },
          updatedFiles: [],
          output: "",
          error: "requested_offset_meters, width_meters, height_meters, and clearance_meters must be valid.",
        },
        { status: 400 },
      );
    }
    if (kind === "window" && sillHeightMeters !== undefined && sillHeightMeters < 0) {
      return NextResponse.json(
        {
          success: false,
          command: "preview_insert_window",
          message: "sill_height_meters must not be negative.",
          validation: { errors: 0, warnings: 0 },
          updatedFiles: [],
          output: "",
          error: "sill_height_meters must not be negative.",
        },
        { status: 400 },
      );
    }

    const preview = computeOpeningPlacementPreview({
      project_json: body.project_json ?? null,
      host_wall: body.host_wall ?? null,
      host_wall_id: hostWallId,
      kind,
      requested_offset_meters: requestedOffset,
      width_meters: widthMeters,
      height_meters: heightMeters,
      sill_height_meters: sillHeightMeters,
      clearance_meters: clearanceMeters,
      svg_point: isFiniteNumber((body.svg_point as { x?: unknown } | undefined)?.x) && isFiniteNumber((body.svg_point as { y?: unknown } | undefined)?.y)
        ? { x: Number((body.svg_point as { x?: number }).x), y: Number((body.svg_point as { y?: number }).y) }
        : null,
      model_point: isFiniteNumber((body.model_point as { x?: unknown } | undefined)?.x) && isFiniteNumber((body.model_point as { y?: unknown } | undefined)?.y)
        ? { x: Number((body.model_point as { x?: number }).x), y: Number((body.model_point as { y?: number }).y) }
        : null,
    });

    return NextResponse.json(
      {
        success: true,
        command: preview.command,
        message: preview.message,
        validation: { errors: preview.can_place && preview.valid ? 0 : 0, warnings: preview.warnings.length },
        updatedFiles: [],
        output: JSON.stringify(preview),
        error: null,
        preview,
      },
      { status: 200 },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return NextResponse.json(
      {
        success: false,
        command: "preview_insert_door",
        message,
        validation: { errors: 0, warnings: 0 },
        updatedFiles: [],
        output: "",
        error: message,
      },
      { status: 500 },
    );
  }
}
