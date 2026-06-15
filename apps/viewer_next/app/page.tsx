"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import ObjViewer from "./ObjViewer";
import {
  computeOpeningPlacementPreview,
  extractWallAxis,
  projectPointToWallAxis,
  wallThicknessMeters,
  type OpeningPlacementPreview,
  type SvgPoint,
  type WallAxis,
} from "../lib/openingPlacement";

type JsonPrimitive = string | number | boolean | null;
type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
type JsonObject = { [key: string]: JsonValue };

type ProjectSummary = {
  projectName: string;
  schemaVersion: number | null;
  engineVersion: string | null;
};

type ValidationIssue = {
  message?: string;
  severity?: string;
  elementId?: string | number;
  category?: string;
  [key: string]: JsonValue | undefined;
};

type ScheduleRow = Record<string, JsonValue>;

type DebugElement = {
  id?: number;
  name?: string;
  kind?: string;
  dirty?: boolean;
  [key: string]: JsonValue | undefined;
};

type DebugReport = {
  documentName: string;
  elementCount: number;
  elements: DebugElement[];
  validation: {
    issues: ValidationIssue[] | number;
    warnings: ValidationIssue[] | number;
    errors: ValidationIssue[] | number;
  };
  schedules: {
    walls: ScheduleRow[];
    openings: ScheduleRow[];
    rooms: ScheduleRow[];
    slabs: ScheduleRow[];
    roofs: ScheduleRow[];
    columns: ScheduleRow[];
    beams: ScheduleRow[];
    stairs: ScheduleRow[];
    floors: ScheduleRow[];
    ceilings: ScheduleRow[];
    material_takeoff: ScheduleRow[];
    material_takeoff_by_category: ScheduleRow[];
  };
  materials: JsonValue[];
  wall_types: JsonValue[];
  issues?: JsonValue[];
};

type ViewerData = {
  project: ProjectSummary;
  debug: DebugReport;
  projectJson: JsonObject | null;
  svg: string;
  obj: string | null;
  metadata: JsonObject | null;
};

type Selection =
  | { kind: "none" }
  | { kind: "category"; label: string }
  | { kind: "element"; label: string; value: DebugElement; svgMeta?: SvgMetadata | null }
  | { kind: "schedule"; label: string; rows: ScheduleRow[] }
  | { kind: "material"; label: string; value: unknown }
  | { kind: "validation"; label: string; value: unknown }
  | { kind: "svg-only"; label: string; svgMeta: SvgMetadata; approxPoint?: { x: number; y: number } | null };

type SelectionDetails = {
  title: string;
  body: string;
};

type SvgMetadata = {
  elementId: string;
  kind: string | null;
  hitKind: string | null;
  svgId: string | null;
};

type SvgViewBox = {
  minX: number;
  minY: number;
  width: number;
  height: number;
};

type ArtifactStats = {
  svgElementCount: number;
  objVertexCount: number;
  objFaceCount: number;
  objObjectCount: number;
};

const kindFilterKeys = [
  "wall",
  "room",
  "door",
  "window",
  "slab",
  "floor",
  "ceiling",
  "roof",
  "column",
  "beam",
  "stair",
] as const;

type KindFilterKey = (typeof kindFilterKeys)[number];

const sampleFiles = {
  projectJson: "/sample/project.json",
  debugJson: "/sample/debug_report.json",
  svg: "/sample/floorplan.svg",
  obj: "/sample/walls.obj",
  metadata: "/sample/metadata.json",
};

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function safeJsonParse(text: string): JsonObject | null {
  try {
    const parsed: unknown = JSON.parse(text);
    return isObject(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function safeJsonStringify(value: unknown) {
  return JSON.stringify(value ?? null, null, 2);
}

function toNumber(value: unknown, fallback = 0) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function toStringValue(value: unknown, fallback = "-") {
  return typeof value === "string" && value.length > 0 ? value : fallback;
}

function asArray<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

function normalizeProjectSummary(projectJson: JsonObject | null, metadata: JsonObject | null, debug: DebugReport | null): ProjectSummary {
  return {
    projectName:
      toStringValue(projectJson?.project_name, "") ||
      toStringValue(metadata?.project_name, "") ||
      (debug ? toStringValue(debug.documentName, "") : "") ||
      "Untitled Project",
    schemaVersion:
      typeof projectJson?.schema_version === "number"
        ? projectJson.schema_version
        : typeof metadata?.schema_version === "number"
          ? metadata.schema_version
          : null,
    engineVersion:
      toStringValue(projectJson?.engine_version, "") ||
      toStringValue(metadata?.engine_version, "") ||
      null,
  };
}

function normalizeDebugReport(value: unknown): DebugReport {
  const report = isObject(value) ? value : {};
  const schedules = isObject(report.schedules) ? report.schedules : {};
  const validation = isObject(report.validation) ? report.validation : {};
  return {
    documentName: toStringValue(report.documentName ?? report.document_name, "Untitled Document"),
    elementCount: toNumber(report.elementCount, asArray(report.elements).length),
    elements: asArray<DebugElement>(report.elements),
    validation: {
      issues: Array.isArray(validation.issues) ? (validation.issues as ValidationIssue[]) : toNumber(validation.issues),
      warnings: Array.isArray(validation.warnings) ? (validation.warnings as ValidationIssue[]) : toNumber(validation.warnings),
      errors: Array.isArray(validation.errors) ? (validation.errors as ValidationIssue[]) : toNumber(validation.errors),
    },
    schedules: {
      walls: asArray<ScheduleRow>(schedules.walls),
      openings: asArray<ScheduleRow>(schedules.openings),
      rooms: asArray<ScheduleRow>(schedules.rooms),
      slabs: asArray<ScheduleRow>(schedules.slabs),
      roofs: asArray<ScheduleRow>(schedules.roofs),
      columns: asArray<ScheduleRow>(schedules.columns),
      beams: asArray<ScheduleRow>(schedules.beams),
      stairs: asArray<ScheduleRow>(schedules.stairs),
      floors: asArray<ScheduleRow>(schedules.floors),
      ceilings: asArray<ScheduleRow>(schedules.ceilings),
      material_takeoff: asArray<ScheduleRow>(schedules.material_takeoff),
      material_takeoff_by_category: asArray<ScheduleRow>(schedules.material_takeoff_by_category),
    },
    materials: asArray<JsonValue>(report.materials),
    wall_types: asArray<JsonValue>(report.wall_types),
    issues: asArray<JsonValue>(report.issues),
  };
}

function normalizeKindKey(value: unknown) {
  return typeof value === "string" && value.length > 0 ? value.trim().toLowerCase() : "unknown";
}

function displayKindLabel(value: unknown) {
  const kind = typeof value === "string" && value.length > 0 ? value.trim() : "Unknown";
  return kind[0].toUpperCase() + kind.slice(1).toLowerCase();
}

function formatDraftLength(start: { x: number; y: number }, end: { x: number; y: number }) {
  return Math.hypot(end.x - start.x, end.y - start.y);
}

function screenToHostPoint(
  clientX: number,
  clientY: number,
  rect: DOMRect,
  pan: { x: number; y: number },
  scale: number,
) {
  return {
    x: (clientX - rect.left - pan.x) / scale,
    y: (clientY - rect.top - pan.y) / scale,
  };
}

function extractSvgIds(svg: string) {
  const matches = [...svg.matchAll(/\b(?:id|data-element-id)="([^"]+)"/g)];
  return matches.map((match) => match[1]);
}

function extractObjStats(obj: string | null): ArtifactStats {
  if (!obj) {
    return {
      svgElementCount: 0,
      objVertexCount: 0,
      objFaceCount: 0,
      objObjectCount: 0,
    };
  }
  const vertexCount = (obj.match(/^v\s+/gm) ?? []).length;
  const faceCount = (obj.match(/^f\s+/gm) ?? []).length;
  const objectCount = (obj.match(/^[og]\s+/gm) ?? []).length;
  return {
    svgElementCount: 0,
    objVertexCount: vertexCount,
    objFaceCount: faceCount,
    objObjectCount: objectCount,
  };
}

function extractSvgViewBox(svg: string) {
  const match = svg.match(/viewBox="([^"]+)"/i);
  if (!match) {
    return null;
  }
  const values = match[1]
    .trim()
    .split(/[\s,]+/)
    .map((value) => Number(value));
  if (values.length !== 4 || values.some((value) => !Number.isFinite(value))) {
    return null;
  }
  const [minX, minY, width, height] = values;
  if (width <= 0 || height <= 0) {
    return null;
  }
  return { minX, minY, width, height } satisfies SvgViewBox;
}

function prepareSvgMarkup(svg: string) {
  if (!svg) {
    return svg;
  }
  return svg.replace(/^<svg\b([^>]*)>/i, (match, attrs) => {
    const cleanedAttrs = attrs
      .replace(/\swidth="[^"]*"/i, "")
      .replace(/\sheight="[^"]*"/i, "");
    return `<svg${cleanedAttrs} width="100%" height="100%" preserveAspectRatio="xMidYMid meet" style="display:block">`;
  });
}

function extractExportTimestamp(metadata: JsonObject | null) {
  const keys = ["export_timestamp", "exported_at", "updated_at", "timestamp"];
  for (const key of keys) {
    const value = metadata?.[key];
    if (typeof value === "string" && value.length > 0) {
      return value;
    }
  }
  return null;
}

function countValidationIssues(value: ValidationIssue[] | number) {
  return Array.isArray(value) ? value.length : value;
}

function validationIssuesList(value: ValidationIssue[] | number) {
  return Array.isArray(value) ? value : [];
}

function groupElements(elements: DebugElement[]) {
  const groups: Record<string, DebugElement[]> = {};
  for (const element of elements) {
    const key = displayKindLabel(element.kind);
    if (!groups[key]) {
      groups[key] = [];
    }
    groups[key].push(element);
  }
  return groups;
}

function buildSelectionDetails(
  selection: Selection,
  data: ViewerData | null,
): SelectionDetails | null {
  if (selection.kind === "none") {
    return null;
  }

  if (selection.kind === "category") {
    const elements = data?.debug.elements ?? [];
    return {
      title: selection.label,
      body: `Count: ${elements.filter((element) => displayKindLabel(element.kind) === selection.label).length}`,
    };
  }

  if (selection.kind === "schedule") {
    return {
      title: selection.label,
      body: safeJsonStringify(selection.rows),
    };
  }

  if (selection.kind === "material" || selection.kind === "validation") {
    return {
      title: selection.label,
      body: safeJsonStringify(selection.value),
    };
  }

  if (selection.kind === "svg-only") {
    return {
      title: selection.label,
      body: safeJsonStringify({
        elementId: selection.svgMeta.elementId,
        kind: selection.svgMeta.kind,
        hitKind: selection.svgMeta.hitKind,
        svgId: selection.svgMeta.svgId,
        approxPoint: selection.approxPoint ?? null,
        note: "SVG-only element. No matching debug_report entry was found.",
      }),
    };
  }

  const element = selection.value as DebugElement | null;
  const latestElement = element?.id != null ? data?.debug.elements.find((candidate) => candidate.id === element.id) ?? null : element;
  if (element?.id != null && latestElement === null) {
    return {
      title: `${element.kind ?? "Element"} ${element.id}`,
      body: safeJsonStringify({
        id: element.id,
        kind: element.kind ?? null,
        name: element.name ?? null,
        note: "Selected element is no longer present in the refreshed artifacts.",
      }),
    };
  }
  const project = data?.projectJson;
  const debug = data?.debug;
  const projectDocument = project && isObject(project.document) ? project.document : null;
  const projectElement = projectDocument
    ? asArray<JsonObject>(projectDocument.elements).find((candidate) => toNumber(candidate.id, -1) === latestElement?.id)
    : null;
  const schedules = debug?.schedules;

  const refs: string[] = [];
  const refRow = (rows: ScheduleRow[] | undefined, key: string) => {
    const index = rows?.findIndex((row) => toNumber(row[`${key}_id`], -1) === latestElement?.id || toNumber(row.element_id, -1) === latestElement?.id) ?? -1;
    if (index >= 0) {
      refs.push(`${key} schedule row ${index + 1}`);
    }
  };
  refRow(schedules?.walls, "wall");
  refRow(schedules?.openings, "opening");
  refRow(schedules?.rooms, "room");
  refRow(schedules?.slabs, "slab");
  refRow(schedules?.roofs, "roof");
  refRow(schedules?.columns, "column");
  refRow(schedules?.beams, "beam");
  refRow(schedules?.stairs, "stair");

  const takeoffRefs: string[] = [];
  const takeoffRows = debug?.schedules.material_takeoff ?? [];
  takeoffRows.forEach((row, index) => {
    const sourceIds = asArray<string | number>(row.source_element_ids);
    const hasMatch =
      sourceIds.some((sourceId) => Number(sourceId) === latestElement?.id) ||
      toNumber(row.element_id, -1) === latestElement?.id;
    if (hasMatch) {
      takeoffRefs.push(`material takeoff row ${index + 1}`);
    }
  });

  const details: Record<string, JsonValue> = {
    id: latestElement?.id ?? null,
    kind: latestElement?.kind ?? null,
    name: latestElement?.name ?? null,
    dirty: latestElement?.dirty ?? null,
    svgKind: selection.svgMeta?.kind ?? null,
    svgHitKind: selection.svgMeta?.hitKind ?? null,
    projectMatch: projectElement ?? null,
    scheduleRefs: refs,
    takeoffRefs,
  };

  if (latestElement?.kind === "Wall") {
    const wall = isObject(latestElement.wall) ? latestElement.wall : null;
    const projectWall = isObject(projectElement?.wall) ? projectElement.wall : null;
    const axis = isObject(projectWall?.axis) ? projectWall.axis : null;
    const start = isObject(axis?.start) ? axis.start : null;
    const end = isObject(axis?.end) ? axis.end : null;
    details.level_id = wall?.level_id ?? null;
    details.wall_type_id = wall?.wall_type_id ?? null;
    details.thickness = wall?.thickness ?? null;
    details.height = wall?.height ?? null;
    details.axis = wall?.axis ?? null;
    details.axis_start = start ?? null;
    details.axis_end = end ?? null;
    details.openings = asArray<ScheduleRow>(wall?.openings).length;
    details.joins = asArray<ScheduleRow>(wall?.joins).length;
    details.wall_type_summary = wall?.wall_type_name ?? wall?.wall_type_id ?? null;
    details.material_summary = wall?.material_summary ?? wall?.material_id ?? null;
  } else if (latestElement?.kind === "Door") {
    const door = isObject(latestElement.door) ? latestElement.door : null;
    const projectDoor = isObject(projectElement?.door) ? projectElement.door : null;
    details.level_id = door?.level_id ?? null;
    details.host_wall_id = door?.host_wall_id ?? null;
    details.offset = door?.offset ?? null;
    details.width = door?.width ?? null;
    details.height = door?.height ?? null;
    details.project_offset = projectDoor?.offset ?? null;
    details.project_width = projectDoor?.width ?? null;
    details.project_height = projectDoor?.height ?? null;
  } else if (latestElement?.kind === "Window") {
    const window = isObject(latestElement.window) ? latestElement.window : null;
    const projectWindow = isObject(projectElement?.window) ? projectElement.window : null;
    details.level_id = window?.level_id ?? null;
    details.host_wall_id = window?.host_wall_id ?? null;
    details.offset = window?.offset ?? null;
    details.width = window?.width ?? null;
    details.height = window?.height ?? null;
    details.sill_height = window?.sill_height ?? null;
    details.project_offset = projectWindow?.offset ?? null;
    details.project_width = projectWindow?.width ?? null;
    details.project_height = projectWindow?.height ?? null;
    details.project_sill_height = projectWindow?.sill_height ?? null;
  } else if (latestElement?.kind === "Room") {
    const room = isObject(latestElement.room) ? latestElement.room : null;
    details.level_id = room?.level_id ?? null;
    details.boundary_wall_ids = room?.boundary_wall_ids ?? null;
    details.centerline_area = room?.centerline_area ?? null;
    details.interior_area = room?.interior_area ?? null;
    details.centerline_perimeter = room?.centerline_perimeter ?? null;
    details.interior_perimeter = room?.interior_perimeter ?? null;
    details.floor_finish_area = room?.floor_finish_area ?? null;
    details.ceiling_area = room?.ceiling_area ?? null;
    details.baseboard_length = room?.baseboard_length ?? null;
    details.interior_wall_finish_area = room?.interior_wall_finish_area ?? null;
    details.preferred_boundary_mode = room?.preferred_boundary_mode ?? null;
  }

  return {
    title: `${latestElement?.kind ?? "Element"} ${latestElement?.id ?? "?"}`,
    body: safeJsonStringify(details),
  };
}

function findElementById(data: ViewerData | null, elementId: number | null) {
  if (!data || elementId === null) {
    return null;
  }
  return data.debug.elements.find((element) => element.id === elementId) ?? null;
}

function findElementByIdLoose(data: ViewerData | null, elementId: string | null) {
  if (!data || elementId === null) {
    return null;
  }
  const numericId = Number(elementId);
  return Number.isFinite(numericId) ? findElementById(data, numericId) : null;
}

function projectDocumentElements(projectDocument: JsonObject | null) {
  return asArray<JsonObject>(projectDocument?.elements);
}

function findProjectElement(projectDocument: JsonObject | null, elementId: number | null) {
  if (projectDocument === null || elementId === null || !Number.isFinite(elementId)) {
    return null;
  }
  return projectDocumentElements(projectDocument).find((candidate) => toNumber(candidate.id, -1) === elementId) ?? null;
}

function findProjectWallElement(projectDocument: JsonObject | null, wallId: number | null) {
  if (projectDocument === null || wallId === null || !Number.isFinite(wallId)) {
    return null;
  }
  return projectDocumentElements(projectDocument).find((candidate) => toNumber(candidate.id, -1) === wallId && candidate.kind === "Wall") ?? null;
}

function findProjectOpeningHostWall(projectDocument: JsonObject | null, openingId: number | null) {
  if (projectDocument === null || openingId === null || !Number.isFinite(openingId)) {
    return null;
  }
  for (const element of projectDocumentElements(projectDocument)) {
    if (element.kind !== "Wall" || !isObject(element.wall)) {
      continue;
    }
    const openings = asArray<JsonObject>(element.wall.openings);
    if (openings.some((opening) => toNumber(opening.element_id ?? opening.id ?? opening.opening_id, -1) === openingId)) {
      return element;
    }
  }
  return null;
}

function nearestWallHit(projectDocument: JsonObject | null, point: { x: number; y: number }, tolerance = 0.4) {
  if (!projectDocument) {
    return null;
  }

  let best:
    | {
        wall: JsonObject;
        axis: WallAxis;
        projection: ReturnType<typeof projectPointToWallAxis>;
        distance: number;
      }
    | null = null;

  for (const element of projectDocumentElements(projectDocument)) {
    if (element.kind !== "Wall") {
      continue;
    }
    const axis = projectWallAxis(element);
    if (!axis) {
      continue;
    }
    const projection = projectPointToWallAxis(point, axis);
    if (!projection || projection.distance > tolerance) {
      continue;
    }
    if (!best || projection.distance < best.distance) {
      best = {
        wall: element,
        axis,
        projection,
        distance: projection.distance,
      };
    }
  }

  return best;
}

function nearestOpeningHit(projectDocument: JsonObject | null, point: { x: number; y: number }, tolerance = 0.35) {
  if (!projectDocument) {
    return null;
  }

  let best:
    | {
        opening: JsonObject;
        kind: "door" | "window";
        hostWall: JsonObject;
        hostAxis: WallAxis;
        offset: number;
        distance: number;
      }
    | null = null;

  for (const wallElement of projectDocumentElements(projectDocument)) {
    if (wallElement.kind !== "Wall") {
      continue;
    }
    const axis = projectWallAxis(wallElement);
    if (!axis) {
      continue;
    }
    const wallThickness = wallThicknessMeters(isObject(wallElement.wall) ? wallElement.wall : null, 0.2);
    for (const opening of asArray<JsonObject>(isObject(wallElement.wall) ? wallElement.wall.openings : [])) {
      const openingKind = String(opening.kind ?? "").toLowerCase() === "window" ? "window" : "door";
      const offset = toNumber(opening.offset_meters ?? opening.offset, NaN);
      const width = Math.max(0.05, toNumber(opening.width_meters ?? opening.width, 0));
      if (!Number.isFinite(offset) || width <= 0) {
        continue;
      }
      const projection = projectPointToWallAxis(point, axis);
      if (!projection) {
        continue;
      }
      const alongDistance = Math.abs(projection.offset - offset);
      const maxAlongDistance = Math.max(width / 2 + 0.25, 0.15);
      const maxPerpendicular = Math.max(tolerance, wallThickness * 1.2);
      if (alongDistance <= maxAlongDistance && projection.distance <= maxPerpendicular) {
        if (!best || projection.distance < best.distance) {
          best = {
            opening,
            kind: openingKind,
            hostWall: wallElement,
            hostAxis: axis,
            offset,
            distance: projection.distance,
          };
        }
      }
    }
  }

  return best;
}

function projectWallAxis(projectWallElement: JsonObject | null) {
  return projectWallElement && isObject(projectWallElement.wall) ? extractWallAxis(projectWallElement.wall) : null;
}

function translateWallAxis(axis: WallAxis, deltaX: number, deltaY: number): WallAxis {
  return {
    start: { x: axis.start.x + deltaX, y: axis.start.y + deltaY },
    end: { x: axis.end.x + deltaX, y: axis.end.y + deltaY },
  };
}

function wallLength(axis: WallAxis) {
  return Math.hypot(axis.end.x - axis.start.x, axis.end.y - axis.start.y);
}

function wallEndpoints(axis: WallAxis) {
  return [axis.start, axis.end];
}

function findNearestEndpointSnap(
  projectDocument: JsonObject | null,
  movingWallId: number,
  originalAxis: WallAxis,
  delta: { x: number; y: number },
  tolerance = 0.15,
) {
  let bestAdjustment: { deltaX: number; deltaY: number; snapped: boolean } = {
    deltaX: delta.x,
    deltaY: delta.y,
    snapped: false,
  };
  let bestDistance = tolerance;

  for (const candidate of projectDocumentElements(projectDocument)) {
    if (candidate.kind !== "Wall" || toNumber(candidate.id, -1) === movingWallId) {
      continue;
    }
    const candidateAxis = projectWallAxis(candidate);
    if (!candidateAxis) {
      continue;
    }
    for (const source of wallEndpoints(originalAxis)) {
      for (const target of wallEndpoints(candidateAxis)) {
        const movedSource = {
          x: source.x + delta.x,
          y: source.y + delta.y,
        };
        const distance = Math.hypot(movedSource.x - target.x, movedSource.y - target.y);
        if (distance <= bestDistance) {
          bestDistance = distance;
          bestAdjustment = {
            deltaX: delta.x + (target.x - movedSource.x),
            deltaY: delta.y + (target.y - movedSource.y),
            snapped: true,
          };
        }
      }
    }
  }

  return bestAdjustment;
}

function sortMaterialTakeoff(rows: ScheduleRow[]) {
  return [...rows].sort((left, right) => {
    const leftCategory = toStringValue(left.category, toStringValue(left.material_category, ""));
    const rightCategory = toStringValue(right.category, toStringValue(right.material_category, ""));
    if (leftCategory !== rightCategory) {
      return leftCategory.localeCompare(rightCategory);
    }
    const leftName = toStringValue(left.material_name, toStringValue(left.material, ""));
    const rightName = toStringValue(right.material_name, toStringValue(right.material, ""));
    return leftName.localeCompare(rightName);
  });
}

function createDefaultOpeningDraft() {
  return {
    hostWallId: null as number | null,
    offsetMeters: 1.2,
    widthMeters: 0.9,
    heightMeters: 2.1,
    sillHeightMeters: 0.9,
    clearanceMeters: 0.05,
    svgPoint: null as { x: number; y: number } | null,
    modelPoint: null as { x: number; y: number } | null,
    preview: null as OpeningPlacementPreview | null,
  };
}

function isSvgElement(value: unknown): value is SVGElement {
  return typeof SVGElement !== "undefined" && value instanceof SVGElement;
}

function findClosestSvgElement(target: Element | null, kinds: string[]) {
  let current: Element | null = target;
  while (current) {
    if (
      isSvgElement(current) &&
      current.getAttribute("data-element-id") &&
      kinds.includes(normalizeKindKey(current.getAttribute("data-kind")))
    ) {
      return {
        elementId: current.getAttribute("data-element-id") as string,
        kind: current.getAttribute("data-kind"),
        hitKind: current.getAttribute("data-hit-kind"),
        svgId: current.id || null,
        element: current,
      };
    }
    current = current.parentElement;
  }
  return null;
}

function findClosestSvgWall(target: Element | null) {
  return findClosestSvgElement(target, ["wall"]);
}

function findClosestSvgOpening(target: Element | null) {
  return findClosestSvgElement(target, ["door", "window"]);
}

function svgPointFromClient(
  host: HTMLDivElement,
  clientX: number,
  clientY: number,
  viewBox: SvgViewBox | null,
) {
  const svg = host.querySelector("svg");
  if (!svg || !viewBox) {
    return null;
  }
  const rect = svg.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) {
    return null;
  }
  return {
    x: viewBox.minX + ((clientX - rect.left) / rect.width) * viewBox.width,
    y: viewBox.minY + ((clientY - rect.top) / rect.height) * viewBox.height,
  };
}

function modelPointFromSvgPoint(point: SvgPoint | null) {
  if (!point) {
    return null;
  }
  return {
    x: point.x,
    y: -point.y,
  };
}

function wallPreviewPoints(
  axis: WallAxis | null,
  offsetMeters: number,
  widthMeters: number,
  thicknessMeters: number,
) {
  if (!axis) {
    return "";
  }
  const dx = axis.end.x - axis.start.x;
  const dy = axis.end.y - axis.start.y;
  const length = Math.hypot(dx, dy);
  if (length <= 1.0e-9) {
    return "";
  }
  const ux = dx / length;
  const uy = dy / length;
  const nx = -uy;
  const ny = ux;
  const center = {
    x: axis.start.x + (ux * offsetMeters),
    y: axis.start.y + (uy * offsetMeters),
  };
  const halfWidth = widthMeters / 2;
  const halfThickness = thicknessMeters / 2;
  const points = [
    { x: center.x - (ux * halfWidth) - (nx * halfThickness), y: center.y - (uy * halfWidth) - (ny * halfThickness) },
    { x: center.x + (ux * halfWidth) - (nx * halfThickness), y: center.y + (uy * halfWidth) - (ny * halfThickness) },
    { x: center.x + (ux * halfWidth) + (nx * halfThickness), y: center.y + (uy * halfWidth) + (ny * halfThickness) },
    { x: center.x - (ux * halfWidth) + (nx * halfThickness), y: center.y - (uy * halfWidth) + (ny * halfThickness) },
  ];
  return points.map((point) => `${point.x},${-point.y}`).join(" ");
}

function snapValue(value: number, step: number) {
  if (!Number.isFinite(value) || step <= 0) {
    return value;
  }
  return Math.round(value / step) * step;
}

function formatSigned(value: number) {
  return `${value >= 0 ? "+" : ""}${value.toFixed(2)}`;
}

function openingDragPreviewPoints(
  axis: WallAxis | null,
  offsetMeters: number,
  widthMeters: number,
  thicknessMeters: number,
) {
  return wallPreviewPoints(axis, offsetMeters, widthMeters, thicknessMeters);
}

type WallDragPreview = {
  kind: "wall";
  wallId: number;
  wallLabel: string;
  originalAxis: WallAxis;
  previewAxis: WallAxis;
  startSvgPoint: SvgPoint;
  currentSvgPoint: SvgPoint;
  rawDelta: { x: number; y: number };
  delta: { x: number; y: number };
  snapped: boolean;
};

type OpeningDragPreview = {
  kind: "opening";
  openingKind: "door" | "window";
  openingId: number;
  openingLabel: string;
  hostWallId: number;
  hostWallAxis: WallAxis | null;
  widthMeters: number;
  heightMeters: number;
  sillHeightMeters: number;
  originalOffsetMeters: number;
  rawOffsetMeters: number;
  requestedOffsetMeters: number;
  previewOffsetMeters: number;
  svgPoint: SvgPoint | null;
  modelPoint: { x: number; y: number } | null;
  preview: OpeningPlacementPreview | null;
  snapped: boolean;
};

type DragPreview = WallDragPreview | OpeningDragPreview;

type WallDragSession = {
  kind: "wall";
  pointerId: number;
  wallId: number;
  wallLabel: string;
  originalAxis: WallAxis;
  startSvgPoint: SvgPoint | null;
  startModelPoint: { x: number; y: number } | null;
};

type OpeningDragSession = {
  kind: "opening";
  pointerId: number;
  openingKind: "door" | "window";
  openingId: number;
  openingLabel: string;
  hostWallId: number;
  hostWall: JsonObject | null;
  hostWallAxis: WallAxis | null;
  widthMeters: number;
  heightMeters: number;
  sillHeightMeters: number;
  clearanceMeters: number;
  originalOffsetMeters: number;
  startSvgPoint: SvgPoint | null;
  startModelPoint: { x: number; y: number } | null;
};

type EditDragSession = WallDragSession | OpeningDragSession;

type InteractionMode =
  | "select"
  | "draft-wall"
  | "draft-door"
  | "draft-window"
  | "move-wall"
  | "move-opening";

function extractValidationSummary(debug: DebugReport | null) {
  const issues = debug?.validation.issues ?? 0;
  const warnings = debug?.validation.warnings ?? 0;
  const errors = debug?.validation.errors ?? 0;
  const warningCount = countValidationIssues(warnings);
  const errorCount = countValidationIssues(errors);
  const status = errorCount > 0 ? "Errors" : warningCount > 0 ? "Warnings" : "OK";
  return { warningCount, errorCount, status, issues, warnings, errors };
}

async function loadBundledSampleData(revision: number): Promise<ViewerData> {
  const suffix = revision > 0 ? `?v=${revision}` : "";
  const [projectJson, debugJson, svg, metadata, obj] = await Promise.all([
    fetch(`${sampleFiles.projectJson}${suffix}`).then((response) => response.json()),
    fetch(`${sampleFiles.debugJson}${suffix}`).then((response) => response.json()),
    fetch(`${sampleFiles.svg}${suffix}`).then((response) => response.text()),
    fetch(`${sampleFiles.metadata}${suffix}`).then((response) => response.json()).catch(() => null),
    fetch(`${sampleFiles.obj}${suffix}`).then((response) => response.text()).catch(() => null),
  ]);
  const debug = normalizeDebugReport(debugJson);
  const projectObject = isObject(projectJson) ? projectJson : null;
  const metadataObject = isObject(metadata) ? metadata : null;
  return {
    project: normalizeProjectSummary(projectObject, metadataObject, debug),
    debug,
    projectJson: projectObject,
    svg,
    obj: typeof obj === "string" ? obj : null,
    metadata: metadataObject,
  };
}

export default function Home() {
  const [data, setData] = useState<ViewerData | null>(null);
  const [selection, setSelection] = useState<Selection>({ kind: "none" });
  const [loadError, setLoadError] = useState<string | null>(null);
  const [viewMode, setViewMode] = useState<"2d" | "3d">("2d");
  const [interactionMode, setInteractionMode] = useState<InteractionMode>("select");
  const [artifactRevision, setArtifactRevision] = useState(0);
  const [artifactLoadedAt, setArtifactLoadedAt] = useState(() => Date.now());
  const [scale, setScale] = useState(1);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [dragging, setDragging] = useState(false);
  const [dragPreview, setDragPreview] = useState<DragPreview | null>(null);
  const [snapToGrid, setSnapToGrid] = useState(true);
  const [selectedSvgId, setSelectedSvgId] = useState<string | null>(null);
  const [hoveredSvgMeta, setHoveredSvgMeta] = useState<SvgMetadata | null>(null);
  const [hoveredSvgPoint, setHoveredSvgPoint] = useState<{ x: number; y: number } | null>(null);
  const [selectedSvgPoint, setSelectedSvgPoint] = useState<{ x: number; y: number } | null>(null);
  const [hoveredProjectElementId, setHoveredProjectElementId] = useState<number | null>(null);
  const [hoveredProjectInfo, setHoveredProjectInfo] = useState<string>("Move the cursor over an element to highlight it.");
  const [draftWall, setDraftWall] = useState<{ start: { x: number; y: number }; end?: { x: number; y: number } | null } | null>(null);
  const [openingDraft, setOpeningDraft] = useState(createDefaultOpeningDraft);
  const [draftWallParams, setDraftWallParams] = useState({ heightMeters: 3.0, thicknessMeters: 0.2 });
  const [editStatus, setEditStatus] = useState<{
    tone: "neutral" | "good" | "warn" | "bad";
    message: string;
    command: string | null;
    timestamp: number | null;
    validation: { errors: number; warnings: number };
    updatedFiles: string[];
    output: string;
    error: string | null;
  }>({
    tone: "neutral",
    message: "No local edits yet.",
    command: null,
    timestamp: null,
    validation: { errors: 0, warnings: 0 },
    updatedFiles: [],
    output: "",
    error: null,
  });
  const [editBusy, setEditBusy] = useState(false);
  const [editFormError, setEditFormError] = useState<string | null>(null);
  const [bridgeStatus, setBridgeStatus] = useState<{ configured: boolean; message: string; instructions: string[] }>({
    configured: false,
    message: "Bridge status unknown.",
    instructions: [],
  });
  const [svgClickInfo, setSvgClickInfo] = useState<string>(
    "Top view selection uses the exported project model.",
  );
  const [sourceMode, setSourceMode] = useState<"sample" | "project" | "artifacts">("sample");
  const [kindVisibility, setKindVisibility] = useState<Record<KindFilterKey, boolean>>(() =>
    Object.fromEntries(kindFilterKeys.map((key) => [key, true])) as Record<KindFilterKey, boolean>,
  );
  const dragOrigin = useRef<{ x: number; y: number; panX: number; panY: number } | null>(null);
  const editDragRef = useRef<EditDragSession | null>(null);
  const suppressNextSvgClickRef = useRef(false);
  const svgHostRef = useRef<HTMLDivElement | null>(null);
  const projectInputRef = useRef<HTMLInputElement | null>(null);
  const artifactInputRef = useRef<HTMLInputElement | null>(null);
  const currentSvgIds = useMemo(() => extractSvgIds(data?.svg ?? ""), [data]);
  const currentSvgViewBox = useMemo(() => extractSvgViewBox(data?.svg ?? ""), [data]);
  const renderedSvgMarkup = useMemo(() => prepareSvgMarkup(data?.svg ?? ""), [data]);
  const artifactStats = useMemo(() => extractObjStats(data?.obj ?? null), [data]);
  const exportTimestamp = useMemo(() => extractExportTimestamp(data?.metadata ?? null), [data]);
  const visibleDebugElements = useMemo(
    () =>
      (data?.debug.elements ?? []).filter((element) => {
        const key = normalizeKindKey(element.kind);
        return (kindVisibility[key as KindFilterKey] ?? true);
      }),
    [data, kindVisibility],
  );
  const groupedElements = useMemo(() => groupElements(visibleDebugElements), [visibleDebugElements]);
  const validation = useMemo(() => extractValidationSummary(data?.debug ?? null), [data]);
  const materialTakeoff = useMemo(() => sortMaterialTakeoff(data?.debug.schedules.material_takeoff ?? []), [data]);
  const selectedDetails = useMemo(() => buildSelectionDetails(selection, data), [selection, data]);
  const selectedElement = useMemo(() => {
    if (selection.kind !== "element") {
      return null;
    }
    const currentId = selection.value.id ?? null;
    if (currentId === null) {
      return selection.value;
    }
    return data?.debug.elements.find((element) => element.id === currentId) ?? selection.value;
  }, [data, selection]);
  const selectedEditableId = selectedElement?.id ?? null;
  const selectedProjectElementId = useMemo(() => {
    if (selectedEditableId !== null) {
      return selectedEditableId;
    }
    if (selectedSvgId !== null) {
      const parsedId = Number(selectedSvgId);
      return Number.isFinite(parsedId) ? parsedId : null;
    }
    return null;
  }, [selectedEditableId, selectedSvgId]);
  const selectedWallElement = useMemo(() => {
    if (selectedElement?.kind === "Wall") {
      return selectedElement;
    }
    if (selectedSvgId) {
      const matched = findElementByIdLoose(data, selectedSvgId);
      if (matched?.kind === "Wall") {
        return matched;
      }
    }
    return null;
  }, [data, selectedElement, selectedSvgId]);
  const selectedWallId = selectedWallElement?.id ?? null;
  const selectedProjectDocument = useMemo(
    () => (data?.projectJson && isObject(data.projectJson.document) ? data.projectJson.document : null),
    [data],
  );
  const selectedProjectElement = useMemo(() => {
    if (selectedProjectElementId === null || !selectedProjectDocument) {
      return null;
    }
    return asArray<JsonObject>(selectedProjectDocument.elements).find((candidate) => toNumber(candidate.id, -1) === selectedProjectElementId) ?? null;
  }, [selectedProjectDocument, selectedProjectElementId]);
  const hoveredProjectElement = useMemo(() => {
    if (hoveredProjectElementId === null) {
      return null;
    }
    return data?.debug.elements.find((element) => element.id === hoveredProjectElementId) ?? null;
  }, [data, hoveredProjectElementId]);
  const selectedWallProjectElement = useMemo(
    () => (selectedProjectElement?.kind === "Wall" ? selectedProjectElement : null),
    [selectedProjectElement],
  );
  const selectedDoorProjectElement = useMemo(
    () => (selectedProjectElement?.kind === "Door" ? selectedProjectElement : null),
    [selectedProjectElement],
  );
  const selectedWindowProjectElement = useMemo(
    () => (selectedProjectElement?.kind === "Window" ? selectedProjectElement : null),
    [selectedProjectElement],
  );
  const selectedOpeningProjectElement = selectedDoorProjectElement ?? selectedWindowProjectElement ?? null;
  const selectedOpeningHostWallProjectElement = useMemo(
    () => findProjectOpeningHostWall(selectedProjectDocument, toNumber(selectedOpeningProjectElement?.id, NaN)),
    [selectedOpeningProjectElement?.id, selectedProjectDocument],
  );
  const selectedOpeningHostWall = useMemo(
    () => projectWallAxis(selectedOpeningHostWallProjectElement),
    [selectedOpeningHostWallProjectElement],
  );
  const selectedWallProjectWall = useMemo(
    () => (isObject(selectedWallProjectElement?.wall) ? selectedWallProjectElement.wall : null),
    [selectedWallProjectElement],
  );
  const selectedWallAxis = useMemo(
    () => extractWallAxis(selectedWallProjectWall),
    [selectedWallProjectWall],
  );
  const selectedWallThickness = useMemo(
    () => wallThicknessMeters(selectedWallProjectWall, 0.2),
    [selectedWallProjectWall],
  );
  const selectedWallLength = useMemo(() => {
    if (!selectedWallAxis) {
      return null;
    }
    return Math.hypot(selectedWallAxis.end.x - selectedWallAxis.start.x, selectedWallAxis.end.y - selectedWallAxis.start.y);
  }, [selectedWallAxis]);
  const activeOpeningKind = interactionMode === "draft-door" ? "door" : interactionMode === "draft-window" ? "window" : null;
  const draftLength = draftWall?.start && draftWall?.end ? formatDraftLength(draftWall.start, draftWall.end) : null;
  const openingModeLabel = interactionMode === "draft-door" ? "Door" : interactionMode === "draft-window" ? "Window" : null;
  const hoveredDetails = useMemo(() => {
    if (hoveredProjectElement) {
      return `${hoveredProjectElement.kind ?? "Element"} #${hoveredProjectElement.id ?? "?"}`;
    }
    if (!hoveredSvgMeta) {
      return null;
    }
    return `${hoveredSvgMeta.kind ?? "element"} #${hoveredSvgMeta.elementId}${hoveredSvgMeta.hitKind ? ` • ${hoveredSvgMeta.hitKind}` : ""}`;
  }, [hoveredProjectElement, hoveredSvgMeta]);

  const handleProjectHover = (info: {
    elementId: number | null;
    kind: string | null;
    hitKind: string | null;
    modelPoint: { x: number; y: number } | null;
  }) => {
    setHoveredProjectElementId(info.elementId ?? null);
    if (info.elementId !== null) {
      setHoveredProjectInfo(
        `${info.kind ?? "Element"} #${info.elementId}${info.hitKind ? ` • ${info.hitKind}` : ""}${info.modelPoint ? ` • model ${info.modelPoint.x.toFixed(2)}, ${info.modelPoint.y.toFixed(2)}` : ""}`,
      );
    } else if (info.modelPoint) {
      setHoveredProjectInfo(`Top view point ${info.modelPoint.x.toFixed(2)}, ${info.modelPoint.y.toFixed(2)}`);
    } else {
      setHoveredProjectInfo("Move the cursor over an element to highlight it.");
    }
  };

  const handleProjectPick = (info: {
    elementId: number | null;
    kind: string | null;
    hitKind: string | null;
    modelPoint: { x: number; y: number } | null;
  }) => {
    const pickedId = info.elementId ?? null;
    const pickedElement = pickedId !== null ? findElementById(data, pickedId) : null;
    const pickedKind = normalizeKindKey(info.kind);
    const matchedWall = pickedId !== null ? findProjectWallElement(selectedProjectDocument, pickedId) : null;
    const nearestWall = info.modelPoint ? nearestWallHit(selectedProjectDocument, info.modelPoint, 0.45) : null;
    const wallCandidate = matchedWall ?? nearestWall?.wall ?? null;

    if (interactionMode === "draft-wall") {
      if (!info.modelPoint) {
        setSvgClickInfo("Click inside the top view to place the wall.");
        return;
      }
      setSelection({ kind: "none" });
      setSelectedSvgId(null);
      setSelectedSvgPoint(null);
      setHoveredSvgMeta(null);
      setHoveredSvgPoint(null);
      setHoveredProjectElementId(null);
      setDraftWall((current) => {
        if (!current || current.end) {
          setSvgClickInfo("Draft wall start set. Click again to preview the wall.");
          return { start: info.modelPoint as { x: number; y: number }, end: null };
        }
        const nextDraft = { ...current, end: info.modelPoint as { x: number; y: number } };
        setSvgClickInfo(`Draft wall preview only. Approx length ${formatDraftLength(nextDraft.start, nextDraft.end).toFixed(2)} m.`);
        return nextDraft;
      });
      return;
    }

    if (interactionMode === "draft-door" || interactionMode === "draft-window") {
      const openingKind = interactionMode === "draft-door" ? "door" : "window";
      const isWallHit = pickedKind === "wall" && wallCandidate;
      const hostWall = isWallHit ? wallCandidate : nearestWall?.wall ?? null;
      const hostWallAxis = hostWall ? projectWallAxis(hostWall) : null;
      if (!hostWall || !hostWallAxis || !info.modelPoint) {
        setEditFormError("Click a wall to place opening.");
        setSvgClickInfo("Click a wall to place opening.");
        return;
      }
      const projected = projectPointToWallAxis(info.modelPoint, hostWallAxis);
      const offsetMeters = projected ? Math.max(0, projected.offset) : openingDraft.offsetMeters;
      setOpeningDraft((current) => ({
        ...current,
        hostWallId: toNumber(hostWall.id, current.hostWallId ?? 0),
        offsetMeters,
        svgPoint: null,
        modelPoint: info.modelPoint,
        preview: null,
      }));
      setSelectedSvgId(String(hostWall.id ?? ""));
      setHoveredProjectElementId(Number.isFinite(Number(hostWall.id)) ? Number(hostWall.id) : null);
      const hostWallNumericId = Number(hostWall.id);
      setSelection({
        kind: "element",
        label: `${hostWall.kind ?? "Wall"} #${hostWall.id ?? "-"}`,
        value: (findElementById(data, Number.isFinite(hostWallNumericId) ? hostWallNumericId : null) ?? { id: hostWall.id, kind: "Wall", name: "Wall" }) as DebugElement,
        svgMeta: {
          elementId: String(hostWall.id ?? ""),
          kind: "Wall",
          hitKind: "wall_body",
          svgId: null,
        },
      });
      setSvgClickInfo(
        `${openingModeLabel ?? "Opening"} host wall #${hostWall.id ?? "-"} selected. model ${info.modelPoint.x.toFixed(2)}, ${info.modelPoint.y.toFixed(2)} offset ${offsetMeters.toFixed(2)}m.`,
      );
      return;
    }

    if (pickedElement) {
      setSelection({
        kind: "element",
        label: `${pickedElement.kind ?? "Element"} #${pickedElement.id ?? "?"}`,
        value: pickedElement,
        svgMeta: {
          elementId: String(pickedElement.id ?? ""),
          kind: pickedElement.kind ?? null,
          hitKind: info.hitKind ?? null,
          svgId: null,
        },
      });
      setSelectedSvgId(pickedId !== null ? String(pickedId) : null);
      setHoveredProjectElementId(pickedId);
      setSvgClickInfo(`Selected ${pickedElement.kind ?? "element"} #${pickedElement.id ?? "?"}`);
      return;
    }

    if (info.modelPoint) {
      setSelection({ kind: "none" });
      setSelectedSvgId(null);
      setSelectedSvgPoint({ x: info.modelPoint.x, y: -info.modelPoint.y });
      setHoveredProjectElementId(null);
      setSvgClickInfo(`Top view click at ${info.modelPoint.x.toFixed(2)}, ${info.modelPoint.y.toFixed(2)}.`);
    }
  };

  useEffect(() => {
    let active = true;
    loadBundledSampleData(artifactRevision)
      .then((nextData) => {
        if (!active) {
          return;
        }
        setData(nextData);
        setSourceMode("sample");
      })
      .catch((error: unknown) => {
        if (!active) {
          return;
        }
        setLoadError(error instanceof Error ? error.message : String(error));
      });
    return () => {
      active = false;
    };
  }, [artifactRevision]);

  useEffect(() => {
    let active = true;
    fetch("/api/edit/status")
      .then(async (response) => {
        const payload = (await response.json()) as { configured?: boolean; message?: string; instructions?: string[] };
        if (!active) {
          return;
        }
        setBridgeStatus({
          configured: payload.configured ?? false,
          message: payload.message ?? "Bridge status unavailable.",
          instructions: payload.instructions ?? [],
        });
      })
      .catch(() => {
        if (!active) {
          return;
        }
        setBridgeStatus({
          configured: false,
          message: "Bridge status unavailable.",
          instructions: [],
        });
      });
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (!activeOpeningKind || viewMode !== "2d") {
      return;
    }
    const wallId = openingDraft.hostWallId ?? selectedWallProjectElement?.id ?? null;
    if (!wallId || !data?.projectJson) {
      return;
    }

    let active = true;
    const timer = window.setTimeout(() => {
      void fetch("/api/edit/preview-opening-placement", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          project_json: data.projectJson,
          host_wall: selectedWallProjectWall,
          host_wall_id: wallId,
          kind: activeOpeningKind,
          requested_offset_meters: openingDraft.offsetMeters,
          width_meters: openingDraft.widthMeters,
          height_meters: openingDraft.heightMeters,
          sill_height_meters: activeOpeningKind === "window" ? openingDraft.sillHeightMeters : 0,
          clearance_meters: openingDraft.clearanceMeters,
          svg_point: openingDraft.svgPoint,
          model_point: openingDraft.modelPoint,
        }),
      })
        .then(async (response) => {
          const payload = (await response.json()) as {
            success: boolean;
            message: string;
            error: string | null;
            preview?: OpeningPlacementPreview;
          };
          if (!active) {
            return;
          }
          if (!response.ok || !payload.success || !payload.preview) {
            setEditFormError(payload.error ?? payload.message ?? "Failed to preview opening placement.");
            setOpeningDraft((current) => ({ ...current, preview: null }));
            return;
          }
          setEditFormError(null);
          setOpeningDraft((current) => ({
            ...current,
            preview: payload.preview ?? null,
          }));
          setSvgClickInfo(payload.message ?? "Opening preview updated.");
        })
        .catch((error: unknown) => {
          if (!active) {
            return;
          }
          const message = error instanceof Error ? error.message : String(error);
          setEditFormError(message);
          setOpeningDraft((current) => ({ ...current, preview: null }));
        });
    }, 120);

    return () => {
      active = false;
      window.clearTimeout(timer);
    };
  }, [
    activeOpeningKind,
    data?.projectJson,
    openingDraft.clearanceMeters,
    openingDraft.heightMeters,
    openingDraft.hostWallId,
    openingDraft.modelPoint,
    openingDraft.offsetMeters,
    openingDraft.sillHeightMeters,
    openingDraft.svgPoint,
    openingDraft.widthMeters,
    selectedWallProjectElement?.id,
    selectedWallProjectWall,
    viewMode,
  ]);

  useEffect(() => {
    const host = svgHostRef.current;
    if (!host) {
      return;
    }
    const previous = host.querySelectorAll('[data-selected-svg="true"]');
    previous.forEach((node) => {
      if (node instanceof SVGElement) {
        node.removeAttribute("data-selected-svg");
        node.style.filter = "";
        node.style.stroke = "";
        node.style.strokeWidth = "";
      }
    });
    const hoverPrevious = host.querySelectorAll('[data-hovered-svg="true"]');
    hoverPrevious.forEach((node) => {
      if (node instanceof SVGElement) {
        node.removeAttribute("data-hovered-svg");
      }
    });
    host.querySelectorAll("[data-kind]").forEach((node) => {
      if (!(node instanceof SVGElement)) {
        return;
      }
      const kind = normalizeKindKey(node.getAttribute("data-kind"));
      const visible = kindVisibility[kind as KindFilterKey] ?? true;
      if (visible) {
        node.removeAttribute("data-kind-hidden");
        node.style.opacity = "";
        node.style.pointerEvents = "";
      } else {
        node.setAttribute("data-kind-hidden", "true");
        node.style.opacity = "0.12";
        node.style.pointerEvents = "none";
      }
    });
    host.querySelectorAll("[data-element-id]").forEach((node) => {
      if (!(node instanceof SVGElement)) {
        return;
      }
      const elementId = node.getAttribute("data-element-id");
      const isSelected = selectedSvgId !== null && elementId === selectedSvgId;
      const isHovered = hoveredSvgMeta !== null && elementId === hoveredSvgMeta.elementId;
      if (isSelected) {
        node.setAttribute("data-selected-svg", "true");
      } else {
        node.removeAttribute("data-selected-svg");
      }
      if (isHovered) {
        node.setAttribute("data-hovered-svg", "true");
      } else {
        node.removeAttribute("data-hovered-svg");
      }
    });
  }, [selectedSvgId, hoveredSvgMeta, kindVisibility, data]);

  useEffect(() => {
    if (!data || selectedEditableId === null) {
      return;
    }
    const stillExists = data.debug.elements.some((element) => element.id === selectedEditableId);
    if (!stillExists) {
      const timer = window.setTimeout(() => {
        setSelection({ kind: "none" });
        setSelectedSvgId(null);
        setSelectedSvgPoint(null);
        setHoveredSvgMeta(null);
        setHoveredSvgPoint(null);
        setSvgClickInfo(`Selected element ${selectedEditableId} is no longer present in the refreshed artifacts.`);
      }, 0);
      return () => window.clearTimeout(timer);
    }
  }, [data, selectedEditableId]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        resetEditDrafts("Draft cancelled.");
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  const resetView = () => {
    setScale(1);
    setPan({ x: 0, y: 0 });
  };

  function resetEditDrafts(message?: string) {
    setDraftWall(null);
    setOpeningDraft(createDefaultOpeningDraft());
    setDragPreview(null);
    editDragRef.current = null;
    setInteractionMode("select");
    setEditFormError(null);
    if (message) {
      setSvgClickInfo(message);
    }
  }

  const reloadSample = async () => {
    setLoadError(null);
    setSourceMode("sample");
    setSelection({ kind: "none" });
    setSelectedSvgId(null);
    setSelectedSvgPoint(null);
    setHoveredSvgMeta(null);
    setHoveredSvgPoint(null);
    setHoveredProjectElementId(null);
    setHoveredProjectInfo("Move the cursor over an element to highlight it.");
    setEditFormError(null);
    resetEditDrafts("Reloaded bundled sample.");
    setArtifactLoadedAt(Date.now());
    setArtifactRevision((value) => value + 1);
  };

  const refreshArtifacts = () => {
    setLoadError(null);
    setArtifactLoadedAt(Date.now());
    setArtifactRevision((value) => value + 1);
    setDragPreview(null);
    editDragRef.current = null;
    setHoveredProjectElementId(null);
    setSvgClickInfo("Artifacts reloaded.");
  };

  const loadProjectJsonFile = async (file: File) => {
    setLoadError(null);
    const text = await file.text();
    const parsed = safeJsonParse(text);
    if (!parsed) {
      throw new Error("Invalid project.json");
    }
    const debug = data?.debug ?? normalizeDebugReport(null);
    const metadata = data?.metadata ?? null;
    setData({
      project: normalizeProjectSummary(parsed, metadata, debug),
      debug,
      projectJson: parsed,
      svg: data?.svg ?? "",
      obj: data?.obj ?? null,
      metadata,
    });
    setSourceMode("project");
    setSelection({ kind: "validation", label: "project.json", value: parsed });
    setSelectedSvgId(null);
    setSelectedSvgPoint(null);
    setHoveredSvgMeta(null);
    setHoveredSvgPoint(null);
    setHoveredProjectElementId(null);
    setHoveredProjectInfo("Move the cursor over an element to highlight it.");
    setEditFormError(null);
    resetEditDrafts(`Loaded project.json: ${file.name}`);
  };

  const loadArtifactPair = async (files: FileList | null) => {
    if (!files || files.length === 0) {
      return;
    }
    setLoadError(null);
    const selectedFiles = Array.from(files);
    const debugFile = selectedFiles.find((file) => file.name.endsWith("debug_report.json"));
    const svgFile = selectedFiles.find((file) => file.name.endsWith(".svg"));
    const projectFile = selectedFiles.find((file) => file.name.endsWith("project.json"));
    const metadataFile = selectedFiles.find((file) => file.name.endsWith("metadata.json"));
    if (!debugFile || !svgFile) {
      throw new Error("Please select at least debug_report.json and floorplan.svg");
    }
    const [debugJson, svg, projectJson, metadata] = await Promise.all([
      debugFile.text().then((text) => JSON.parse(text) as unknown),
      svgFile.text(),
      projectFile?.text().then((text) => JSON.parse(text) as unknown).catch(() => null) ?? Promise.resolve(null),
      metadataFile?.text().then((text) => JSON.parse(text) as unknown).catch(() => null) ?? Promise.resolve(null),
    ]);
    const debug = normalizeDebugReport(debugJson);
    const projectObject = isObject(projectJson) ? projectJson : null;
    const metadataObject = isObject(metadata) ? metadata : null;
    setData({
      project: normalizeProjectSummary(projectObject, metadataObject, debug),
      debug,
      projectJson: projectObject,
      svg,
      obj: null,
      metadata: metadataObject,
    });
    setSourceMode("artifacts");
    setSelection({ kind: "none" });
    setSelectedSvgId(null);
    setSelectedSvgPoint(null);
    setHoveredSvgMeta(null);
    setHoveredSvgPoint(null);
    setHoveredProjectElementId(null);
    setHoveredProjectInfo("Move the cursor over an element to highlight it.");
    setEditFormError(null);
    resetEditDrafts("Imported static artifact pair.");
  };

  const importProjectJsonClick = () => projectInputRef.current?.click();
  const importArtifactsClick = () => artifactInputRef.current?.click();

  const postLocalEdit = async (
    route: string,
    body: Record<string, unknown>,
    fallbackMessage: string,
    onSuccess?: (result: {
      success: boolean;
      command: string;
      message: string;
      validation: { errors: number; warnings: number };
      updatedFiles: string[];
      output: string;
      error: string | null;
      artifactPaths?: Record<string, string>;
      commandOutput?: { opening_id?: number; wall_id?: number; element_id?: number };
    }) => void,
  ) => {
    setEditBusy(true);
    setLoadError(null);
    setEditFormError(null);
    try {
      const response = await fetch(route, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });
      const payload = (await response.json()) as {
        success: boolean;
        command: string;
        message: string;
        validation: { errors: number; warnings: number };
        updatedFiles: string[];
        output: string;
        error: string | null;
        artifactPaths?: Record<string, string>;
        commandOutput?: { opening_id?: number; wall_id?: number; element_id?: number };
      };
      if (!response.ok || !payload.success) {
        throw new Error(payload.error ?? payload.message ?? fallbackMessage);
      }
      const errors = payload.validation.errors ?? 0;
      const warnings = payload.validation.warnings ?? 0;
      setEditStatus({
        tone: errors > 0 || warnings > 0 ? "warn" : "good",
        message: payload.message ?? `${payload.command} completed. Validation: ${errors} errors, ${warnings} warnings.`,
        command: payload.command,
        timestamp: Date.now(),
        validation: { errors, warnings },
        updatedFiles: payload.updatedFiles ?? [],
        output: payload.output ?? "",
        error: payload.error ?? null,
      });
      onSuccess?.(payload);
      setArtifactLoadedAt(Date.now());
      setArtifactRevision((value) => value + 1);
      return payload;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setEditStatus((current) => ({
        ...current,
        tone: "bad",
        message,
        error: message,
        timestamp: Date.now(),
      }));
      throw error;
    } finally {
      setEditBusy(false);
    }
  };

  const updateWallDragPreview = (session: WallDragSession, currentSvgPoint: SvgPoint | null, currentModelPoint: { x: number; y: number } | null) => {
    const startModelPoint = session.startModelPoint ?? currentModelPoint;
    if (!startModelPoint || !currentModelPoint) {
      setDragPreview({
        kind: "wall",
        wallId: session.wallId,
        wallLabel: session.wallLabel,
        originalAxis: session.originalAxis,
        previewAxis: session.originalAxis,
        startSvgPoint: session.startSvgPoint ?? currentSvgPoint ?? { x: 0, y: 0 },
        currentSvgPoint: currentSvgPoint ?? session.startSvgPoint ?? { x: 0, y: 0 },
        rawDelta: { x: 0, y: 0 },
        delta: { x: 0, y: 0 },
        snapped: false,
      });
      return;
    }

    const rawDelta = {
      x: currentModelPoint.x - startModelPoint.x,
      y: currentModelPoint.y - startModelPoint.y,
    };
    const gridDelta = snapToGrid
      ? {
          x: snapValue(rawDelta.x, 0.1),
          y: snapValue(rawDelta.y, 0.1),
        }
      : rawDelta;
    const snappedDelta = findNearestEndpointSnap(
      selectedProjectDocument,
      session.wallId,
      session.originalAxis,
      gridDelta,
      snapToGrid ? 0.18 : 0,
    );
    const previewAxis = translateWallAxis(session.originalAxis, snappedDelta.deltaX, snappedDelta.deltaY);
    setDragPreview({
      kind: "wall",
      wallId: session.wallId,
      wallLabel: session.wallLabel,
      originalAxis: session.originalAxis,
      previewAxis,
      startSvgPoint: session.startSvgPoint ?? currentSvgPoint ?? { x: 0, y: 0 },
      currentSvgPoint: currentSvgPoint ?? session.startSvgPoint ?? { x: 0, y: 0 },
      rawDelta,
      delta: { x: snappedDelta.deltaX, y: snappedDelta.deltaY },
      snapped: snappedDelta.snapped || gridDelta.x !== rawDelta.x || gridDelta.y !== rawDelta.y,
    });
  };

  const updateOpeningDragPreview = (
    session: OpeningDragSession,
    currentSvgPoint: SvgPoint | null,
    currentModelPoint: { x: number; y: number } | null,
  ) => {
    const hostWallAxis = session.hostWallAxis ?? projectWallAxis(session.hostWall);
    const projected = currentModelPoint && hostWallAxis ? projectPointToWallAxis(currentModelPoint, hostWallAxis) : null;
    const requestedOffset = projected ? projected.offset : session.originalOffsetMeters;
    const snappedOffset = snapToGrid ? snapValue(requestedOffset, 0.05) : requestedOffset;
    const preview = computeOpeningPlacementPreview({
      project_json: data?.projectJson ?? null,
      host_wall: session.hostWall,
      host_wall_id: session.hostWallId,
      kind: session.openingKind,
      requested_offset_meters: snappedOffset,
      width_meters: session.widthMeters,
      height_meters: session.heightMeters,
      sill_height_meters: session.openingKind === "window" ? session.sillHeightMeters : 0,
      clearance_meters: session.clearanceMeters,
      svg_point: currentSvgPoint,
      model_point: currentModelPoint,
    });

    setDragPreview({
      kind: "opening",
      openingKind: session.openingKind,
      openingId: session.openingId,
      openingLabel: session.openingLabel,
      hostWallId: session.hostWallId,
      hostWallAxis,
      widthMeters: session.widthMeters,
      heightMeters: session.heightMeters,
      sillHeightMeters: session.sillHeightMeters,
      originalOffsetMeters: session.originalOffsetMeters,
      rawOffsetMeters: requestedOffset,
      requestedOffsetMeters: snappedOffset,
      previewOffsetMeters: preview.adjusted_offset_meters,
      svgPoint: currentSvgPoint,
      modelPoint: currentModelPoint,
      preview,
      snapped: preview.adjusted_offset_meters !== snappedOffset,
    });
    setOpeningDraft((current) => ({
      ...current,
      hostWallId: session.hostWallId,
      offsetMeters: snappedOffset,
      svgPoint: currentSvgPoint,
      modelPoint: currentModelPoint,
      preview,
    }));
  };

  const beginWallMoveDrag = (target: Element | null, event: React.PointerEvent<HTMLDivElement>) => {
    const svgPoint = svgHostRef.current ? svgPointFromClient(svgHostRef.current, event.clientX, event.clientY, currentSvgViewBox) : null;
    const modelPoint = modelPointFromSvgPoint(svgPoint);
    const wallMeta = findClosestSvgWall(target);
    const nearest = !wallMeta && modelPoint ? nearestWallHit(selectedProjectDocument, modelPoint, Math.max(0.45, selectedWallThickness * 1.8)) : null;
    const matchedElement = wallMeta ? findElementByIdLoose(data, wallMeta.elementId) : nearest ? findElementByIdLoose(data, String(nearest.wall.id ?? "")) : null;
    if (!wallMeta || !matchedElement || matchedElement.kind !== "Wall") {
      if (!nearest) {
        setEditFormError("Click a wall to move it.");
        setSvgClickInfo("Move wall mode: click a wall to start the drag.");
        return false;
      }
    }
    const nearestWallId = Number(nearest?.wall.id);
    const resolvedWallId = matchedElement?.id ?? (Number.isFinite(nearestWallId) ? nearestWallId : null) ?? Number(wallMeta?.elementId);
    const wallProjectElement = findProjectWallElement(selectedProjectDocument, resolvedWallId);
    const wallAxis = projectWallAxis(wallProjectElement);
    if (!wallProjectElement || !wallAxis) {
      setEditFormError("Selected wall has no usable axis.");
      setSvgClickInfo("Selected wall has no usable axis.");
      return false;
    }
    editDragRef.current = {
      kind: "wall",
      pointerId: event.pointerId,
      wallId: toNumber(wallProjectElement.id, matchedElement?.id ?? NaN),
      wallLabel: `${matchedElement?.kind ?? "Wall"} #${matchedElement?.id ?? wallMeta?.elementId ?? nearest?.wall.id ?? "?"}`,
      originalAxis: wallAxis,
      startSvgPoint: svgPoint,
      startModelPoint: modelPoint,
    };
    setSelectedSvgId(wallMeta?.elementId ?? String(nearest?.wall.id ?? matchedElement?.id ?? ""));
    setSelection({
      kind: "element",
      label: `${matchedElement?.kind ?? "Wall"} #${matchedElement?.id ?? wallMeta?.elementId ?? nearest?.wall.id ?? "?"}`,
      value: (matchedElement ?? (nearest?.wall as DebugElement)) as DebugElement,
      svgMeta: {
        elementId: wallMeta?.elementId ?? String(nearest?.wall.id ?? matchedElement?.id ?? ""),
        kind: matchedElement?.kind ?? "Wall",
        hitKind: wallMeta?.hitKind ?? "wall_body",
        svgId: wallMeta?.svgId ?? null,
      },
    });
    setEditFormError(null);
    setSvgClickInfo(
      `Move wall preview started. ${svgPoint ? `SVG ${svgPoint.x.toFixed(2)}, ${svgPoint.y.toFixed(2)}` : "-"} ${modelPoint ? `model ${modelPoint.x.toFixed(2)}, ${modelPoint.y.toFixed(2)}` : "-"}.`,
    );
    if (event.currentTarget.hasPointerCapture(event.pointerId) === false) {
      event.currentTarget.setPointerCapture(event.pointerId);
    }
    return true;
  };

  const beginOpeningMoveDrag = (target: Element | null, event: React.PointerEvent<HTMLDivElement>) => {
    const svgPoint = svgHostRef.current ? svgPointFromClient(svgHostRef.current, event.clientX, event.clientY, currentSvgViewBox) : null;
    const modelPoint = modelPointFromSvgPoint(svgPoint);
    const openingMeta = findClosestSvgOpening(target);
    const nearest = !openingMeta && modelPoint ? nearestOpeningHit(selectedProjectDocument, modelPoint, 0.4) : null;
    const matchedElement = openingMeta ? findElementByIdLoose(data, openingMeta.elementId) : nearest ? findElementByIdLoose(data, String(nearest.opening.element_id ?? nearest.opening.id ?? "")) : null;
    if (!openingMeta && !nearest && (!matchedElement || (matchedElement.kind !== "Door" && matchedElement.kind !== "Window"))) {
      setEditFormError("Click a door or window to move it.");
      setSvgClickInfo("Move opening mode: click a door or window to start the drag.");
      return false;
    }

    const nearestOpeningId = Number(nearest?.opening.element_id);
    const resolvedOpeningId = matchedElement?.id ?? (Number.isFinite(nearestOpeningId) ? nearestOpeningId : null);
    const openingProjectElement = findProjectElement(selectedProjectDocument, resolvedOpeningId);
    const openingElementId = toNumber(openingProjectElement?.id ?? matchedElement?.id ?? resolvedOpeningId ?? null, NaN);
    const hostWallProjectElement = findProjectOpeningHostWall(selectedProjectDocument, openingElementId);
    const hostWallAxis = projectWallAxis(hostWallProjectElement);
    if (!hostWallProjectElement || !hostWallAxis || !isObject(hostWallProjectElement.wall)) {
      setEditFormError("Opening host wall could not be found.");
      setSvgClickInfo("Opening host wall could not be found.");
      return false;
    }
    const openingKey = (matchedElement?.kind ?? nearest?.kind) === "Window" ? "window" : "door";
    const openingData = isObject(openingProjectElement?.[openingKey]) ? (openingProjectElement?.[openingKey] as JsonObject) : null;
    const widthMeters = toNumber(openingData?.width ?? openingData?.width_meters, openingKey === "door" ? 0.9 : 1.2);
    const heightMeters = toNumber(openingData?.height ?? openingData?.height_meters, openingKey === "door" ? 2.1 : 1.2);
    const sillHeightMeters = toNumber(openingData?.sill_height ?? openingData?.sill_height_meters, openingKey === "door" ? 0 : 0.9);
    const offsetMeters = toNumber(openingData?.offset ?? openingData?.offset_meters, 1.2);

    editDragRef.current = {
      kind: "opening",
      pointerId: event.pointerId,
      openingKind: openingKey,
      openingId: openingElementId,
      openingLabel: `${matchedElement?.kind ?? nearest?.kind ?? "Opening"} #${matchedElement?.id ?? openingMeta?.elementId ?? nearest?.opening.element_id ?? "?"}`,
      hostWallId: toNumber(hostWallProjectElement.id, -1),
      hostWall: hostWallProjectElement,
      hostWallAxis,
      widthMeters,
      heightMeters,
      sillHeightMeters,
      clearanceMeters: 0.05,
      originalOffsetMeters: offsetMeters,
      startSvgPoint: svgPoint,
      startModelPoint: modelPoint,
    };
    setSelectedSvgId(openingMeta?.elementId ?? String(nearest?.opening.element_id ?? matchedElement?.id ?? ""));
    setSelection({
      kind: "element",
      label: `${matchedElement?.kind ?? nearest?.kind ?? "Opening"} #${matchedElement?.id ?? openingMeta?.elementId ?? nearest?.opening.element_id ?? "?"}`,
      value: (matchedElement ?? (openingProjectElement as DebugElement)) as DebugElement,
      svgMeta: {
        elementId: openingMeta?.elementId ?? String(nearest?.opening.element_id ?? matchedElement?.id ?? ""),
        kind: matchedElement?.kind ?? nearest?.kind ?? "Opening",
        hitKind: openingMeta?.hitKind ?? "opening",
        svgId: openingMeta?.svgId ?? null,
      },
    });
    setEditFormError(null);
    setSvgClickInfo(
      `Move ${(matchedElement?.kind ?? nearest?.kind ?? "opening")} preview started on wall #${hostWallProjectElement.id ?? "-"}${svgPoint ? ` • SVG ${svgPoint.x.toFixed(2)}, ${svgPoint.y.toFixed(2)}` : ""}${modelPoint ? ` • model ${modelPoint.x.toFixed(2)}, ${modelPoint.y.toFixed(2)}` : ""}.`,
    );
    if (event.currentTarget.hasPointerCapture(event.pointerId) === false) {
      event.currentTarget.setPointerCapture(event.pointerId);
    }
    return true;
  };

  const beginEditDrag = (target: Element | null, event: React.PointerEvent<HTMLDivElement>) => {
    if (interactionMode === "move-wall") {
      return beginWallMoveDrag(target, event);
    }
    if (interactionMode === "move-opening") {
      return beginOpeningMoveDrag(target, event);
    }
    return false;
  };

  const cancelEditDrag = (message = "Drag cancelled.") => {
    setDraftWall(null);
    setOpeningDraft(createDefaultOpeningDraft());
    setDragPreview(null);
    editDragRef.current = null;
    setEditFormError(null);
    setSvgClickInfo(message);
  };

  const commitWallDrag = async () => {
    if (!dragPreview || dragPreview.kind !== "wall") {
      return;
    }
    if (dragPreview.previewAxis.start.x === dragPreview.originalAxis.start.x && dragPreview.previewAxis.start.y === dragPreview.originalAxis.start.y && dragPreview.previewAxis.end.x === dragPreview.originalAxis.end.x && dragPreview.previewAxis.end.y === dragPreview.originalAxis.end.y) {
      setEditFormError("Wall has not moved yet.");
      return;
    }
    try {
      await postLocalEdit(
        "/api/edit/set-wall-axis",
        {
          wall_id: dragPreview.wallId,
          start: dragPreview.previewAxis.start,
          end: dragPreview.previewAxis.end,
        },
        "Failed to move wall.",
      );
      setDragPreview(null);
      editDragRef.current = null;
      setInteractionMode("select");
      setSvgClickInfo(`Wall ${dragPreview.wallId} moved. Selection preserved if the wall still exists.`);
    } catch {
      // handled by postLocalEdit
    }
  };

  const commitOpeningDrag = async () => {
    if (!dragPreview || dragPreview.kind !== "opening") {
      return;
    }
    if (!dragPreview.preview || !dragPreview.preview.can_place) {
      setEditFormError(dragPreview.preview?.message ?? "Opening placement is not valid.");
      return;
    }
    try {
      const route = dragPreview.openingKind === "door" ? "/api/edit/update-door" : "/api/edit/update-window";
      const body: Record<string, unknown> = {
        [`${dragPreview.openingKind}_id`]: dragPreview.openingId,
        offset_meters: dragPreview.preview.adjusted_offset_meters,
        width_meters: dragPreview.widthMeters,
        height_meters: dragPreview.heightMeters,
      };
      if (dragPreview.openingKind === "window") {
        body.sill_height_meters = dragPreview.sillHeightMeters;
      }
      await postLocalEdit(route, body, `Failed to move ${dragPreview.openingKind}.`);
      setDragPreview(null);
      editDragRef.current = null;
      setInteractionMode("select");
      setSvgClickInfo(`${dragPreview.openingKind === "door" ? "Door" : "Window"} ${dragPreview.openingId} moved. Selection preserved if the opening still exists.`);
    } catch {
      // handled by postLocalEdit
    }
  };

  const submitDraftWall = async () => {
    if (!draftWall?.start || !draftWall.end) {
      setEditFormError("Draw a wall preview first.");
      setEditStatus((current) => ({ ...current, tone: "bad", message: "Draw a wall preview first.", error: "Draw a wall preview first.", timestamp: Date.now() }));
      return;
    }
    if (draftLength === null || draftLength < 0.05) {
      setEditFormError("Wall axis must have non-zero length.");
      setEditStatus((current) => ({ ...current, tone: "bad", message: "Wall axis must have non-zero length.", error: "Wall axis must have non-zero length.", timestamp: Date.now() }));
      return;
    }
    try {
      const payload = await postLocalEdit("/api/edit/create-wall", {
          start: draftWall.start,
          end: draftWall.end,
          height_meters: draftWallParams.heightMeters,
          thickness_meters: draftWallParams.thicknessMeters,
        }, "Failed to create wall.");
      setDraftWall(null);
      setInteractionMode("select");
      setSelection({ kind: "none" });
      setSelectedSvgId(null);
      setSelectedSvgPoint(null);
      setHoveredSvgMeta(null);
      setHoveredSvgPoint(null);
      setSvgClickInfo(payload.message ?? "Local edit applied.");
    } catch {
      // handled by postLocalEdit
    }
  };

  const submitInsertOpening = async (kind: "door" | "window") => {
    const hostWallId = openingDraft.hostWallId ?? selectedWallId;
    if (!hostWallId) {
      setEditFormError("Select a wall first.");
      setEditStatus((current) => ({ ...current, tone: "bad", message: "Select a wall first.", error: "Select a wall first.", timestamp: Date.now() }));
      return;
    }
    if (selectedWallElement?.kind !== "Wall" && selectedWallProjectElement?.kind !== "Wall") {
      setEditFormError("Select a wall first.");
      setEditStatus((current) => ({ ...current, tone: "bad", message: "Select a wall first.", error: "Select a wall first.", timestamp: Date.now() }));
      return;
    }
    const offset = openingDraft.preview?.can_place ? openingDraft.preview.adjusted_offset_meters : openingDraft.offsetMeters;
    const width = openingDraft.widthMeters;
    const height = openingDraft.heightMeters;
    const sillHeight = openingDraft.sillHeightMeters;
    if (offset < 0) {
      setEditFormError("Offset must be zero or greater.");
      return;
    }
    if (width <= 0 || height <= 0) {
      setEditFormError("Width and height must be greater than zero.");
      return;
    }
    if (kind === "window" && sillHeight < 0) {
      setEditFormError("Sill height must be zero or greater.");
      return;
    }
    try {
      const route = kind === "door" ? "/api/edit/insert-door" : "/api/edit/insert-window";
      setSvgClickInfo(
        `POST ${route} host wall ${hostWallId} offset ${offset.toFixed(2)}m width ${width.toFixed(2)}m height ${height.toFixed(2)}m`,
      );
      const body =
        kind === "door"
          ? {
              host_wall_id: hostWallId,
              offset_meters: offset,
              width_meters: width,
              height_meters: height,
              clearance_meters: openingDraft.clearanceMeters,
            }
          : {
              host_wall_id: hostWallId,
              offset_meters: offset,
              width_meters: width,
              height_meters: height,
              sill_height_meters: sillHeight,
              clearance_meters: openingDraft.clearanceMeters,
            };
      const payload = await postLocalEdit(route, body, `Failed to insert ${kind}.`);
      const openingId = payload.commandOutput?.opening_id ?? null;
      setInteractionMode("select");
      setOpeningDraft(createDefaultOpeningDraft());
      if (selectedWallElement) {
        setSelection({
          kind: "element",
          label: `${selectedWallElement.kind ?? "Wall"} #${selectedWallElement.id ?? selectedWallId}`,
          value: selectedWallElement,
          svgMeta: {
            elementId: String(selectedWallElement.id ?? selectedWallId),
            kind: selectedWallElement.kind ?? "Wall",
            hitKind: "wall_body",
            svgId: selectedSvgId ?? null,
          },
        });
      }
      setSelectedSvgPoint(null);
      setHoveredSvgMeta(null);
      setHoveredSvgPoint(null);
      setSvgClickInfo(
        payload.message ??
          `${kind === "door" ? "Door" : "Window"} inserted${openingId ? ` (id ${openingId})` : ""}.`,
      );
    } catch {
      // handled by postLocalEdit
    }
  };

  const submitDeleteSelected = async () => {
    if (selectedEditableId === null) {
      setEditFormError("Select an element first.");
      setEditStatus((current) => ({ ...current, tone: "bad", message: "Select an element first.", error: "Select an element first.", timestamp: Date.now() }));
      return;
    }
    const label = selectedElement?.label ?? `element ${selectedEditableId}`;
    if (typeof window !== "undefined" && !window.confirm(`Delete ${label}?`)) {
      return;
    }
    try {
      await postLocalEdit(
        "/api/edit/delete-element",
        { element_id: selectedEditableId },
        "Failed to delete element.",
        () => {
          setSelection({ kind: "none" });
          setSelectedSvgId(null);
          setSelectedSvgPoint(null);
          setHoveredSvgMeta(null);
          setHoveredSvgPoint(null);
          setHoveredProjectElementId(null);
          setSvgClickInfo("Element deleted.");
        },
      );
    } catch {
      // handled by postLocalEdit
    }
  };

  const submitWallAxisUpdate = async (form: HTMLFormElement) => {
    if (!selectedWallProjectElement?.id) {
      setEditFormError("Select a wall first.");
      setEditStatus((current) => ({ ...current, tone: "bad", message: "Select a wall first.", error: "Select a wall first.", timestamp: Date.now() }));
      return;
    }
    const formData = new FormData(form);
    const startX = Number(formData.get("start_x"));
    const startY = Number(formData.get("start_y"));
    const endX = Number(formData.get("end_x"));
    const endY = Number(formData.get("end_y"));
    if (![startX, startY, endX, endY].every((value) => Number.isFinite(value))) {
      setEditFormError("Wall axis coordinates must be finite numbers.");
      return;
    }
    if (Math.hypot(endX - startX, endY - startY) < 0.05) {
      setEditFormError("Wall axis cannot be zero length.");
      return;
    }
    const body = {
      wall_id: selectedWallProjectElement.id,
      start: {
        x: startX,
        y: startY,
      },
      end: {
        x: endX,
        y: endY,
      },
    };
    setSvgClickInfo(
      `POST /api/edit/set-wall-axis wall ${selectedWallProjectElement.id} start ${startX.toFixed(2)},${startY.toFixed(2)} end ${endX.toFixed(2)},${endY.toFixed(2)}`,
    );
    await postLocalEdit("/api/edit/set-wall-axis", body, "Failed to update wall axis.", () => {
      setSvgClickInfo(`Wall ${selectedWallProjectElement.id} axis updated.`);
    });
  };

  const submitWallPropertiesUpdate = async (form: HTMLFormElement) => {
    if (!selectedWallProjectElement?.id) {
      setEditFormError("Select a wall first.");
      setEditStatus((current) => ({ ...current, tone: "bad", message: "Select a wall first.", error: "Select a wall first.", timestamp: Date.now() }));
      return;
    }
    const formData = new FormData(form);
    const wallTypeValue = String(formData.get("wall_type_id") ?? "").trim();
    const heightMeters = Number(formData.get("height_meters"));
    const thicknessMeters = Number(formData.get("thickness_meters"));
    if (!Number.isFinite(heightMeters) || heightMeters <= 0) {
      setEditFormError("Wall height must be greater than zero.");
      return;
    }
    if (!Number.isFinite(thicknessMeters) || thicknessMeters <= 0) {
      setEditFormError("Wall thickness must be greater than zero.");
      return;
    }
    const body: Record<string, unknown> = {
      wall_id: selectedWallProjectElement.id,
      height_meters: heightMeters,
      thickness_meters: thicknessMeters,
    };
    if (wallTypeValue.length > 0 && Number.isFinite(Number(wallTypeValue))) {
      body.wall_type_id = Number(wallTypeValue);
    }
    setSvgClickInfo(
      `POST /api/edit/update-wall wall ${selectedWallProjectElement.id} height ${heightMeters.toFixed(2)} thickness ${thicknessMeters.toFixed(2)}`,
    );
    await postLocalEdit("/api/edit/update-wall", body, "Failed to update wall properties.", () => {
      setSvgClickInfo(`Wall ${selectedWallProjectElement.id} properties updated.`);
    });
  };

  const submitOpeningUpdate = async (kind: "door" | "window", form: HTMLFormElement) => {
    const selectedOpeningId = kind === "door" ? selectedDoorProjectElement?.id : selectedWindowProjectElement?.id;
    if (!selectedOpeningId) {
      setEditFormError(`Select a ${kind} first.`);
      setEditStatus((current) => ({ ...current, tone: "bad", message: `Select a ${kind} first.`, error: `Select a ${kind} first.`, timestamp: Date.now() }));
      return;
    }
    const formData = new FormData(form);
    const offsetMeters = Number(formData.get("offset_meters"));
    const widthMeters = Number(formData.get("width_meters"));
    const heightMeters = Number(formData.get("height_meters"));
    if (!Number.isFinite(offsetMeters) || offsetMeters < 0) {
      setEditFormError("Offset must be zero or greater.");
      return;
    }
    if (!Number.isFinite(widthMeters) || widthMeters <= 0) {
      setEditFormError("Width must be greater than zero.");
      return;
    }
    if (!Number.isFinite(heightMeters) || heightMeters <= 0) {
      setEditFormError("Height must be greater than zero.");
      return;
    }
    const body: Record<string, unknown> = {
      [`${kind}_id`]: selectedOpeningId,
      offset_meters: offsetMeters,
      width_meters: widthMeters,
      height_meters: heightMeters,
    };
    if (kind === "window") {
      const sillHeightMeters = Number(formData.get("sill_height_meters"));
      if (!Number.isFinite(sillHeightMeters) || sillHeightMeters < 0) {
        setEditFormError("Sill height must be zero or greater.");
        return;
      }
      body.sill_height_meters = sillHeightMeters;
    }
    setSvgClickInfo(
      `POST ${kind === "door" ? "/api/edit/update-door" : "/api/edit/update-window"} ${kind} ${selectedOpeningId} offset ${offsetMeters.toFixed(2)}m width ${widthMeters.toFixed(2)}m height ${heightMeters.toFixed(2)}m`,
    );
    await postLocalEdit(kind === "door" ? "/api/edit/update-door" : "/api/edit/update-window", body, `Failed to update ${kind}.`, () => {
      setSvgClickInfo(`${kind === "door" ? "Door" : "Window"} ${selectedOpeningId} updated.`);
    });
  };

  const onWheel = (event: React.WheelEvent<HTMLDivElement>) => {
    event.preventDefault();
    const nextScale = Math.min(4, Math.max(0.25, scale - event.deltaY * 0.001));
    setScale(nextScale);
  };

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if (viewMode !== "2d") {
      return;
    }
    const target = event.target as Element | null;
    if (interactionMode === "draft-wall") {
      return;
    }
    if (interactionMode === "move-wall" || interactionMode === "move-opening") {
      event.preventDefault();
      if (beginEditDrag(target, event)) {
        return;
      }
      return;
    }
    setDragging(true);
    dragOrigin.current = { x: event.clientX, y: event.clientY, panX: pan.x, panY: pan.y };
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    const target = event.target as Element | null;
    if (editDragRef.current) {
      const svgPoint = svgHostRef.current ? svgPointFromClient(svgHostRef.current, event.clientX, event.clientY, currentSvgViewBox) : null;
      const modelPoint = modelPointFromSvgPoint(svgPoint);
      if (editDragRef.current.kind === "wall") {
        updateWallDragPreview(editDragRef.current, svgPoint, modelPoint);
      } else {
        updateOpeningDragPreview(editDragRef.current, svgPoint, modelPoint);
      }
      if (svgPoint) {
        setSvgClickInfo(
          editDragRef.current.kind === "wall"
            ? `Wall drag preview • SVG ${svgPoint.x.toFixed(2)}, ${svgPoint.y.toFixed(2)}${modelPoint ? ` • model ${modelPoint.x.toFixed(2)}, ${modelPoint.y.toFixed(2)}` : ""}`
            : `Opening drag preview • SVG ${svgPoint.x.toFixed(2)}, ${svgPoint.y.toFixed(2)}${modelPoint ? ` • model ${modelPoint.x.toFixed(2)}, ${modelPoint.y.toFixed(2)}` : ""}`,
        );
      }
      return;
    }
    if (target) {
      const clickable = target.closest("[data-element-id]") as SVGElement | null;
      if (clickable) {
        const elementId = clickable.getAttribute("data-element-id");
        const kind = clickable.getAttribute("data-kind");
        const hitKind = clickable.getAttribute("data-hit-kind");
        if (elementId) {
          setHoveredSvgMeta({
            elementId,
            kind,
            hitKind,
            svgId: clickable.id || null,
          });
          const rect = (event.currentTarget as HTMLDivElement).getBoundingClientRect();
          setHoveredSvgPoint({
            x: event.clientX - rect.left,
            y: event.clientY - rect.top,
          });
          return;
        }
      }
      const svgPoint = svgHostRef.current ? svgPointFromClient(svgHostRef.current, event.clientX, event.clientY, currentSvgViewBox) : null;
      const modelPoint = modelPointFromSvgPoint(svgPoint);
      const nearbyOpening = modelPoint ? nearestOpeningHit(selectedProjectDocument, modelPoint, 0.35) : null;
      const nearbyWall = modelPoint ? nearestWallHit(selectedProjectDocument, modelPoint, 0.45) : null;
      const nearby = nearbyOpening ?? nearbyWall;
      if (nearby) {
        const rect = (event.currentTarget as HTMLDivElement).getBoundingClientRect();
        setHoveredSvgMeta({
          elementId: String(nearbyOpening ? nearbyOpening.opening.element_id ?? nearbyOpening.opening.id ?? "-" : nearbyWall?.wall.id ?? "-"),
          kind: nearbyOpening ? (nearbyOpening.kind === "window" ? "Window" : "Door") : "Wall",
          hitKind: nearbyOpening ? "opening" : "wall_body",
          svgId: nearbyOpening ? null : null,
        });
        setHoveredSvgPoint({
          x: event.clientX - rect.left,
          y: event.clientY - rect.top,
        });
      } else {
        setHoveredSvgMeta(null);
        setHoveredSvgPoint(null);
      }
    }
    if (!dragging || !dragOrigin.current) {
      return;
    }
    const dx = event.clientX - dragOrigin.current.x;
    const dy = event.clientY - dragOrigin.current.y;
    setPan({ x: dragOrigin.current.panX + dx, y: dragOrigin.current.panY + dy });
  };

  const stopDragging = () => {
    setDragging(false);
    dragOrigin.current = null;
    if (editDragRef.current) {
      suppressNextSvgClickRef.current = true;
      editDragRef.current = null;
    }
    setHoveredSvgMeta(null);
    setHoveredSvgPoint(null);
  };

  const handleSvgClick = (event: React.MouseEvent<HTMLDivElement>) => {
    if (suppressNextSvgClickRef.current) {
      suppressNextSvgClickRef.current = false;
      return;
    }
    const target = event.target as Element | null;
    if (!target) {
      return;
    }

    if (viewMode === "2d" && interactionMode === "draft-wall") {
      const rect = (event.currentTarget as HTMLDivElement).getBoundingClientRect();
      const point = screenToHostPoint(event.clientX, event.clientY, rect, pan, scale);
      setSelectedSvgId(null);
      setSelectedSvgPoint(null);
      setHoveredSvgMeta(null);
      setHoveredSvgPoint(null);
      setSelection({ kind: "none" });
      setDraftWall((current) => {
        if (!current || current.end) {
          setSvgClickInfo("Draft wall start set. Click again to preview the wall.");
          return { start: point, end: null };
        }
        const nextDraft = { ...current, end: point };
        setSvgClickInfo(`Draft wall preview only. Approx length ${formatDraftLength(nextDraft.start, nextDraft.end).toFixed(1)} px.`);
        return nextDraft;
      });
      return;
    }

    if (viewMode === "2d" && (interactionMode === "draft-door" || interactionMode === "draft-window")) {
      const wallMeta = findClosestSvgWall(target);
      const wallProjectElement = data?.projectJson && isObject(data.projectJson.document)
        ? asArray<JsonObject>(data.projectJson.document.elements).find((candidate) => toNumber(candidate.id, -1) === toNumber(wallMeta?.elementId ?? -1, -1))
        : null;
      const svgPoint = svgHostRef.current ? svgPointFromClient(svgHostRef.current, event.clientX, event.clientY, currentSvgViewBox) : null;
      const modelPoint = modelPointFromSvgPoint(svgPoint);
      const nearbyWall = !wallMeta && modelPoint ? nearestWallHit(selectedProjectDocument, modelPoint, 0.45) : null;
      const wallCandidate = wallProjectElement ?? (nearbyWall?.wall ?? null);
      const wallAxis = extractWallAxis(isObject(wallCandidate?.wall) ? wallCandidate.wall : null);
      const projected = modelPoint && wallAxis ? projectPointToWallAxis(modelPoint, wallAxis) : null;
      const offsetMeters = projected ? Math.max(0, projected.offset) : openingDraft.offsetMeters;
      const displayRect = (event.currentTarget as HTMLDivElement).getBoundingClientRect();
      const hostWallId = toNumber(wallCandidate?.id ?? nearbyWall?.wall.id ?? null, NaN);
      if (!Number.isFinite(hostWallId)) {
        setSvgClickInfo("Click a wall to place opening.");
        setEditFormError("Click a wall to place opening.");
        return;
      }
      setSelection({
        kind: "element",
        label: `Wall #${hostWallId}`,
        value: (wallCandidate as JsonObject) ?? null,
        svgMeta: {
          elementId: String(hostWallId),
          kind: "Wall",
          hitKind: wallMeta?.hitKind ?? "wall_body",
          svgId: wallMeta?.svgId ?? null,
        },
      });
      setSelectedSvgId(String(hostWallId));
      setSelectedSvgPoint({
        x: event.clientX - displayRect.left,
        y: event.clientY - displayRect.top,
      });
      setHoveredSvgMeta(null);
      setHoveredSvgPoint(null);
      setOpeningDraft((current) => ({
        ...current,
        hostWallId,
        offsetMeters,
        svgPoint,
        modelPoint,
        preview: null,
      }));
      setSvgClickInfo(
        `${openingModeLabel ?? "Opening"} host wall #${hostWallId} selected. SVG ${svgPoint ? `${svgPoint.x.toFixed(2)}, ${svgPoint.y.toFixed(2)}` : "-"} model ${modelPoint ? `${modelPoint.x.toFixed(2)}, ${modelPoint.y.toFixed(2)}` : "-"} offset ${offsetMeters.toFixed(2)}m.`,
      );
      return;
    }

    const clickable = target.closest("[data-element-id]") as Element | null;
    if (clickable) {
      const svgId = clickable.getAttribute("data-element-id") ?? clickable.id;
      if (svgId) {
        setSelectedSvgId(svgId);
        const matchedElement = findElementByIdLoose(data, svgId);
        const svgMeta: SvgMetadata = {
          elementId: svgId,
          kind: clickable.getAttribute("data-kind"),
          hitKind: clickable.getAttribute("data-hit-kind"),
          svgId: clickable.id || null,
        };
        if (matchedElement) {
          setSelection({
            kind: "element",
            label: `${matchedElement.kind ?? "Element"} #${matchedElement.id ?? "?"}`,
            value: matchedElement,
            svgMeta,
          });
        } else {
          setSelection({
            kind: "svg-only",
            label: `${svgMeta.kind ?? "Element"} #${svgMeta.elementId}`,
            svgMeta,
            approxPoint: null,
          });
        }
        setSelectedSvgPoint(null);
        setHoveredSvgMeta(null);
        setHoveredSvgPoint(null);
        setSvgClickInfo(
          `Selected embedded SVG element id: ${svgId}${svgMeta.kind ? ` (${svgMeta.kind})` : ""}${svgMeta.hitKind ? ` • ${svgMeta.hitKind}` : ""}`,
        );
        return;
      }
    }
    const rect = (event.currentTarget as HTMLDivElement).getBoundingClientRect();
    const svgPoint = svgHostRef.current ? svgPointFromClient(svgHostRef.current, event.clientX, event.clientY, currentSvgViewBox) : null;
    const modelPoint = modelPointFromSvgPoint(svgPoint);
    const nearbyOpening = modelPoint ? nearestOpeningHit(selectedProjectDocument, modelPoint, 0.35) : null;
    const nearbyWall = modelPoint ? nearestWallHit(selectedProjectDocument, modelPoint, 0.45) : null;
    if (nearbyOpening) {
      const id = String(nearbyOpening.opening.element_id ?? nearbyOpening.opening.id ?? "");
      const matchedElement = findElementByIdLoose(data, id);
      const svgMeta: SvgMetadata = {
        elementId: id,
        kind: nearbyOpening.kind === "window" ? "Window" : "Door",
        hitKind: "opening",
        svgId: null,
      };
      setSelectedSvgId(id);
      setSelection(
        matchedElement
          ? {
              kind: "element",
              label: `${matchedElement.kind ?? svgMeta.kind} #${matchedElement.id ?? id}`,
              value: matchedElement,
              svgMeta,
            }
          : {
              kind: "svg-only",
              label: `${svgMeta.kind} #${svgMeta.elementId}`,
              svgMeta,
              approxPoint: null,
            },
      );
      setSelectedSvgPoint({
        x: event.clientX - rect.left,
        y: event.clientY - rect.top,
      });
      setHoveredSvgMeta(null);
      setHoveredSvgPoint(null);
      setSvgClickInfo(`Selected nearby ${svgMeta.kind} #${svgMeta.elementId} using model proximity.`);
      return;
    }
    if (nearbyWall) {
      const id = String(nearbyWall.wall.id ?? "");
      const matchedElement = findElementByIdLoose(data, id);
      const svgMeta: SvgMetadata = {
        elementId: id,
        kind: "Wall",
        hitKind: "wall_body",
        svgId: null,
      };
      setSelectedSvgId(id);
      setSelection({
        kind: "element",
        label: `${matchedElement?.kind ?? "Wall"} #${matchedElement?.id ?? id}`,
        value: matchedElement ?? (nearbyWall.wall as DebugElement),
        svgMeta,
      });
      setSelectedSvgPoint({
        x: event.clientX - rect.left,
        y: event.clientY - rect.top,
      });
      setHoveredSvgMeta(null);
      setHoveredSvgPoint(null);
      setSvgClickInfo(`Selected nearby wall #${id} using model proximity.`);
      return;
    }
    const approxPoint = {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };
    setSelectedSvgId(null);
    setSelectedSvgPoint(approxPoint);
    setHoveredSvgMeta(null);
    setHoveredSvgPoint(null);
    setSvgClickInfo(
      `SVG click fallback: no embedded ids were found. Approximate point (${approxPoint.x.toFixed(1)}, ${approxPoint.y.toFixed(1)}).`,
    );
  };

  const selectedElementId =
    selection.kind === "element"
      ? selection.value.id ?? null
      : selection.kind === "svg-only"
        ? Number.isFinite(Number(selection.svgMeta.elementId))
          ? Number(selection.svgMeta.elementId)
          : null
        : null;

  const validationWarnings = validation.warnings;
  const validationErrors = validation.errors;
  const validationIssueList = validationIssuesList(validation.issues);
  const wallScheduleCount = data?.debug.schedules.walls.length ?? 0;
  const openingScheduleCount = data?.debug.schedules.openings.length ?? 0;
  const roomScheduleCount = data?.debug.schedules.rooms.length ?? 0;
  const sceneElementCount = data?.debug.elements.length ?? currentSvgIds.length;
  const debugWallCount = data?.debug.elements.filter((element) => normalizeKindKey(element.kind) === "wall").length ?? 0;
  const debugOpeningCount = data?.debug.elements.filter((element) => {
    const kind = normalizeKindKey(element.kind);
    return kind === "door" || kind === "window";
  }).length ?? 0;
  const debugRoomCount = data?.debug.elements.filter((element) => normalizeKindKey(element.kind) === "room").length ?? 0;
  const artifactConsistencyWarning = data
    ? (() => {
        const messages = [
          !data.projectJson && (!data.obj || artifactStats.objFaceCount === 0) ? "No 3D source available." : null,
          wallScheduleCount !== debugWallCount ? `wall count mismatch (${wallScheduleCount} schedule / ${debugWallCount} debug).` : null,
          openingScheduleCount !== debugOpeningCount ? `opening count mismatch (${openingScheduleCount} schedule / ${debugOpeningCount} debug).` : null,
          roomScheduleCount !== debugRoomCount ? `room count mismatch (${roomScheduleCount} schedule / ${debugRoomCount} debug).` : null,
        ].filter((item): item is string => Boolean(item));
        return messages.length > 0 ? messages.join(" ") : null;
      })()
    : null;
  const lastEditBadge = editBusy
    ? "Creating..."
    : editStatus.tone === "good"
      ? "Success"
      : editStatus.tone === "warn"
        ? "Warnings"
      : editStatus.tone === "bad"
        ? "Error"
        : "Idle";
  const editStatusToneClass =
    editStatus.tone === "good"
      ? "border-emerald-200 bg-emerald-50 text-emerald-900"
      : editStatus.tone === "warn"
        ? "border-amber-200 bg-amber-50 text-amber-900"
        : editStatus.tone === "bad"
          ? "border-rose-200 bg-rose-50 text-rose-900"
          : "border-slate-200 bg-slate-50 text-slate-700";
  const editStatusLabel = editStatus.tone === "bad" ? "Failed" : "Succeeded";

  return (
    <main className="min-h-screen bg-[linear-gradient(180deg,#f5f7f6_0%,#edf1ee_100%)] text-slate-900">
      <header className="sticky top-0 z-20 border-b border-slate-200/80 bg-white/85 backdrop-blur">
        <div className="mx-auto flex max-w-[1800px] items-center justify-between gap-4 px-6 py-4">
          <div>
            <p className="text-xs uppercase tracking-[0.3em] text-emerald-700">Temporary read-only viewer</p>
            <h1 className="text-2xl font-semibold tracking-tight">BIM artifact explorer</h1>
            <p className="mt-1 text-sm text-slate-500">Static artifact mode only, no live engine bridge yet.</p>
          </div>
          <div className="flex flex-wrap items-center gap-3 text-sm">
            <Badge label="Project" value={data?.project.projectName ?? "Loading sample..."} />
            <Badge label="Schema" value={data?.project.schemaVersion?.toString() ?? "-"} />
            <StatusBadge errors={countValidationIssues(validationErrors)} warnings={countValidationIssues(validationWarnings)} />
            <Badge label="Last edit" value={lastEditBadge} />
            <Badge label="Zoom" value={`${Math.round(scale * 100)}%`} />
            <Badge label="Walls" value={wallScheduleCount} />
            <Badge label="Openings" value={openingScheduleCount} />
            <Badge label="Rooms" value={roomScheduleCount} />
            <Badge label="Scene ids" value={sceneElementCount} />
          </div>
        </div>
      </header>

      {!bridgeStatus.configured ? (
        <div className="border-b border-amber-200 bg-amber-50 px-6 py-3 text-sm text-amber-900">
          <div className="mx-auto flex max-w-[1800px] flex-wrap items-start justify-between gap-3">
            <div>
              <p className="font-medium">Bridge not configured</p>
              <p className="mt-1 text-xs">{bridgeStatus.message}</p>
              {bridgeStatus.instructions.length > 0 ? (
                <ul className="mt-2 list-disc space-y-1 pl-5 text-xs">
                  {bridgeStatus.instructions.map((instruction) => (
                    <li key={instruction}>{instruction}</li>
                  ))}
                </ul>
              ) : null}
            </div>
            <button
              type="button"
              className="rounded-full border border-amber-300 bg-white px-3 py-1.5 text-xs font-medium text-amber-900 hover:bg-amber-100"
              onClick={() => {
                void reloadSample();
              }}
            >
              Reload sample
            </button>
          </div>
        </div>
      ) : null}

      <section className="mx-auto grid max-w-[1800px] grid-cols-[320px_minmax(0,1fr)_400px] gap-4 px-4 py-4">
        <aside className="rounded-3xl border border-slate-200 bg-white p-4 shadow-sm">
          <PanelTitle title="Data source" subtitle="Reload or import exported artifacts" />
          <div className="mt-4 flex flex-col gap-2">
            <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-600">
              Mode: <span className="font-medium text-slate-900">{importModeLabel(sourceMode)}</span>
            </div>
            <button className="rounded-2xl bg-emerald-600 px-4 py-2.5 text-left font-medium text-white hover:bg-emerald-700" onClick={reloadSample}>
              Reload sample
            </button>
            <button className="rounded-2xl border border-slate-200 px-4 py-2.5 text-left font-medium hover:bg-slate-50" onClick={importProjectJsonClick}>
              Load local project.json
            </button>
            <button className="rounded-2xl border border-slate-200 px-4 py-2.5 text-left font-medium hover:bg-slate-50" onClick={importArtifactsClick}>
              Load debug_report.json + floorplan.svg
            </button>
            <input
              ref={projectInputRef}
              type="file"
              accept=".json,application/json"
              className="hidden"
              onChange={async (event) => {
                const file = event.target.files?.[0];
                if (!file) {
                  return;
                }
                try {
                  await loadProjectJsonFile(file);
                } catch (error) {
                  setLoadError(error instanceof Error ? error.message : String(error));
                } finally {
                  event.target.value = "";
                }
              }}
            />
            <input
              ref={artifactInputRef}
              type="file"
              multiple
              accept=".json,.svg,application/json,image/svg+xml"
              className="hidden"
              onChange={async (event) => {
                try {
                  await loadArtifactPair(event.target.files);
                } catch (error) {
                  setLoadError(error instanceof Error ? error.message : String(error));
                } finally {
                  event.target.value = "";
                }
              }}
            />
          </div>

          <div className="mt-4 rounded-2xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
            Static artifact mode uses exported files only. SVG click-selection works only if the exporter embeds element ids or `data-element-id` attributes.
          </div>

          <div className="mt-4 rounded-2xl border border-slate-200 bg-slate-50 p-3 text-sm text-slate-700">
            <p className="font-medium text-slate-900">Artifact sync</p>
            <div className="mt-2 grid grid-cols-2 gap-2 text-xs">
              <div className="rounded-xl bg-white px-3 py-2">Exported: {exportTimestamp ?? "not provided"}</div>
              <div className="rounded-xl bg-white px-3 py-2">OBJ vertices: {artifactStats.objVertexCount}</div>
              <div className="rounded-xl bg-white px-3 py-2">OBJ faces: {artifactStats.objFaceCount}</div>
              <div className="rounded-xl bg-white px-3 py-2">OBJ objects: {artifactStats.objObjectCount || 1}</div>
            </div>
            {artifactConsistencyWarning ? (
              <p className="mt-2 text-[11px] text-amber-700">{artifactConsistencyWarning}</p>
            ) : (
              <p className="mt-2 text-[11px] text-emerald-700">2D and 3D artifacts look consistent enough for viewer use.</p>
            )}
          </div>

          {loadError ? (
            <div className="mt-4 rounded-2xl border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800">
              {loadError}
            </div>
          ) : null}

          <div className="mt-6 space-y-4">
            <PanelTitle title="Categories" subtitle="Panel-based inspection works even without SVG ids" />
            <div className="rounded-2xl border border-slate-200 bg-slate-50 p-3">
              <div className="grid grid-cols-2 gap-2 text-xs">
                {kindFilterKeys.map((kind) => (
                  <label key={kind} className="flex items-center gap-2 rounded-xl border border-white bg-white px-2 py-1.5 shadow-sm">
                    <input
                      type="checkbox"
                      checked={kindVisibility[kind]}
                      onChange={() =>
                        setKindVisibility((current) => ({
                          ...current,
                          [kind]: !current[kind],
                        }))
                      }
                    />
                    <span className="capitalize">{kind}</span>
                  </label>
                ))}
              </div>
              <p className="mt-2 text-[11px] text-slate-500">Unchecked kinds are dimmed and not selectable in the SVG view.</p>
            </div>
            {Object.keys(groupedElements).length === 0 ? (
              <EmptyState text="Loading sample artifacts..." />
            ) : (
              Object.entries(groupedElements).map(([kind, items]) => (
                <button
                  key={kind}
                  className={`flex w-full items-center justify-between rounded-2xl border px-3 py-2 text-left transition ${
                    kindVisibility[normalizeKindKey(kind) as KindFilterKey]
                      ? "border-slate-200 hover:bg-slate-50"
                      : "border-slate-100 bg-slate-100 text-slate-400"
                  }`}
                  onClick={() => {
                    setSelection({ kind: "category", label: kind });
                    setSelectedSvgId(null);
                    setSelectedSvgPoint(null);
                  }}
                  disabled={!kindVisibility[normalizeKindKey(kind) as KindFilterKey]}
                >
                  <span className="font-medium">{kind}</span>
                  <span className="text-sm text-slate-500">{items.length}</span>
                </button>
              ))
            )}
          </div>

          <div className="mt-6 space-y-4">
            <PanelTitle title="Elements" subtitle="Click a row to inspect details" />
            {Object.entries(groupedElements).map(([kind, items]) => (
              <div key={kind} className="rounded-2xl border border-slate-200 bg-slate-50 p-3">
                <div className="flex items-center justify-between gap-2">
                  <button
                    className="text-left font-semibold text-slate-900 hover:text-emerald-700"
                    onClick={() => {
                      setSelection({ kind: "category", label: kind });
                      setSelectedSvgId(null);
                      setSelectedSvgPoint(null);
                    }}
                  >
                    {kind}
                  </button>
                  <span className="text-xs uppercase tracking-[0.2em] text-slate-500">{items.length}</span>
                </div>
                <div className="mt-3 space-y-2">
                  {items.map((item, index) => (
                    <button
                      key={`${kind}-${item.id ?? item.name ?? index}`}
                      className={`flex w-full items-start justify-between rounded-xl border px-3 py-2 text-left shadow-sm transition ${
                        selectedElementId === item.id
                          ? "border-emerald-300 bg-emerald-50"
                          : "border-white bg-white hover:border-emerald-200 hover:bg-emerald-50/60"
                      } ${kindVisibility[normalizeKindKey(item.kind) as KindFilterKey] ? "" : "opacity-40"}`}
                      onClick={() => {
                        const svgMeta = item.id != null
                          ? {
                              elementId: String(item.id),
                              kind: item.kind ?? kind,
                              hitKind: null,
                              svgId: null,
                            }
                          : null;
                        setSelection({ kind: "element", label: `${item.kind ?? kind} #${item.id ?? "?"}`, value: item, svgMeta });
                        setSelectedSvgId(item.id != null ? String(item.id) : null);
                        setSelectedSvgPoint(null);
                        setHoveredSvgMeta(null);
                        setHoveredSvgPoint(null);
                      }}
                      disabled={!kindVisibility[normalizeKindKey(item.kind) as KindFilterKey]}
                    >
                      <div>
                        <p className="font-medium text-slate-900">{item.name ?? `Element ${item.id ?? "?"}`}</p>
                        <p className="text-xs text-slate-500">id {item.id ?? "?"}</p>
                      </div>
                      <span className="text-xs uppercase tracking-[0.2em] text-slate-500">{item.dirty ? "Dirty" : "Clean"}</span>
                    </button>
                  ))}
                </div>
              </div>
            ))}
          </div>

          <div className="mt-6 space-y-4">
            <SectionBlock
              title="Walls"
              count={data?.debug.schedules.walls.length ?? 0}
              onSelect={() => {
                setSelection({ kind: "schedule", label: "Walls schedule", rows: data?.debug.schedules.walls ?? [] });
                setSelectedSvgId(null);
                setSelectedSvgPoint(null);
              }}
            />
            <SectionBlock
              title="Rooms"
              count={data?.debug.schedules.rooms.length ?? 0}
              onSelect={() => {
                setSelection({ kind: "schedule", label: "Rooms schedule", rows: data?.debug.schedules.rooms ?? [] });
                setSelectedSvgId(null);
                setSelectedSvgPoint(null);
              }}
            />
            <SectionBlock
              title="Openings"
              count={data?.debug.schedules.openings.length ?? 0}
              onSelect={() => {
                setSelection({ kind: "schedule", label: "Openings schedule", rows: data?.debug.schedules.openings ?? [] });
                setSelectedSvgId(null);
                setSelectedSvgPoint(null);
              }}
            />
            <SectionBlock
              title="Materials"
              count={data?.debug.materials.length ?? 0}
              onSelect={() => {
                setSelection({ kind: "material", label: "Materials", value: data?.debug.materials ?? [] });
                setSelectedSvgId(null);
                setSelectedSvgPoint(null);
              }}
            />
            <SectionBlock
              title="Schedules"
              count={Object.values(data?.debug.schedules ?? {}).reduce((sum, rows) => sum + (Array.isArray(rows) ? rows.length : 0), 0)}
              onSelect={() => {
                setSelection({ kind: "schedule", label: "All schedules", rows: [] });
                setSelectedSvgId(null);
                setSelectedSvgPoint(null);
              }}
            />
          </div>

          <div className="mt-6 rounded-2xl bg-slate-50 p-4 text-sm text-slate-600">
            <p className="font-medium text-slate-900">Export sources</p>
            <p className="mt-2">
              Copy fresh engine exports into <code className="rounded bg-white px-1.5 py-0.5">public/sample</code>.
            </p>
            <p className="mt-2">Preferred source: <code className="rounded bg-white px-1.5 py-0.5">c_basic_building_package</code>.</p>
          </div>
        </aside>

        <section className="min-w-0 rounded-3xl border border-slate-200 bg-white shadow-sm">
          <div className="flex flex-wrap items-center justify-between gap-4 border-b border-slate-200 px-4 py-3">
            <div>
              <p className="text-sm font-medium text-slate-500">Viewer</p>
              <p className="text-lg font-semibold">{viewMode === "2d" ? "2D top view" : "3D scene"}</p>
              <p className="text-xs text-slate-500">
                {viewMode === "2d"
                  ? `Scene elements: ${data?.debug.elementCount ?? 0}`
                  : "3D scene is built from the exported project JSON so walls, rooms, and openings stay separate."}
              </p>
            </div>
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <button
                className={`rounded-full border px-3 py-1.5 ${viewMode === "2d" ? "border-emerald-300 bg-emerald-50 text-emerald-800" : "border-slate-200 hover:bg-slate-50"}`}
                onClick={() => {
                  setViewMode("2d");
                  setInteractionMode("select");
                  setDragPreview(null);
                  editDragRef.current = null;
                }}
              >
                2D Floorplan
              </button>
              <button
                className={`rounded-full border px-3 py-1.5 ${viewMode === "3d" ? "border-emerald-300 bg-emerald-50 text-emerald-800" : "border-slate-200 hover:bg-slate-50"}`}
                onClick={() => {
                  setViewMode("3d");
                  setInteractionMode("select");
                  setDraftWall(null);
                  setDragPreview(null);
                  editDragRef.current = null;
                }}
              >
                3D View
              </button>
              {viewMode === "2d" ? (
                <>
                  <button
                    className={`rounded-full border px-3 py-1.5 ${interactionMode === "select" ? "border-emerald-300 bg-emerald-50 text-emerald-800" : "border-slate-200 hover:bg-slate-50"}`}
                    onClick={() => {
                      resetEditDrafts("Selection mode.");
                    }}
                  >
                    Select
                  </button>
                  <button
                    className={`rounded-full border px-3 py-1.5 ${interactionMode === "draft-wall" ? "border-amber-300 bg-amber-50 text-amber-800" : "border-slate-200 hover:bg-slate-50"}`}
                    onClick={() => {
                      setInteractionMode((current) => (current === "draft-wall" ? "select" : "draft-wall"));
                      setDraftWall(null);
                      setSvgClickInfo("Draft wall preview only. First click sets start, second click sets end.");
                    }}
                  >
                    Add wall draft
                  </button>
                  <button
                    className={`rounded-full border px-3 py-1.5 ${interactionMode === "draft-door" ? "border-amber-300 bg-amber-50 text-amber-800" : "border-slate-200 hover:bg-slate-50"}`}
                    onClick={() => {
                      setInteractionMode((current) => (current === "draft-door" ? "select" : "draft-door"));
                      setDraftWall(null);
                      setOpeningDraft(createDefaultOpeningDraft());
                      setSvgClickInfo("Select a wall first, then confirm door placement.");
                    }}
                  >
                    Add door
                  </button>
                  <button
                    className={`rounded-full border px-3 py-1.5 ${interactionMode === "draft-window" ? "border-amber-300 bg-amber-50 text-amber-800" : "border-slate-200 hover:bg-slate-50"}`}
                    onClick={() => {
                      setInteractionMode((current) => (current === "draft-window" ? "select" : "draft-window"));
                      setDraftWall(null);
                      setOpeningDraft(createDefaultOpeningDraft());
                      setSvgClickInfo("Select a wall first, then confirm window placement.");
                    }}
                  >
                    Add window
                  </button>
                  <button
                    className={`rounded-full border px-3 py-1.5 ${interactionMode === "move-wall" ? "border-sky-300 bg-sky-50 text-sky-800" : "border-slate-200 hover:bg-slate-50"}`}
                    onClick={() => {
                      setInteractionMode((current) => (current === "move-wall" ? "select" : "move-wall"));
                      setDraftWall(null);
                      setOpeningDraft(createDefaultOpeningDraft());
                      setDragPreview(null);
                      editDragRef.current = null;
                      setSvgClickInfo("Move wall mode. Select and drag a wall to preview a translation.");
                    }}
                  >
                    Move wall
                  </button>
                  <button
                    className={`rounded-full border px-3 py-1.5 ${interactionMode === "move-opening" ? "border-sky-300 bg-sky-50 text-sky-800" : "border-slate-200 hover:bg-slate-50"}`}
                    onClick={() => {
                      setInteractionMode((current) => (current === "move-opening" ? "select" : "move-opening"));
                      setDraftWall(null);
                      setOpeningDraft(createDefaultOpeningDraft());
                      setDragPreview(null);
                      editDragRef.current = null;
                      setSvgClickInfo("Move opening mode. Select and drag a door or window along its host wall.");
                    }}
                  >
                    Move opening
                  </button>
                  <button
                    className={`rounded-full border px-3 py-1.5 ${snapToGrid ? "border-sky-300 bg-sky-50 text-sky-800" : "border-slate-200 hover:bg-slate-50"}`}
                    onClick={() => setSnapToGrid((current) => !current)}
                  >
                    Snap {snapToGrid ? "on" : "off"}
                  </button>
                </>
              ) : (
                <div className="rounded-full border border-slate-200 bg-slate-50 px-3 py-1.5 text-xs text-slate-600">
                  3D preview comes from the exported project model.
                </div>
              )}
            </div>
          </div>

          <div className="h-[calc(100vh-190px)] p-4">
            {data ? (
              <ObjViewer
                key={viewMode}
                projectJson={data.projectJson ?? null}
                objText={data.obj ?? null}
                loadedAtLabel={new Date(artifactLoadedAt).toLocaleTimeString()}
                preset={viewMode === "2d" ? "top" : "isometric"}
                interactive={Boolean(data)}
                selectedElementId={selectedEditableId}
                hoveredElementId={hoveredProjectElementId}
                onHover={handleProjectHover}
                onPick={handleProjectPick}
              />
            ) : (
              <div className="flex h-full items-center justify-center rounded-2xl border border-slate-200 bg-white/80 text-slate-500">
                Loading project scene...
              </div>
            )}
          </div>
        </section>

        <aside className="space-y-4 rounded-3xl border border-slate-200 bg-white p-4 shadow-sm">
          <PanelTitle title="Selection" subtitle="Element details, validation, and takeoff" />
          <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
            <p className="text-sm uppercase tracking-[0.2em] text-slate-500">Selected</p>
            <h2 className="mt-1 text-lg font-semibold">{selectedDetails?.title ?? "None"}</h2>
            <p className="mt-2 text-xs text-slate-500">{svgClickInfo}</p>
            <p className="mt-1 text-xs text-slate-500">{hoveredProjectInfo}</p>
            {hoveredDetails ? <p className="mt-1 text-xs text-emerald-700">Hover: {hoveredDetails}</p> : null}
            <pre className="mt-3 max-h-80 overflow-auto whitespace-pre-wrap text-xs leading-5 text-slate-700">
              {selectedDetails?.body ?? "Click a row on the left or click elements in the top view."}
            </pre>
          </div>

          {selectedWallProjectElement ? (
            <form
              key={`wall-${selectedWallProjectElement.id}`}
              className="rounded-2xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-900"
              onSubmit={(event) => {
                event.preventDefault();
                void submitWallPropertiesUpdate(event.currentTarget);
              }}
            >
              <p className="font-medium">Wall editor</p>
              <p className="mt-1 text-xs">Numeric edit only. Axis changes and property updates refresh the local engine artifacts.</p>
              <div className="mt-3 grid grid-cols-2 gap-3 text-xs">
                {(() => {
                  const wall = isObject(selectedWallProjectElement.wall) ? selectedWallProjectElement.wall : null;
                  const axis = isObject(wall?.axis) ? wall.axis : null;
                  const start = isObject(axis?.start) ? axis.start : null;
                  const end = isObject(axis?.end) ? axis.end : null;
                  return (
                    <>
                      <label className="space-y-1">
                        <span className="block uppercase tracking-[0.18em] text-emerald-700">Start x</span>
                        <input
                          name="start_x"
                          type="number"
                          step="0.01"
                          className="w-full rounded-lg border border-emerald-200 bg-white px-2 py-1.5 text-slate-900"
                          defaultValue={toNumber(start?.x, 0)}
                        />
                      </label>
                      <label className="space-y-1">
                        <span className="block uppercase tracking-[0.18em] text-emerald-700">Start y</span>
                        <input
                          name="start_y"
                          type="number"
                          step="0.01"
                          className="w-full rounded-lg border border-emerald-200 bg-white px-2 py-1.5 text-slate-900"
                          defaultValue={toNumber(start?.y, 0)}
                        />
                      </label>
                      <label className="space-y-1">
                        <span className="block uppercase tracking-[0.18em] text-emerald-700">End x</span>
                        <input
                          name="end_x"
                          type="number"
                          step="0.01"
                          className="w-full rounded-lg border border-emerald-200 bg-white px-2 py-1.5 text-slate-900"
                          defaultValue={toNumber(end?.x, 0)}
                        />
                      </label>
                      <label className="space-y-1">
                        <span className="block uppercase tracking-[0.18em] text-emerald-700">End y</span>
                        <input
                          name="end_y"
                          type="number"
                          step="0.01"
                          className="w-full rounded-lg border border-emerald-200 bg-white px-2 py-1.5 text-slate-900"
                          defaultValue={toNumber(end?.y, 0)}
                        />
                      </label>
                      <label className="space-y-1">
                        <span className="block uppercase tracking-[0.18em] text-emerald-700">Height m</span>
                        <input
                          name="height_meters"
                          type="number"
                          step="0.01"
                          min="0.01"
                          className="w-full rounded-lg border border-emerald-200 bg-white px-2 py-1.5 text-slate-900"
                          defaultValue={toNumber(wall?.height, 3)}
                        />
                      </label>
                      <label className="space-y-1">
                        <span className="block uppercase tracking-[0.18em] text-emerald-700">Thickness m</span>
                        <input
                          name="thickness_meters"
                          type="number"
                          step="0.01"
                          min="0.01"
                          className="w-full rounded-lg border border-emerald-200 bg-white px-2 py-1.5 text-slate-900"
                          defaultValue={toNumber(wall?.thickness, 0.2)}
                        />
                      </label>
                      <label className="space-y-1">
                        <span className="block uppercase tracking-[0.18em] text-emerald-700">Wall type id</span>
                        <input
                          name="wall_type_id"
                          type="number"
                          step="1"
                          min="0"
                          className="w-full rounded-lg border border-emerald-200 bg-white px-2 py-1.5 text-slate-900"
                          defaultValue={toNumber(wall?.wall_type_id, 0)}
                        />
                      </label>
                    </>
                  );
                })()}
              </div>
              {editFormError ? <div className="mt-3 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-xs text-rose-700">{editFormError}</div> : null}
              <div className="mt-3 flex flex-wrap gap-2">
                <button
                  type="submit"
                  className="rounded-full bg-emerald-600 px-3 py-1.5 font-medium text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-60"
                  disabled={editBusy}
                >
                  {editBusy ? "Updating..." : "Update wall"}
                </button>
                <button
                  type="button"
                  className="rounded-full border border-emerald-200 bg-white px-3 py-1.5 font-medium text-emerald-900 hover:bg-emerald-100"
                  onClick={() => {
                    void submitDeleteSelected();
                  }}
                  disabled={editBusy}
                >
                  Delete
                </button>
                <button
                  type="button"
                  className="rounded-full border border-emerald-200 bg-white px-3 py-1.5 font-medium text-emerald-900 hover:bg-emerald-100"
                  onClick={(event) => {
                    const form = event.currentTarget.closest("form");
                    if (form instanceof HTMLFormElement) {
                      void submitWallAxisUpdate(form);
                    }
                  }}
                  disabled={editBusy}
                >
                  Apply axis
                </button>
              </div>
            </form>
          ) : selectedDoorProjectElement ? (
            <form
              key={`door-${selectedDoorProjectElement.id}`}
              className="rounded-2xl border border-sky-200 bg-sky-50 p-4 text-sm text-sky-900"
              onSubmit={(event) => {
                event.preventDefault();
                void submitOpeningUpdate("door", event.currentTarget);
              }}
            >
              <p className="font-medium">Door editor</p>
              <p className="mt-1 text-xs">Offset and size edits are numeric only for now.</p>
              {editFormError ? <div className="mt-3 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-xs text-rose-700">{editFormError}</div> : null}
              {(() => {
                const door = isObject(selectedDoorProjectElement.door) ? selectedDoorProjectElement.door : null;
                return (
                  <div className="mt-3 grid grid-cols-2 gap-3 text-xs">
                    <label className="space-y-1">
                      <span className="block uppercase tracking-[0.18em] text-sky-700">Offset m</span>
                      <input
                        name="offset_meters"
                        type="number"
                        step="0.01"
                        min="0"
                        className="w-full rounded-lg border border-sky-200 bg-white px-2 py-1.5 text-slate-900"
                        defaultValue={toNumber(door?.offset, 1.2)}
                      />
                    </label>
                    <label className="space-y-1">
                      <span className="block uppercase tracking-[0.18em] text-sky-700">Width m</span>
                      <input
                        name="width_meters"
                        type="number"
                        step="0.01"
                        min="0.01"
                        className="w-full rounded-lg border border-sky-200 bg-white px-2 py-1.5 text-slate-900"
                        defaultValue={toNumber(door?.width, 0.9)}
                      />
                    </label>
                    <label className="space-y-1">
                      <span className="block uppercase tracking-[0.18em] text-sky-700">Height m</span>
                      <input
                        name="height_meters"
                        type="number"
                        step="0.01"
                        min="0.01"
                        className="w-full rounded-lg border border-sky-200 bg-white px-2 py-1.5 text-slate-900"
                        defaultValue={toNumber(door?.height, 2.1)}
                      />
                    </label>
                    <div className="space-y-1">
                      <span className="block uppercase tracking-[0.18em] text-sky-700">Host</span>
                      <div className="rounded-lg border border-sky-200 bg-white px-2 py-1.5 text-slate-700">
                        wall {String(selectedOpeningHostWallProjectElement?.id ?? (toNumber(door?.host_wall_id, 0) || "-"))}
                        {selectedOpeningHostWall ? ` • ${wallLength(selectedOpeningHostWall).toFixed(2)} m` : ""}
                      </div>
                    </div>
                  </div>
                );
              })()}
              <div className="mt-3 flex flex-wrap gap-2">
                <button
                  type="submit"
                  className="rounded-full bg-sky-600 px-3 py-1.5 font-medium text-white hover:bg-sky-700 disabled:cursor-not-allowed disabled:opacity-60"
                  disabled={editBusy}
                >
                  {editBusy ? "Updating..." : "Update door"}
                </button>
                <button
                  type="button"
                  className="rounded-full border border-sky-200 bg-white px-3 py-1.5 font-medium text-sky-900 hover:bg-sky-100"
                  onClick={() => {
                    void submitDeleteSelected();
                  }}
                  disabled={editBusy}
                >
                  Delete
                </button>
              </div>
            </form>
          ) : selectedWindowProjectElement ? (
            <form
              key={`window-${selectedWindowProjectElement.id}`}
              className="rounded-2xl border border-violet-200 bg-violet-50 p-4 text-sm text-violet-900"
              onSubmit={(event) => {
                event.preventDefault();
                void submitOpeningUpdate("window", event.currentTarget);
              }}
            >
              <p className="font-medium">Window editor</p>
              <p className="mt-1 text-xs">Offset, width, height, and sill height can be edited numerically.</p>
              {editFormError ? <div className="mt-3 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-xs text-rose-700">{editFormError}</div> : null}
              {(() => {
                const windowElement = isObject(selectedWindowProjectElement.window) ? selectedWindowProjectElement.window : null;
                return (
                  <div className="mt-3 grid grid-cols-2 gap-3 text-xs">
                    <label className="space-y-1">
                      <span className="block uppercase tracking-[0.18em] text-violet-700">Offset m</span>
                      <input
                        name="offset_meters"
                        type="number"
                        step="0.01"
                        min="0"
                        className="w-full rounded-lg border border-violet-200 bg-white px-2 py-1.5 text-slate-900"
                        defaultValue={toNumber(windowElement?.offset, 1.2)}
                      />
                    </label>
                    <label className="space-y-1">
                      <span className="block uppercase tracking-[0.18em] text-violet-700">Width m</span>
                      <input
                        name="width_meters"
                        type="number"
                        step="0.01"
                        min="0.01"
                        className="w-full rounded-lg border border-violet-200 bg-white px-2 py-1.5 text-slate-900"
                        defaultValue={toNumber(windowElement?.width, 1.2)}
                      />
                    </label>
                    <label className="space-y-1">
                      <span className="block uppercase tracking-[0.18em] text-violet-700">Height m</span>
                      <input
                        name="height_meters"
                        type="number"
                        step="0.01"
                        min="0.01"
                        className="w-full rounded-lg border border-violet-200 bg-white px-2 py-1.5 text-slate-900"
                        defaultValue={toNumber(windowElement?.height, 1.2)}
                      />
                    </label>
                    <label className="space-y-1">
                      <span className="block uppercase tracking-[0.18em] text-violet-700">Sill m</span>
                      <input
                        name="sill_height_meters"
                        type="number"
                        step="0.01"
                        min="0"
                        className="w-full rounded-lg border border-violet-200 bg-white px-2 py-1.5 text-slate-900"
                        defaultValue={toNumber(windowElement?.sill_height, 0.9)}
                      />
                    </label>
                    <div className="space-y-1">
                      <span className="block uppercase tracking-[0.18em] text-violet-700">Host</span>
                      <div className="rounded-lg border border-violet-200 bg-white px-2 py-1.5 text-slate-700">
                        wall {String(selectedOpeningHostWallProjectElement?.id ?? (toNumber(windowElement?.host_wall_id, 0) || "-"))}
                        {selectedOpeningHostWall ? ` • ${wallLength(selectedOpeningHostWall).toFixed(2)} m` : ""}
                      </div>
                    </div>
                  </div>
                );
              })()}
              <div className="mt-3 flex flex-wrap gap-2">
                <button
                  type="submit"
                  className="rounded-full bg-violet-600 px-3 py-1.5 font-medium text-white hover:bg-violet-700 disabled:cursor-not-allowed disabled:opacity-60"
                  disabled={editBusy}
                >
                  {editBusy ? "Updating..." : "Update window"}
                </button>
                <button
                  type="button"
                  className="rounded-full border border-violet-200 bg-white px-3 py-1.5 font-medium text-violet-900 hover:bg-violet-100"
                  onClick={() => {
                    void submitDeleteSelected();
                  }}
                  disabled={editBusy}
                >
                  Delete
                </button>
              </div>
            </form>
          ) : selectedEditableId !== null ? (
            <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-700">
              <p className="font-medium">Delete selected element</p>
              <p className="mt-1 text-xs">This element can be deleted, but detailed numeric editing is only available for walls, doors, and windows.</p>
              <button
                type="button"
                className="mt-3 rounded-full border border-slate-300 bg-white px-3 py-1.5 font-medium text-slate-900 hover:bg-slate-100"
                onClick={() => {
                  void submitDeleteSelected();
                }}
                disabled={editBusy}
              >
                Delete selected
              </button>
            </div>
          ) : null}

          {interactionMode === "move-wall" ? (
            dragPreview?.kind === "wall" ? (
              <div className="rounded-2xl border border-sky-200 bg-sky-50 p-4 text-sm text-sky-900">
                <p className="font-medium">Move wall preview</p>
                <p className="mt-1 text-xs">Drag is preview-only. Confirm will call the local edit bridge once the axis looks right.</p>
                <div className="mt-3 grid grid-cols-2 gap-3 text-xs">
                  <div className="rounded-lg bg-white/80 px-2 py-1">Wall #{dragPreview.wallId}</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">{snapToGrid ? "Snap on" : "Snap off"}</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">Raw Δx {formatSigned(dragPreview.rawDelta.x)} m</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">Raw Δy {formatSigned(dragPreview.rawDelta.y)} m</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">Preview Δx {formatSigned(dragPreview.delta.x)} m</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">Preview Δy {formatSigned(dragPreview.delta.y)} m</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">Start {dragPreview.originalAxis.start.x.toFixed(2)}, {dragPreview.originalAxis.start.y.toFixed(2)}</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">End {dragPreview.previewAxis.end.x.toFixed(2)}, {dragPreview.previewAxis.end.y.toFixed(2)}</div>
                </div>
                <div className="mt-3 flex flex-wrap gap-2">
                  <button
                    type="button"
                    className="rounded-full bg-sky-600 px-3 py-1.5 font-medium text-white hover:bg-sky-700 disabled:cursor-not-allowed disabled:opacity-60"
                    onClick={() => {
                      void commitWallDrag();
                    }}
                    disabled={editBusy || Math.hypot(dragPreview.delta.x, dragPreview.delta.y) < 1e-6}
                  >
                    {editBusy ? "Moving..." : "Confirm move"}
                  </button>
                  <button
                    type="button"
                    className="rounded-full border border-sky-200 bg-white px-3 py-1.5 font-medium text-sky-900 hover:bg-sky-100"
                    onClick={() => {
                      cancelEditDrag("Wall move cancelled.");
                    }}
                    disabled={editBusy}
                  >
                    Cancel
                  </button>
                </div>
              </div>
            ) : (
              <div className="rounded-2xl border border-sky-200 bg-sky-50 p-4 text-sm text-sky-900">
                <p className="font-medium">Move wall mode</p>
                <p className="mt-1 text-xs">Select a wall, then drag it in the 2D floorplan to preview a translation. Press Esc to cancel.</p>
              </div>
            )
          ) : interactionMode === "move-opening" ? (
            dragPreview?.kind === "opening" ? (
              <div className={`rounded-2xl border p-4 text-sm ${dragPreview.preview?.can_place ? (dragPreview.preview.valid ? "border-emerald-200 bg-emerald-50 text-emerald-900" : "border-amber-200 bg-amber-50 text-amber-900") : "border-rose-200 bg-rose-50 text-rose-900"}`}>
                <p className="font-medium">Move {dragPreview.openingKind} preview</p>
                <p className="mt-1 text-xs">Drag along the host wall. Confirm uses the local edit bridge; invalid placements stay preview-only.</p>
                <div className="mt-3 grid grid-cols-2 gap-3 text-xs">
                  <div className="rounded-lg bg-white/80 px-2 py-1">Opening #{dragPreview.openingId}</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">Host wall #{dragPreview.hostWallId}</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">{snapToGrid ? "Snap on" : "Snap off"}</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">Raw {dragPreview.rawOffsetMeters.toFixed(2)} m</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">Requested {dragPreview.requestedOffsetMeters.toFixed(2)} m</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">Adjusted {dragPreview.previewOffsetMeters.toFixed(2)} m</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">Free {dragPreview.preview?.free_intervals.length ?? 0}</div>
                  <div className="rounded-lg bg-white/80 px-2 py-1">Blocked {dragPreview.preview?.blocked_intervals.length ?? 0}</div>
                </div>
                {dragPreview.preview ? (
                  <div className="mt-3 rounded-xl border border-white/70 bg-white/80 px-3 py-2 text-xs text-slate-700">
                    <p className="font-medium text-slate-900">{dragPreview.preview.message}</p>
                    {dragPreview.preview.warnings.length > 0 ? (
                      <ul className="mt-2 list-disc space-y-1 pl-5">
                        {dragPreview.preview.warnings.map((warning) => (
                          <li key={warning}>{warning}</li>
                        ))}
                      </ul>
                    ) : null}
                    <p className="mt-2">
                      SVG {dragPreview.svgPoint ? `${dragPreview.svgPoint.x.toFixed(2)}, ${dragPreview.svgPoint.y.toFixed(2)}` : "-"} • model {dragPreview.modelPoint ? `${dragPreview.modelPoint.x.toFixed(2)}, ${dragPreview.modelPoint.y.toFixed(2)}` : "-"}
                    </p>
                  </div>
                ) : null}
                <div className="mt-3 flex flex-wrap gap-2">
                  <button
                    type="button"
                    className="rounded-full bg-emerald-600 px-3 py-1.5 font-medium text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:opacity-60"
                    onClick={() => {
                      void commitOpeningDrag();
                    }}
                    disabled={editBusy || !(dragPreview.preview?.can_place ?? false)}
                  >
                    {editBusy ? "Moving..." : "Confirm move"}
                  </button>
                  <button
                    type="button"
                    className="rounded-full border border-emerald-200 bg-white px-3 py-1.5 font-medium text-emerald-900 hover:bg-emerald-100"
                    onClick={() => {
                      cancelEditDrag("Opening move cancelled.");
                    }}
                    disabled={editBusy}
                  >
                    Cancel
                  </button>
                </div>
              </div>
            ) : (
              <div className="rounded-2xl border border-sky-200 bg-sky-50 p-4 text-sm text-sky-900">
                <p className="font-medium">Move opening mode</p>
                <p className="mt-1 text-xs">Select a door or window, then drag it along the host wall to preview offset changes. Press Esc to cancel.</p>
              </div>
            )
          ) : interactionMode === "draft-wall" ? (
            draftWall?.start && draftWall.end ? (
              <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
                <p className="font-medium">Draft wall confirmation</p>
                <p className="mt-1 text-xs">This creates a real wall through the local edit bridge. It is still a development-only flow.</p>
                <div className="mt-3 grid grid-cols-2 gap-3 text-xs">
                  <label className="space-y-1">
                    <span className="block uppercase tracking-[0.18em] text-amber-700">Length</span>
                    <input
                      className="w-full rounded-lg border border-amber-200 bg-white px-2 py-1.5 text-slate-900"
                      value={`${draftLength ? draftLength.toFixed(1) : "-" } px`}
                      readOnly
                    />
                  </label>
                  <label className="space-y-1">
                    <span className="block uppercase tracking-[0.18em] text-amber-700">Height m</span>
                    <input
                      type="number"
                      step="0.1"
                      min="0.1"
                      className="w-full rounded-lg border border-amber-200 bg-white px-2 py-1.5 text-slate-900"
                      value={draftWallParams.heightMeters}
                      onChange={(event) =>
                        setDraftWallParams((current) => ({
                          ...current,
                          heightMeters: Number(event.target.value) || current.heightMeters,
                        }))
                      }
                    />
                  </label>
                  <label className="space-y-1">
                    <span className="block uppercase tracking-[0.18em] text-amber-700">Thickness m</span>
                    <input
                      type="number"
                      step="0.01"
                      min="0.01"
                      className="w-full rounded-lg border border-amber-200 bg-white px-2 py-1.5 text-slate-900"
                      value={draftWallParams.thicknessMeters}
                      onChange={(event) =>
                        setDraftWallParams((current) => ({
                          ...current,
                          thicknessMeters: Number(event.target.value) || current.thicknessMeters,
                        }))
                      }
                    />
                  </label>
                  <div className="space-y-1">
                    <span className="block uppercase tracking-[0.18em] text-amber-700">Mode</span>
                    <div className="rounded-lg border border-amber-200 bg-white px-2 py-1.5 text-slate-700">Preview only until Create wall</div>
                  </div>
                </div>
                <div className="mt-3 flex flex-wrap gap-2">
                  <button
                    className="rounded-full bg-amber-600 px-3 py-1.5 font-medium text-white hover:bg-amber-700 disabled:cursor-not-allowed disabled:opacity-60"
                    onClick={submitDraftWall}
                    disabled={editBusy}
                  >
                    {editBusy ? "Creating..." : "Create wall"}
                  </button>
                  <button
                    className="rounded-full border border-amber-200 bg-white px-3 py-1.5 font-medium text-amber-900 hover:bg-amber-100"
                    onClick={() => {
                      setDraftWall(null);
                      setInteractionMode("select");
                      setSvgClickInfo("Draft wall preview cancelled.");
                    }}
                    disabled={editBusy}
                  >
                    Cancel
                  </button>
                </div>
              </div>
            ) : (
              <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
                <p className="font-medium">Draft wall preview only</p>
                <p className="mt-1 text-xs">First click sets start, second click sets end. Press Esc to cancel.</p>
                <div className="mt-3 space-y-1 text-xs">
                  <p>Start: {draftWall?.start ? `${draftWall.start.x.toFixed(1)}, ${draftWall.start.y.toFixed(1)}` : "-"}</p>
                  <p>End: {draftWall?.end ? `${draftWall.end.x.toFixed(1)}, ${draftWall.end.y.toFixed(1)}` : "-"}</p>
                  <p>Length: {draftLength ? `${draftLength.toFixed(1)} px` : "-"}</p>
                </div>
              </div>
            )
          ) : interactionMode === "draft-door" || interactionMode === "draft-window" ? (
            <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
              <p className="font-medium">{openingModeLabel ?? "Opening"} placement</p>
              <p className="mt-1 text-xs">Click a wall to compute a wall-local offset, or use the manual fields below. The local engine helper validates placement and refreshes the exported artifacts.</p>
              {selectedWallElement ? (
                <div className="mt-3 rounded-xl border border-amber-200 bg-white px-3 py-2 text-xs text-slate-700">
                  <p className="font-medium text-slate-900">Host wall</p>
                  <p>id {selectedWallElement.id ?? "-"}</p>
                  <p>{selectedWallElement.name ?? "Unnamed wall"}</p>
                  <p>wall-local length {selectedWallLength ? `${selectedWallLength.toFixed(2)} m` : "-"}</p>
                  <p>thickness {selectedWallThickness.toFixed(2)} m</p>
                  <p>selected id {openingDraft.hostWallId ?? selectedWallElement.id ?? "-"}</p>
                  <p className="mt-1 text-[11px] text-slate-500">Select another wall in the SVG or side panel to change the host.</p>
                </div>
              ) : (
                <div className="mt-3 rounded-xl border border-amber-200 bg-white px-3 py-2 text-xs text-slate-700">
                  Click a wall to place opening.
                </div>
              )}
              {openingDraft.preview ? (
                <div className={`mt-3 rounded-xl border px-3 py-2 text-xs ${openingDraft.preview.valid ? "border-emerald-200 bg-emerald-50 text-emerald-800" : openingDraft.preview.can_place ? "border-amber-200 bg-amber-50 text-amber-800" : "border-rose-200 bg-rose-50 text-rose-800"}`}>
                  <p className="font-medium">Placement feedback</p>
                  <p className="mt-1">{openingDraft.preview.message}</p>
                  <div className="mt-2 grid grid-cols-2 gap-2">
                    <div className="rounded-lg bg-white/80 px-2 py-1">Requested {openingDraft.preview.requested_offset_meters.toFixed(2)} m</div>
                    <div className="rounded-lg bg-white/80 px-2 py-1">Adjusted {openingDraft.preview.adjusted_offset_meters.toFixed(2)} m</div>
                    <div className="rounded-lg bg-white/80 px-2 py-1">Free intervals {openingDraft.preview.free_intervals.length}</div>
                    <div className="rounded-lg bg-white/80 px-2 py-1">Blocked {openingDraft.preview.blocked_intervals.length}</div>
                  </div>
                  {openingDraft.preview.warnings.length > 0 ? (
                    <ul className="mt-2 list-disc space-y-1 pl-5">
                      {openingDraft.preview.warnings.map((warning) => (
                        <li key={warning}>{warning}</li>
                      ))}
                    </ul>
                  ) : null}
                  <p className="mt-2 font-medium">Debug</p>
                  <p className="mt-1 text-[11px]">
                    SVG {openingDraft.svgPoint ? `${openingDraft.svgPoint.x.toFixed(2)}, ${openingDraft.svgPoint.y.toFixed(2)}` : "-"} • model {openingDraft.modelPoint ? `${openingDraft.modelPoint.x.toFixed(2)}, ${openingDraft.modelPoint.y.toFixed(2)}` : "-"}
                  </p>
                </div>
              ) : null}
              <div className="mt-3 grid grid-cols-2 gap-3 text-xs">
                <label className="space-y-1">
                  <span className="block uppercase tracking-[0.18em] text-amber-700">Offset m</span>
                  <input
                    type="number"
                    step="0.05"
                    min="0"
                    className="w-full rounded-lg border border-amber-200 bg-white px-2 py-1.5 text-slate-900"
                    value={openingDraft.offsetMeters}
                    onChange={(event) =>
                      setOpeningDraft((current) => ({
                        ...current,
                        offsetMeters: Number(event.target.value) || current.offsetMeters,
                      }))
                    }
                  />
                </label>
                <label className="space-y-1">
                  <span className="block uppercase tracking-[0.18em] text-amber-700">Width m</span>
                  <input
                    type="number"
                    step="0.05"
                    min="0.1"
                    className="w-full rounded-lg border border-amber-200 bg-white px-2 py-1.5 text-slate-900"
                    value={openingDraft.widthMeters}
                    onChange={(event) =>
                      setOpeningDraft((current) => ({
                        ...current,
                        widthMeters: Number(event.target.value) || current.widthMeters,
                      }))
                    }
                  />
                </label>
                <label className="space-y-1">
                  <span className="block uppercase tracking-[0.18em] text-amber-700">Height m</span>
                  <input
                    type="number"
                    step="0.05"
                    min="0.1"
                    className="w-full rounded-lg border border-amber-200 bg-white px-2 py-1.5 text-slate-900"
                    value={openingDraft.heightMeters}
                    onChange={(event) =>
                      setOpeningDraft((current) => ({
                        ...current,
                        heightMeters: Number(event.target.value) || current.heightMeters,
                      }))
                    }
                  />
                </label>
                {interactionMode === "draft-window" ? (
                  <label className="space-y-1">
                    <span className="block uppercase tracking-[0.18em] text-amber-700">Sill m</span>
                    <input
                      type="number"
                      step="0.05"
                      min="0"
                      className="w-full rounded-lg border border-amber-200 bg-white px-2 py-1.5 text-slate-900"
                      value={openingDraft.sillHeightMeters}
                      onChange={(event) =>
                        setOpeningDraft((current) => ({
                          ...current,
                          sillHeightMeters: Number(event.target.value) || current.sillHeightMeters,
                        }))
                      }
                    />
                  </label>
                ) : (
                  <div className="space-y-1">
                    <span className="block uppercase tracking-[0.18em] text-amber-700">Sill m</span>
                    <div className="rounded-lg border border-amber-200 bg-white px-2 py-1.5 text-slate-700">0.0 for door</div>
                  </div>
                )}
                <label className="space-y-1">
                  <span className="block uppercase tracking-[0.18em] text-amber-700">Clearance m</span>
                  <input
                    type="number"
                    step="0.01"
                    min="0"
                    className="w-full rounded-lg border border-amber-200 bg-white px-2 py-1.5 text-slate-900"
                    value={openingDraft.clearanceMeters}
                    onChange={(event) =>
                      setOpeningDraft((current) => ({
                        ...current,
                        clearanceMeters: Number(event.target.value) || current.clearanceMeters,
                      }))
                    }
                  />
                </label>
              </div>
              <div className="mt-3 flex flex-wrap gap-2">
                <button
                  className="rounded-full bg-amber-600 px-3 py-1.5 font-medium text-white hover:bg-amber-700 disabled:cursor-not-allowed disabled:opacity-60"
                  onClick={() => submitInsertOpening(interactionMode === "draft-door" ? "door" : "window")}
                  disabled={editBusy || !selectedWallElement || (openingDraft.preview ? !openingDraft.preview.can_place : false)}
                >
                  {editBusy ? "Inserting..." : `Insert ${openingModeLabel ?? "opening"}`}
                </button>
                <button
                  className="rounded-full border border-amber-200 bg-white px-3 py-1.5 font-medium text-amber-900 hover:bg-amber-100"
                  onClick={() => {
                    resetEditDrafts("Opening draft cancelled.");
                  }}
                  disabled={editBusy}
                >
                  Cancel
                </button>
              </div>
            </div>
          ) : null}

          {editStatus.message ? (
            <div className={`rounded-2xl border p-4 text-sm ${editStatusToneClass}`}>
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-medium">Edit status</p>
                  <p className="mt-1 text-xs">{editStatus.command ? `Last command: ${editStatus.command}` : "No command yet."}</p>
                </div>
                <div className="text-right text-xs">
                  <p className="font-medium">{editStatusLabel}</p>
                  <p>{editStatus.timestamp ? new Date(editStatus.timestamp).toLocaleString() : "-"}</p>
                </div>
              </div>
              <p className="mt-2 text-xs">{editStatus.message}</p>
              <div className="mt-3 flex flex-wrap gap-2 text-xs">
                <Pill label="Errors" value={editStatus.validation.errors} tone={editStatus.validation.errors === 0 ? "good" : "bad"} />
                <Pill label="Warnings" value={editStatus.validation.warnings} tone={editStatus.validation.warnings === 0 ? "good" : "warn"} />
                <Pill label="Files" value={editStatus.updatedFiles.length} tone={editStatus.updatedFiles.length > 0 ? "good" : "neutral"} />
              </div>
              {editStatus.output ? (
                <details className="mt-3 rounded-xl border border-current/10 bg-white/70 px-3 py-2 text-xs">
                  <summary className="cursor-pointer font-medium">Helper output</summary>
                  <pre className="mt-2 max-h-40 overflow-auto whitespace-pre-wrap break-words">{editStatus.output}</pre>
                </details>
              ) : null}
              <div className="mt-3">
                <button
                  type="button"
                  className="rounded-full border border-current/20 bg-white px-3 py-1.5 text-xs font-medium hover:bg-black/5"
                  onClick={refreshArtifacts}
                >
                  Reload artifacts
                </button>
              </div>
            </div>
          ) : null}

          <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
            <p className="text-sm uppercase tracking-[0.2em] text-slate-500">Validation</p>
            <div className="mt-2 flex flex-wrap gap-2 text-sm">
              <Pill label="Errors" value={countValidationIssues(validationErrors)} tone={countValidationIssues(validationErrors) === 0 ? "good" : "bad"} />
              <Pill label="Warnings" value={countValidationIssues(validationWarnings)} tone={countValidationIssues(validationWarnings) === 0 ? "good" : "warn"} />
              <Pill label="Issues" value={validationIssueList.length} tone="neutral" />
              <Pill label="Status" value={validation.status} tone={validation.status === "OK" ? "good" : validation.status === "Errors" ? "bad" : "warn"} />
            </div>
            <IssueList issues={validationIssueList} emptyLabel="No validation issues reported." />
            {validationIssueList.length === 0 ? (
              <p className="mt-3 text-sm text-slate-500">No individual validation entries were embedded in this debug report.</p>
            ) : null}
          </div>

          <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
            <p className="text-sm uppercase tracking-[0.2em] text-slate-500">Material takeoff</p>
            <p className="mt-1 text-sm text-slate-600">{materialTakeoff.length} rows</p>
            <div className="mt-3 overflow-hidden rounded-xl border border-slate-200 bg-white">
              <table className="w-full text-left text-xs">
                <thead className="bg-slate-100 text-slate-600">
                  <tr>
                    <th className="px-3 py-2">Material</th>
                    <th className="px-3 py-2">Qty</th>
                    <th className="px-3 py-2">Unit</th>
                    <th className="px-3 py-2">Src</th>
                  </tr>
                </thead>
                <tbody>
                  {(materialTakeoff.length > 0
                    ? materialTakeoff
                    : [{ material_name: "None", quantity: 0, unit: "-", source_count: 0 }]).map((row, index) => (
                    <tr key={index} className="border-t border-slate-200">
                      <td className="px-3 py-2 font-medium">{toStringValue(row.material_name, toStringValue(row.material, "Unnamed"))}</td>
                      <td className="px-3 py-2">{toStringValue(row.quantity, "0")}</td>
                      <td className="px-3 py-2">{toStringValue(row.unit, toStringValue(row.quantity_type, "-"))}</td>
                      <td className="px-3 py-2">
                        {toStringValue(
                          row.source_count,
                          Array.isArray(row.source_element_ids) ? String(row.source_element_ids.length) : "0",
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </aside>
      </section>
    </main>
  );
}

function Badge({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="rounded-full border border-slate-200 bg-slate-50 px-3 py-1.5 text-slate-700">
      <span className="mr-2 text-xs uppercase tracking-[0.2em] opacity-70">{label}</span>
      <span className="font-medium">{value}</span>
    </div>
  );
}

function StatusBadge({ errors, warnings }: { errors: number; warnings: number }) {
  const label = errors > 0 ? "Errors" : warnings > 0 ? "Warnings" : "OK";
  const tone =
    errors > 0
      ? "border-rose-200 bg-rose-50 text-rose-800"
      : warnings > 0
        ? "border-amber-200 bg-amber-50 text-amber-800"
        : "border-emerald-200 bg-emerald-50 text-emerald-800";
  return (
    <div className={`rounded-full border px-3 py-1.5 ${tone}`}>
      <span className="mr-2 text-xs uppercase tracking-[0.2em] opacity-70">Validation</span>
      <span className="font-medium">{label}</span>
    </div>
  );
}

function Pill({
  label,
  value,
  tone,
}: {
  label: string;
  value: number | string;
  tone: "good" | "bad" | "warn" | "neutral";
}) {
  const toneClasses =
    tone === "good"
      ? "bg-emerald-50 text-emerald-800 border-emerald-200"
      : tone === "bad"
        ? "bg-rose-50 text-rose-800 border-rose-200"
        : tone === "warn"
          ? "bg-amber-50 text-amber-800 border-amber-200"
          : "bg-slate-50 text-slate-700 border-slate-200";
  return <span className={`rounded-full border px-2 py-1 ${toneClasses}`}>{label}: {value}</span>;
}

function PanelTitle({ title, subtitle }: { title: string; subtitle: string }) {
  return (
    <div>
      <p className="text-xs uppercase tracking-[0.28em] text-emerald-700">{title}</p>
      <p className="mt-1 text-sm text-slate-500">{subtitle}</p>
    </div>
  );
}

function SectionBlock({ title, count, onSelect }: { title: string; count: number; onSelect: () => void }) {
  return (
    <button className="flex w-full items-center justify-between rounded-2xl border border-slate-200 px-3 py-2 text-left hover:bg-slate-50" onClick={onSelect}>
      <span className="font-medium">{title}</span>
      <span className="text-sm text-slate-500">{count}</span>
    </button>
  );
}

function IssueList({ issues, emptyLabel }: { issues: ValidationIssue[]; emptyLabel: string }) {
  if (issues.length === 0) {
    return <p className="mt-3 text-sm text-slate-500">{emptyLabel}</p>;
  }
  return (
    <div className="mt-3 space-y-2 text-sm">
      {issues.slice(0, 10).map((issue, index) => (
        <div key={`${issue.message ?? "issue"}-${index}`} className="rounded-xl border border-slate-200 bg-white p-3">
          <p className="font-medium text-slate-900">{issue.severity ?? "info"}</p>
          <p className="text-slate-600">{issue.message ?? "Unnamed issue"}</p>
        </div>
      ))}
    </div>
  );
}

function EmptyState({ text }: { text: string }) {
  return <div className="rounded-2xl border border-dashed border-slate-300 p-4 text-sm text-slate-500">{text}</div>;
}

function importModeLabel(sourceMode: "sample" | "project" | "artifacts") {
  switch (sourceMode) {
    case "sample":
      return "Bundled sample";
    case "project":
      return "Local project.json";
    case "artifacts":
      return "Local artifact pair";
  }
}
