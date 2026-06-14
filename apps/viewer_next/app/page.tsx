"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import ObjViewer from "./ObjViewer";

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
  const latestElement = element?.id != null ? data?.debug.elements.find((candidate) => candidate.id === element.id) ?? element : element;
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
    offsetMeters: 1.2,
    widthMeters: 0.9,
    heightMeters: 2.1,
    sillHeightMeters: 0.9,
    clearanceMeters: 0.05,
  };
}

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
  const [interactionMode, setInteractionMode] = useState<"select" | "draft-wall" | "draft-door" | "draft-window">("select");
  const [artifactRevision, setArtifactRevision] = useState(0);
  const [scale, setScale] = useState(1);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [dragging, setDragging] = useState(false);
  const [selectedSvgId, setSelectedSvgId] = useState<string | null>(null);
  const [hoveredSvgMeta, setHoveredSvgMeta] = useState<SvgMetadata | null>(null);
  const [hoveredSvgPoint, setHoveredSvgPoint] = useState<{ x: number; y: number } | null>(null);
  const [selectedSvgPoint, setSelectedSvgPoint] = useState<{ x: number; y: number } | null>(null);
  const [draftWall, setDraftWall] = useState<{ start: { x: number; y: number }; end?: { x: number; y: number } | null } | null>(null);
  const [openingDraft, setOpeningDraft] = useState(createDefaultOpeningDraft);
  const [draftWallParams, setDraftWallParams] = useState({ heightMeters: 3.0, thicknessMeters: 0.2 });
  const [editStatus, setEditStatus] = useState<{ tone: "neutral" | "good" | "warn" | "bad"; message: string }>({
    tone: "neutral",
    message: "No local edits yet.",
  });
  const [editBusy, setEditBusy] = useState(false);
  const [svgClickInfo, setSvgClickInfo] = useState<string>(
    "SVG click selection is approximate until exported ids are embedded.",
  );
  const [sourceMode, setSourceMode] = useState<"sample" | "project" | "artifacts">("sample");
  const [kindVisibility, setKindVisibility] = useState<Record<KindFilterKey, boolean>>(() =>
    Object.fromEntries(kindFilterKeys.map((key) => [key, true])) as Record<KindFilterKey, boolean>,
  );
  const dragOrigin = useRef<{ x: number; y: number; panX: number; panY: number } | null>(null);
  const svgHostRef = useRef<HTMLDivElement | null>(null);
  const projectInputRef = useRef<HTMLInputElement | null>(null);
  const artifactInputRef = useRef<HTMLInputElement | null>(null);
  const currentSvgIds = useMemo(() => extractSvgIds(data?.svg ?? ""), [data]);
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
  const selectedEditableId = selectedElement?.id ?? null;
  const selectedProjectDocument = useMemo(
    () => (data?.projectJson && isObject(data.projectJson.document) ? data.projectJson.document : null),
    [data],
  );
  const selectedProjectElement = useMemo(() => {
    if (selectedEditableId === null || !selectedProjectDocument) {
      return null;
    }
    return asArray<JsonObject>(selectedProjectDocument.elements).find((candidate) => toNumber(candidate.id, -1) === selectedEditableId) ?? null;
  }, [selectedEditableId, selectedProjectDocument]);
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
  const draftLength = draftWall?.start && draftWall?.end ? formatDraftLength(draftWall.start, draftWall.end) : null;
  const openingModeLabel = interactionMode === "draft-door" ? "Door" : interactionMode === "draft-window" ? "Window" : null;
  const hoveredDetails = useMemo(() => {
    if (!hoveredSvgMeta) {
      return null;
    }
    return `${hoveredSvgMeta.kind ?? "element"} #${hoveredSvgMeta.elementId}${hoveredSvgMeta.hitKind ? ` • ${hoveredSvgMeta.hitKind}` : ""}`;
  }, [hoveredSvgMeta]);

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
    setInteractionMode("select");
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
    resetEditDrafts("Reloaded bundled sample.");
    setArtifactRevision((value) => value + 1);
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
    resetEditDrafts("Imported static artifact pair.");
  };

  const importProjectJsonClick = () => projectInputRef.current?.click();
  const importArtifactsClick = () => artifactInputRef.current?.click();

  const postLocalEdit = async <
    TResponse extends {
      success: boolean;
      error?: string;
      message?: string;
      validation?: { issues?: number; warnings?: number; errors?: number };
      commandOutput?: { opening_id?: number; wall_id?: number; element_id?: number };
    },
  >(
    route: string,
    body: Record<string, unknown>,
    fallbackMessage: string,
    onSuccess?: (result: TResponse) => void,
  ) => {
    setEditBusy(true);
    setLoadError(null);
    try {
      const response = await fetch(route, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });
      const payload = (await response.json()) as TResponse;
      if (!response.ok || !payload.success) {
        throw new Error(payload.error ?? fallbackMessage);
      }
      const errors = payload.validation?.errors ?? 0;
      const warnings = payload.validation?.warnings ?? 0;
      setEditStatus({
        tone: errors > 0 || warnings > 0 ? "warn" : "good",
        message: payload.message ?? `${fallbackMessage} Validation: ${errors} errors, ${warnings} warnings.`,
      });
      onSuccess?.(payload);
      setArtifactRevision((value) => value + 1);
      return payload;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setEditStatus({ tone: "bad", message });
      throw error;
    } finally {
      setEditBusy(false);
    }
  };

  const submitDraftWall = async () => {
    if (!draftWall?.start || !draftWall.end) {
      setEditStatus({ tone: "bad", message: "Draw a wall preview first." });
      return;
    }
    try {
      const payload = await postLocalEdit<{
        success: boolean;
        error?: string;
        message?: string;
        validation?: { issues?: number; warnings?: number; errors?: number };
      }>("/api/edit/create-wall", {
          start: draftWall.start,
          end: draftWall.end,
          height_meters: draftWallParams.heightMeters,
          thickness_meters: draftWallParams.thicknessMeters,
        },
        "Failed to create wall.");
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
    if (!selectedWallId) {
      setEditStatus({ tone: "bad", message: "Select a wall first." });
      return;
    }
    if (selectedWallElement?.kind !== "Wall") {
      setEditStatus({ tone: "bad", message: "Select a wall first." });
      return;
    }
    try {
      const route = kind === "door" ? "/api/edit/insert-door" : "/api/edit/insert-window";
      const body =
        kind === "door"
          ? {
              host_wall_id: selectedWallId,
              offset_meters: openingDraft.offsetMeters,
              width_meters: openingDraft.widthMeters,
              height_meters: openingDraft.heightMeters,
              clearance_meters: openingDraft.clearanceMeters,
            }
          : {
              host_wall_id: selectedWallId,
              offset_meters: openingDraft.offsetMeters,
              width_meters: openingDraft.widthMeters,
              height_meters: openingDraft.heightMeters,
              sill_height_meters: openingDraft.sillHeightMeters,
              clearance_meters: openingDraft.clearanceMeters,
            };
      const payload = await postLocalEdit<{
        success: boolean;
        error?: string;
        message?: string;
        validation?: { issues?: number; warnings?: number; errors?: number };
        commandOutput?: { opening_id?: number; wall_id?: number; placement?: { warnings?: string[] } };
      }>(route, body, `Failed to insert ${kind}.`);
      const openingId = payload.commandOutput?.opening_id ?? null;
      setInteractionMode("select");
      setOpeningDraft(createDefaultOpeningDraft());
      setSelection({ kind: "none" });
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
      setEditStatus({ tone: "bad", message: "Select an element first." });
      return;
    }
    const label = selectedElement?.label ?? `element ${selectedEditableId}`;
    if (typeof window !== "undefined" && !window.confirm(`Delete ${label}?`)) {
      return;
    }
    try {
      await postLocalEdit<{ success: boolean; error?: string; message?: string; validation?: { issues?: number; warnings?: number; errors?: number } }>(
        "/api/edit/delete-element",
        { element_id: selectedEditableId },
        "Failed to delete element.",
        () => {
          setSelection({ kind: "none" });
          setSelectedSvgId(null);
          setSelectedSvgPoint(null);
          setHoveredSvgMeta(null);
          setHoveredSvgPoint(null);
          setSvgClickInfo("Element deleted.");
        },
      );
    } catch {
      // handled by postLocalEdit
    }
  };

  const submitWallAxisUpdate = async (form: HTMLFormElement) => {
    if (!selectedWallProjectElement?.id) {
      setEditStatus({ tone: "bad", message: "Select a wall first." });
      return;
    }
    const formData = new FormData(form);
    const body = {
      wall_id: selectedWallProjectElement.id,
      start: {
        x: Number(formData.get("start_x")),
        y: Number(formData.get("start_y")),
      },
      end: {
        x: Number(formData.get("end_x")),
        y: Number(formData.get("end_y")),
      },
    };
    await postLocalEdit("/api/edit/set-wall-axis", body, "Failed to update wall axis.", () => {
      setSvgClickInfo(`Wall ${selectedWallProjectElement.id} axis updated.`);
    });
  };

  const submitWallPropertiesUpdate = async (form: HTMLFormElement) => {
    if (!selectedWallProjectElement?.id) {
      setEditStatus({ tone: "bad", message: "Select a wall first." });
      return;
    }
    const formData = new FormData(form);
    const wallTypeValue = String(formData.get("wall_type_id") ?? "").trim();
    const body: Record<string, unknown> = {
      wall_id: selectedWallProjectElement.id,
      height_meters: Number(formData.get("height_meters")),
      thickness_meters: Number(formData.get("thickness_meters")),
    };
    if (wallTypeValue.length > 0 && Number.isFinite(Number(wallTypeValue))) {
      body.wall_type_id = Number(wallTypeValue);
    }
    await postLocalEdit("/api/edit/update-wall", body, "Failed to update wall properties.", () => {
      setSvgClickInfo(`Wall ${selectedWallProjectElement.id} properties updated.`);
    });
  };

  const submitOpeningUpdate = async (kind: "door" | "window", form: HTMLFormElement) => {
    const selectedOpeningId = kind === "door" ? selectedDoorProjectElement?.id : selectedWindowProjectElement?.id;
    if (!selectedOpeningId) {
      setEditStatus({ tone: "bad", message: `Select a ${kind} first.` });
      return;
    }
    const formData = new FormData(form);
    const body: Record<string, unknown> = {
      [`${kind}_id`]: selectedOpeningId,
      offset_meters: Number(formData.get("offset_meters")),
      width_meters: Number(formData.get("width_meters")),
      height_meters: Number(formData.get("height_meters")),
    };
    if (kind === "window") {
      body.sill_height_meters = Number(formData.get("sill_height_meters"));
    }
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
    if (viewMode === "2d" && interactionMode === "draft-wall") {
      return;
    }
    setDragging(true);
    dragOrigin.current = { x: event.clientX, y: event.clientY, panX: pan.x, panY: pan.y };
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    const target = event.target as Element | null;
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
        }
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
    setHoveredSvgMeta(null);
    setHoveredSvgPoint(null);
  };

  const handleSvgClick = (event: React.MouseEvent<HTMLDivElement>) => {
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
      const clickable = target.closest("[data-element-id]") as Element | null;
      if (clickable) {
        const kind = normalizeKindKey(clickable.getAttribute("data-kind"));
        const elementId = clickable.getAttribute("data-element-id");
        if (kind === "wall" && elementId) {
          const matchedElement = findElementByIdLoose(data, elementId);
          if (matchedElement) {
            setSelection({
              kind: "element",
              label: `${matchedElement.kind ?? "Wall"} #${matchedElement.id ?? elementId}`,
              value: matchedElement,
              svgMeta: {
                elementId,
                kind: matchedElement.kind ?? null,
                hitKind: clickable.getAttribute("data-hit-kind"),
                svgId: clickable.id || null,
              },
            });
            setSelectedSvgId(elementId);
            setSelectedSvgPoint(null);
            setSvgClickInfo(`${openingModeLabel ?? "Opening"} host wall selected.`);
            return;
          }
        }
      }
      setSvgClickInfo("Select a wall first.");
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
  const lastEditBadge = editBusy
    ? "Creating..."
    : editStatus.tone === "good"
      ? "Success"
      : editStatus.tone === "warn"
        ? "Warnings"
        : editStatus.tone === "bad"
          ? "Error"
          : "Idle";

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
          </div>
        </div>
      </header>

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
              <p className="text-lg font-semibold">{viewMode === "2d" ? "SVG floorplan" : "3D OBJ view"}</p>
              <p className="text-xs text-slate-500">
                {viewMode === "2d"
                  ? `SVG ids detected: ${currentSvgIds.length > 0 ? `${currentSvgIds.length}` : "none"}`
                  : "OBJ geometry is read-only and selection is metadata-free for now."}
              </p>
            </div>
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <button
                className={`rounded-full border px-3 py-1.5 ${viewMode === "2d" ? "border-emerald-300 bg-emerald-50 text-emerald-800" : "border-slate-200 hover:bg-slate-50"}`}
                onClick={() => {
                  setViewMode("2d");
                  setInteractionMode("select");
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
                  <button className="rounded-full border border-slate-200 px-3 py-1.5 hover:bg-slate-50" onClick={() => setScale((value) => Math.min(4, value + 0.1))}>
                    Zoom +
                  </button>
                  <button className="rounded-full border border-slate-200 px-3 py-1.5 hover:bg-slate-50" onClick={() => setScale((value) => Math.max(0.25, value - 0.1))}>
                    Zoom -
                  </button>
                  <button className="rounded-full border border-slate-200 px-3 py-1.5 hover:bg-slate-50" onClick={resetView}>
                    Reset
                  </button>
                </>
              ) : (
                <div className="rounded-full border border-slate-200 bg-slate-50 px-3 py-1.5 text-xs text-slate-600">
                  OBJ preview only. Metadata-based picking comes later.
                </div>
              )}
            </div>
          </div>

          {viewMode === "2d" ? (
            <div
              ref={svgHostRef}
              className="relative h-[calc(100vh-190px)] overflow-hidden bg-[radial-gradient(circle_at_top,#f8faf8_0,#eef4f0_55%,#e6ece8_100%)]"
              onClick={handleSvgClick}
              onWheel={onWheel}
              onPointerDown={onPointerDown}
              onPointerMove={onPointerMove}
              onPointerUp={stopDragging}
              onPointerLeave={stopDragging}
            >
              {data ? (
                <div
                  className={`absolute inset-0 origin-top-left ${dragging ? "cursor-grabbing" : interactionMode === "draft-wall" ? "cursor-crosshair" : "cursor-grab"}`}
                  style={{ transform: `translate(${pan.x}px, ${pan.y}px) scale(${scale})` }}
                >
                  <div className="p-6">
                    <div className="relative inline-block rounded-2xl border border-slate-200 bg-white/80 p-4 shadow-lg">
                      <div className="svg-canvas max-w-full" dangerouslySetInnerHTML={{ __html: data.svg }} />
                      {draftWall?.start ? (
                        <svg className="pointer-events-none absolute inset-0 h-full w-full overflow-visible">
                          {draftWall.end ? (
                            <>
                              <line
                                x1={draftWall.start.x}
                                y1={draftWall.start.y}
                                x2={draftWall.end.x}
                                y2={draftWall.end.y}
                                stroke="#f59e0b"
                                strokeWidth="3"
                                strokeDasharray="8 6"
                              />
                              <circle cx={draftWall.start.x} cy={draftWall.start.y} r="5" fill="#f59e0b" />
                              <circle cx={draftWall.end.x} cy={draftWall.end.y} r="5" fill="#f59e0b" />
                              <text x={(draftWall.start.x + draftWall.end.x) / 2 + 8} y={(draftWall.start.y + draftWall.end.y) / 2 - 8} fill="#92400e" fontSize="12">
                                {draftLength ? `Preview ${draftLength.toFixed(1)} px` : "Draft preview only"}
                              </text>
                            </>
                          ) : (
                            <circle cx={draftWall.start.x} cy={draftWall.start.y} r="5" fill="#f59e0b" />
                          )}
                        </svg>
                      ) : null}
                    </div>
                  </div>
                </div>
              ) : (
                <div className="flex h-full items-center justify-center text-slate-500">Loading floorplan SVG...</div>
              )}

              {selectedSvgPoint ? (
                <div
                  className="pointer-events-none absolute z-10 rounded-full border-2 border-rose-600 bg-rose-100/60"
                  style={{
                    left: `${selectedSvgPoint.x - 10}px`,
                    top: `${selectedSvgPoint.y - 10}px`,
                    width: 20,
                    height: 20,
                  }}
                />
              ) : null}

              {hoveredSvgMeta && hoveredSvgPoint ? (
                <div
                  className="pointer-events-none absolute z-20 rounded-lg border border-slate-200 bg-slate-900/90 px-2.5 py-1.5 text-xs text-white shadow-lg"
                  style={{
                    left: `${Math.min(hoveredSvgPoint.x + 14, 280)}px`,
                    top: `${Math.max(hoveredSvgPoint.y - 12, 8)}px`,
                  }}
                >
                  <div className="font-medium">
                    {hoveredSvgMeta.kind ?? "Element"} #{hoveredSvgMeta.elementId}
                  </div>
                  <div className="text-[11px] text-slate-200">{hoveredSvgMeta.hitKind ?? "hover"}</div>
                </div>
              ) : null}

              {interactionMode === "draft-wall" ? (
                <div className="pointer-events-none absolute left-4 bottom-4 z-20 rounded-2xl border border-amber-200 bg-amber-50/95 px-3 py-2 text-xs text-amber-900 shadow">
                  Draft preview only. First click sets start, second click sets end. Press Esc to cancel.
                </div>
              ) : interactionMode === "draft-door" || interactionMode === "draft-window" ? (
                <div className="pointer-events-none absolute left-4 bottom-4 z-20 rounded-2xl border border-amber-200 bg-amber-50/95 px-3 py-2 text-xs text-amber-900 shadow">
                  {openingModeLabel ?? "Opening"} draft. Select a wall, then confirm placement from the side panel.
                </div>
              ) : null}
            </div>
          ) : (
            <div className="h-[calc(100vh-190px)] p-4">
              <ObjViewer objText={data?.obj ?? null} />
            </div>
          )}

          <style jsx global>{`
            .svg-canvas [data-element-id] {
              transition:
                opacity 140ms ease,
                filter 140ms ease,
                transform 140ms ease;
            }
            .svg-canvas [data-kind-hidden="true"] {
              opacity: 0.12;
              pointer-events: none;
            }
            .svg-canvas [data-hovered-svg="true"] * {
              stroke: #0ea5e9 !important;
              stroke-width: 2px !important;
              filter: drop-shadow(0 0 4px rgba(14, 165, 233, 0.55));
            }
            .svg-canvas [data-selected-svg="true"] * {
              stroke: #059669 !important;
              stroke-width: 2.5px !important;
              filter: drop-shadow(0 0 6px rgba(5, 150, 105, 0.75));
            }
          `}</style>
        </section>

        <aside className="space-y-4 rounded-3xl border border-slate-200 bg-white p-4 shadow-sm">
          <PanelTitle title="Selection" subtitle="Element details, validation, and takeoff" />
          <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
            <p className="text-sm uppercase tracking-[0.2em] text-slate-500">Selected</p>
            <h2 className="mt-1 text-lg font-semibold">{selectedDetails?.title ?? "None"}</h2>
            <p className="mt-2 text-xs text-slate-500">{svgClickInfo}</p>
            {hoveredDetails ? <p className="mt-1 text-xs text-emerald-700">Hover: {hoveredDetails}</p> : null}
            <pre className="mt-3 max-h-80 overflow-auto whitespace-pre-wrap text-xs leading-5 text-slate-700">
              {selectedDetails?.body ?? "Click a row on the left or click SVG elements with embedded ids."}
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
                        wall {toNumber(door?.host_wall_id, 0) || "-"}
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

          {interactionMode === "draft-wall" ? (
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
              <p className="mt-1 text-xs">This uses the selected wall and manual offsets for now. The local engine helper validates placement and refreshes the exported artifacts.</p>
              {selectedWallElement ? (
                <div className="mt-3 rounded-xl border border-amber-200 bg-white px-3 py-2 text-xs text-slate-700">
                  <p className="font-medium text-slate-900">Host wall</p>
                  <p>id {selectedWallElement.id ?? "-"}</p>
                  <p>{selectedWallElement.name ?? "Unnamed wall"}</p>
                  <p className="mt-1 text-[11px] text-slate-500">Select another wall in the SVG or side panel to change the host.</p>
                </div>
              ) : (
                <div className="mt-3 rounded-xl border border-amber-200 bg-white px-3 py-2 text-xs text-slate-700">
                  Select a wall first.
                </div>
              )}
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
                  disabled={editBusy || !selectedWallElement}
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
            <div
              className={`rounded-2xl border p-4 text-sm ${
                editStatus.tone === "good"
                  ? "border-emerald-200 bg-emerald-50 text-emerald-900"
                  : editStatus.tone === "warn"
                    ? "border-amber-200 bg-amber-50 text-amber-900"
                    : editStatus.tone === "bad"
                      ? "border-rose-200 bg-rose-50 text-rose-900"
                      : "border-slate-200 bg-slate-50 text-slate-700"
              }`}
            >
              <p className="font-medium">Edit status</p>
              <p className="mt-1 text-xs">{editStatus.message}</p>
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
