export type SvgPoint = { x: number; y: number };

export type ProjectPoint = { x: number; y: number };

export type WallAxisPoint = { x: number; y: number };

export type WallAxis = {
  start: WallAxisPoint;
  end: WallAxisPoint;
};

export type OpeningInterval = {
  start: number;
  end: number;
};

export type OpeningBlockedInterval = OpeningInterval & {
  reason: string;
  element_id?: number | null;
};

export type OpeningPlacementPreview = {
  success: boolean;
  command: "preview_insert_door" | "preview_insert_window";
  kind: "door" | "window";
  host_wall_id: number | null;
  requested_offset_meters: number;
  adjusted_offset_meters: number;
  can_place: boolean;
  valid: boolean;
  message: string;
  wall_length_meters: number;
  wall_thickness_meters: number;
  free_intervals: OpeningInterval[];
  blocked_intervals: OpeningBlockedInterval[];
  warnings: string[];
  svg_point: SvgPoint | null;
  model_point: ProjectPoint | null;
  wall_axis: WallAxis | null;
};

export type OpeningPlacementRequest = {
  project_json: unknown;
  host_wall?: unknown;
  host_wall_id: number;
  kind: "door" | "window";
  requested_offset_meters: number;
  width_meters: number;
  height_meters: number;
  sill_height_meters?: number;
  clearance_meters?: number;
  svg_point?: SvgPoint | null;
  model_point?: ProjectPoint | null;
};

type JsonObject = Record<string, unknown>;

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function toNumber(value: unknown, fallback = 0) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function asArray<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

function projectDocument(projectJson: unknown): JsonObject | null {
  if (!isObject(projectJson)) {
    return null;
  }
  const documentValue = projectJson.document;
  return isObject(documentValue) ? documentValue : null;
}

function projectElements(projectJson: unknown): JsonObject[] {
  const document = projectDocument(projectJson);
  return document ? asArray<JsonObject>(document.elements) : [];
}

export function findProjectWall(projectJson: unknown, wallId: number) {
  return projectElements(projectJson).find((element) => toNumber(element.id, -1) === wallId && String(element.kind ?? "").toLowerCase() === "wall") ?? null;
}

export function extractWallAxis(wall: JsonObject | null): WallAxis | null {
  if (!wall || !isObject(wall.axis)) {
    return null;
  }
  const axis = wall.axis;
  if (!isObject(axis.start) || !isObject(axis.end)) {
    return null;
  }
  const start = axis.start;
  const end = axis.end;
  const startX = toNumber(start.x, NaN);
  const startY = toNumber(start.y, NaN);
  const endX = toNumber(end.x, NaN);
  const endY = toNumber(end.y, NaN);
  if (![startX, startY, endX, endY].every(Number.isFinite)) {
    return null;
  }
  return {
    start: { x: startX, y: startY },
    end: { x: endX, y: endY },
  };
}

export function wallThicknessMeters(wall: JsonObject | null, fallback = 0.2) {
  if (!wall) {
    return fallback;
  }
  return Math.max(0.01, toNumber(wall.thickness ?? wall.thickness_meters, fallback));
}

export function wallOpenings(wall: JsonObject | null) {
  if (!wall) {
    return [];
  }
  return asArray<JsonObject>(wall.openings);
}

export function wallLength(axis: WallAxis) {
  return Math.hypot(axis.end.x - axis.start.x, axis.end.y - axis.start.y);
}

export function projectPointToWallAxis(point: ProjectPoint, axis: WallAxis) {
  const dx = axis.end.x - axis.start.x;
  const dy = axis.end.y - axis.start.y;
  const length = Math.hypot(dx, dy);
  if (length <= 1.0e-9) {
    return null;
  }
  const ux = dx / length;
  const uy = dy / length;
  const vx = point.x - axis.start.x;
  const vy = point.y - axis.start.y;
  const offset = (vx * ux) + (vy * uy);
  const nearest: ProjectPoint = {
    x: axis.start.x + (ux * offset),
    y: axis.start.y + (uy * offset),
  };
  const distance = Math.hypot(point.x - nearest.x, point.y - nearest.y);
  return { offset, nearest, distance, length };
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function mergeIntervals(intervals: OpeningInterval[]) {
  const sorted = [...intervals]
    .filter((interval) => Number.isFinite(interval.start) && Number.isFinite(interval.end) && interval.end > interval.start)
    .sort((left, right) => left.start - right.start);
  const merged: OpeningInterval[] = [];
  for (const interval of sorted) {
    const last = merged[merged.length - 1];
    if (!last || interval.start > last.end) {
      merged.push({ ...interval });
    } else {
      last.end = Math.max(last.end, interval.end);
    }
  }
  return merged;
}

function subtractIntervals(base: OpeningInterval[], blocked: OpeningInterval[]) {
  const result: OpeningInterval[] = [];
  const mergedBlocked = mergeIntervals(blocked);
  for (const interval of base) {
    let cursor = interval.start;
    for (const cut of mergedBlocked) {
      if (cut.end <= cursor || cut.start >= interval.end) {
        continue;
      }
      if (cut.start > cursor) {
        result.push({ start: cursor, end: Math.min(cut.start, interval.end) });
      }
      cursor = Math.max(cursor, cut.end);
      if (cursor >= interval.end) {
        break;
      }
    }
    if (cursor < interval.end) {
      result.push({ start: cursor, end: interval.end });
    }
  }
  return result.filter((interval) => interval.end > interval.start);
}

function nearestValueInIntervals(value: number, intervals: OpeningInterval[]) {
  for (const interval of intervals) {
    if (value >= interval.start && value <= interval.end) {
      return value;
    }
  }
  let best = value;
  let bestDistance = Number.POSITIVE_INFINITY;
  for (const interval of intervals) {
    const candidate = value < interval.start ? interval.start : interval.end;
    const distance = Math.abs(value - candidate);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = candidate;
    }
  }
  return Number.isFinite(bestDistance) ? best : value;
}

export function computeOpeningPlacementPreview(request: OpeningPlacementRequest): OpeningPlacementPreview {
  const hostWallObject = isObject(request.host_wall) ? request.host_wall : null;
  const wall = hostWallObject ?? findProjectWall(request.project_json, request.host_wall_id);
  const axis = extractWallAxis(wall);
  const kind = request.kind;
  const command = kind === "door" ? "preview_insert_door" : "preview_insert_window";
  const width = Math.max(0, request.width_meters);
  const clearance = Math.max(0, request.clearance_meters ?? 0);
  const requested = request.requested_offset_meters;
  const modelPoint = request.model_point ?? null;
  const svgPoint = request.svg_point ?? null;

  if (!wall || !axis) {
    return {
      success: false,
      command,
      kind,
      host_wall_id: Number.isFinite(request.host_wall_id) ? request.host_wall_id : null,
      requested_offset_meters: requested,
      adjusted_offset_meters: requested,
      can_place: false,
      valid: false,
      message: "Host wall not found or wall axis is missing.",
      wall_length_meters: 0,
      wall_thickness_meters: 0.2,
      free_intervals: [],
      blocked_intervals: [],
      warnings: ["No wall axis available."],
      svg_point: svgPoint,
      model_point: modelPoint,
      wall_axis: axis,
    };
  }

  const length = wallLength(axis);
  const thickness = wallThicknessMeters(wall, 0.2);
  const edgeInset = (width / 2) + clearance;
  const freeBase = edgeInset < length - edgeInset
    ? [{ start: edgeInset, end: length - edgeInset }]
    : [];

  const blockedIntervals: OpeningBlockedInterval[] = [];
  for (const opening of wallOpenings(wall)) {
    const openingOffset = toNumber(opening.offset_meters ?? opening.offset, NaN);
    const openingWidth = Math.max(0, toNumber(opening.width_meters ?? opening.width, 0));
    if (!Number.isFinite(openingOffset) || openingWidth <= 0) {
      continue;
    }
    const elementId = toNumber(opening.element_id, NaN);
    blockedIntervals.push({
      start: Math.max(0, openingOffset - (openingWidth / 2) - clearance),
      end: Math.min(length, openingOffset + (openingWidth / 2) + clearance),
      reason: `${String(opening.kind ?? "Opening")} opening`,
      element_id: Number.isFinite(elementId) ? elementId : null,
    });
  }

  const freeIntervals = subtractIntervals(freeBase, blockedIntervals);
  const adjusted = freeIntervals.length > 0 ? clamp(nearestValueInIntervals(requested, freeIntervals), 0, length) : requested;
  const valid = freeIntervals.some((interval) => requested >= interval.start && requested <= interval.end);
  const canPlace = freeIntervals.length > 0;
  const warnings: string[] = [];
  if (!valid && canPlace) {
    warnings.push(`Requested offset ${requested.toFixed(2)} m is blocked; nearest valid offset is ${adjusted.toFixed(2)} m.`);
  }
  if (!canPlace) {
    warnings.push("No free placement interval is available on this wall.");
  }
  if (kind === "window" && request.sill_height_meters !== undefined && request.sill_height_meters < 0) {
    warnings.push("Sill height is invalid.");
  }

  const message = canPlace
    ? valid
      ? `Placement is valid at ${requested.toFixed(2)} m.`
      : `Placement adjusted to ${adjusted.toFixed(2)} m.`
    : "No free placement interval is available on this wall.";

  return {
    success: true,
    command,
    kind,
    host_wall_id: request.host_wall_id,
    requested_offset_meters: requested,
    adjusted_offset_meters: adjusted,
    can_place: canPlace,
    valid,
    message,
    wall_length_meters: length,
    wall_thickness_meters: thickness,
    free_intervals: freeIntervals,
    blocked_intervals: blockedIntervals,
    warnings,
    svg_point: svgPoint,
    model_point: modelPoint,
    wall_axis: axis,
  };
}
