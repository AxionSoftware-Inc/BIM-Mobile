"use client";

import * as THREE from "three";

type JsonPrimitive = string | number | boolean | null;
type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
type JsonObject = { [key: string]: JsonValue };

export type RenderScenePoint = { x: number; y: number; z: number };
export type RenderSceneBounds = { min: RenderScenePoint; max: RenderScenePoint };
export type RenderSceneMesh = {
  positions: RenderScenePoint[];
  indices: number[];
  normals: RenderScenePoint[] | null;
};
export type RenderSceneObject = {
  elementId: number | null;
  kind: string;
  levelId: number | null;
  selectable: boolean;
  visibleByDefault: boolean;
  revision: number;
  bounds: RenderSceneBounds;
  mesh: RenderSceneMesh;
  materialCategory: string;
};
export type RenderScene = {
  sceneVersion: number;
  units: string;
  coordinateSystem: string;
  objectCount: number;
  vertexCount: number;
  indexCount: number;
  objects: RenderSceneObject[];
  source: string;
};
export type RenderSceneDiagnostics = {
  source: string;
  objectCount: number;
  selectableObjectCount: number;
  visibleObjectCount: number;
  vertexCount: number;
  indexCount: number;
  triangleCount: number;
  levelCount: number;
  missingGeometryCount: number;
  invalidBoundsCount: number;
  kindCounts: Record<string, number>;
};
export type RenderSceneBuildResult = {
  root: THREE.Group;
  bounds: THREE.Box3;
  diagnostics: RenderSceneDiagnostics;
};

type KindVisibility = Record<string, boolean>;

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asArray<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

function toNumber(value: unknown, fallback = 0) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function toStringValue(value: unknown, fallback = "") {
  return typeof value === "string" && value.length > 0 ? value : fallback;
}

function normalizeKindKey(value: unknown) {
  return typeof value === "string" && value.length > 0 ? value.trim().toLowerCase() : "unknown";
}

function filterKindKey(kind: string) {
  const normalized = normalizeKindKey(kind);
  if (normalized === "floorsystem") {
    return "floor";
  }
  if (normalized === "ceilingsystem") {
    return "ceiling";
  }
  if (normalized === "opening") {
    return "door";
  }
  return normalized;
}

function extractPoint3(value: unknown): RenderScenePoint | null {
  if (!isObject(value)) {
    return null;
  }
  const x = toNumber(value.x, Number.NaN);
  const y = toNumber(value.y, Number.NaN);
  const z = toNumber(value.z, Number.NaN);
  if (![x, y, z].every(Number.isFinite)) {
    return null;
  }
  return { x, y, z };
}

function extractBounds(value: unknown): RenderSceneBounds | null {
  if (!isObject(value)) {
    return null;
  }
  const min = extractPoint3(value.min);
  const max = extractPoint3(value.max);
  if (!min || !max) {
    return null;
  }
  return { min, max };
}

function makeBoundsFromPositions(positions: RenderScenePoint[]): RenderSceneBounds {
  const bounds = new THREE.Box3();
  for (const position of positions) {
    if (!Number.isFinite(position.x) || !Number.isFinite(position.y) || !Number.isFinite(position.z)) {
      continue;
    }
    bounds.expandByPoint(new THREE.Vector3(position.x, position.z, position.y));
  }
  if (bounds.isEmpty()) {
    return {
      min: { x: 0, y: 0, z: 0 },
      max: { x: 0, y: 0, z: 0 },
    };
  }
  return {
    min: { x: bounds.min.x, y: bounds.min.z, z: bounds.min.y },
    max: { x: bounds.max.x, y: bounds.max.z, z: bounds.max.y },
  };
}

function extractMesh(value: unknown): RenderSceneMesh {
  if (!isObject(value)) {
    return { positions: [], indices: [], normals: null };
  }
  const positions = asArray<JsonValue>(value.positions)
    .map((entry) => extractPoint3(entry))
    .filter((entry): entry is RenderScenePoint => entry !== null);
  const indices = asArray<unknown>(value.indices)
    .map((entry) => toNumber(entry, Number.NaN))
    .filter((entry) => Number.isFinite(entry) && entry >= 0)
    .map((entry) => Math.floor(entry));
  const normalsValue = value.normals;
  const normals = Array.isArray(normalsValue)
    ? normalsValue
        .map((entry) => extractPoint3(entry))
        .filter((entry): entry is RenderScenePoint => entry !== null)
    : null;
  return { positions, indices, normals };
}

function parseRenderSceneObject(value: unknown): RenderSceneObject | null {
  if (!isObject(value)) {
    return null;
  }
  const mesh = extractMesh(value.mesh);
  const bounds = extractBounds(value.bounds) ?? makeBoundsFromPositions(mesh.positions);
  const kind = toStringValue(value.kind, "Unknown");
  return {
    elementId: Number.isFinite(toNumber(value.element_id, Number.NaN)) ? toNumber(value.element_id, 0) : null,
    kind,
    levelId: Number.isFinite(toNumber(value.level_id, Number.NaN)) ? toNumber(value.level_id, 0) : null,
    selectable: value.selectable !== false,
    visibleByDefault: value.visible_by_default !== false,
    revision: Math.max(0, Math.floor(toNumber(value.revision, 0))),
    bounds,
    mesh,
    materialCategory: toStringValue(value.material_category, "generic"),
  };
}

export function normalizeRenderScene(value: unknown, source = "render_scene.json"): RenderScene | null {
  if (!isObject(value)) {
    return null;
  }
  const objects = asArray<unknown>(value.objects)
    .map((entry) => parseRenderSceneObject(entry))
    .filter((entry): entry is RenderSceneObject => entry !== null);
  if (objects.length === 0) {
    return null;
  }
  return {
    sceneVersion: Math.max(1, Math.floor(toNumber(value.scene_version ?? value.sceneVersion, 1))),
    units: toStringValue(value.units, "meters"),
    coordinateSystem: toStringValue(value.coordinate_system ?? value.coordinateSystem, "X/Y plan, Z up"),
    objectCount: Math.max(0, Math.floor(toNumber(value.object_count ?? value.objectCount, objects.length))),
    vertexCount: Math.max(0, Math.floor(toNumber(value.vertex_count ?? value.vertexCount, 0))),
    indexCount: Math.max(0, Math.floor(toNumber(value.index_count ?? value.indexCount, 0))),
    objects,
    source,
  };
}

function geometryFromRenderSceneMesh(mesh: RenderSceneMesh) {
  const geometry = new THREE.BufferGeometry();
  if (mesh.positions.length === 0 || mesh.indices.length < 3) {
    return null;
  }

  const positions = new Float32Array(mesh.positions.length * 3);
  mesh.positions.forEach((position, index) => {
    positions[index * 3] = position.x;
    positions[index * 3 + 1] = position.z;
    positions[index * 3 + 2] = position.y;
  });
  geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  geometry.setIndex(mesh.indices);

  if (mesh.normals && mesh.normals.length === mesh.positions.length) {
    const normals = new Float32Array(mesh.normals.length * 3);
    mesh.normals.forEach((normal, index) => {
      normals[index * 3] = normal.x;
      normals[index * 3 + 1] = normal.z;
      normals[index * 3 + 2] = normal.y;
    });
    geometry.setAttribute("normal", new THREE.BufferAttribute(normals, 3));
  } else {
    geometry.computeVertexNormals();
  }

  geometry.computeBoundingBox();
  return geometry;
}

function colorForKind(kind: string, category: string) {
  const normalizedKind = normalizeKindKey(kind);
  const normalizedCategory = normalizeKindKey(category);
  if (normalizedKind === "wall") {
    return 0x334155;
  }
  if (normalizedKind === "door") {
    return 0xc084fc;
  }
  if (normalizedKind === "window") {
    return 0x60a5fa;
  }
  if (normalizedKind === "slab" || normalizedKind === "floorsystem") {
    return 0x64748b;
  }
  if (normalizedKind === "ceiling" || normalizedKind === "ceilingsystem") {
    return 0xa78bfa;
  }
  if (normalizedKind === "roof") {
    return 0x0f766e;
  }
  if (normalizedKind === "column" || normalizedKind === "beam" || normalizedKind === "stair") {
    return 0x475569;
  }
  if (normalizedCategory === "glass") {
    return 0x60a5fa;
  }
  if (normalizedCategory === "finish") {
    return 0xc084fc;
  }
  if (normalizedCategory === "structural") {
    return 0x334155;
  }
  return 0x64748b;
}

function makeMaterial(kind: string, category: string, wireframe: boolean) {
  return new THREE.MeshStandardMaterial({
    color: colorForKind(kind, category),
    roughness: 0.84,
    metalness: 0.02,
    side: THREE.DoubleSide,
    transparent: true,
    opacity: wireframe ? 1 : 0.84,
    wireframe,
    depthWrite: !wireframe,
  });
}

function addGeometryObject(
  root: THREE.Group,
  object: RenderSceneObject,
  index: number,
  kindVisibility: KindVisibility,
  wireframe: boolean,
) {
  const geometry = geometryFromRenderSceneMesh(object.mesh);
  if (!geometry) {
    return {
      added: false,
      selectable: false,
      vertexCount: 0,
      indexCount: 0,
      invalidBounds: true,
    };
  }

  const key = filterKindKey(object.kind);
  const visible = object.visibleByDefault !== false && kindVisibility[key] !== false;
  const material = makeMaterial(object.kind, object.materialCategory, wireframe);
  const mesh = new THREE.Mesh(geometry, material);
  mesh.name = `render-scene-${key}-${object.elementId ?? index + 1}`;
  mesh.visible = visible;
  mesh.userData = {
    elementId: object.elementId,
    kind: object.kind,
    levelId: object.levelId,
    selectable: object.selectable !== false,
    hitKind: key,
  };

  const group = new THREE.Group();
  group.name = mesh.name;
  group.visible = visible;
  group.userData = mesh.userData;
  group.add(mesh);

  if (!wireframe) {
    const edgesGeometry = new THREE.EdgesGeometry(geometry, 28);
    const edgesMaterial = new THREE.LineBasicMaterial({
      color: colorForKind(object.kind, object.materialCategory),
      transparent: true,
      opacity: 0.55,
      depthWrite: false,
    });
    const edges = new THREE.LineSegments(edgesGeometry, edgesMaterial);
    edges.name = `${mesh.name}-edges`;
    edges.renderOrder = 10;
    edges.userData = mesh.userData;
    group.add(edges);
  }
  root.add(group);

  const invalidBounds = !Number.isFinite(object.bounds.min.x) || !Number.isFinite(object.bounds.min.y) || !Number.isFinite(object.bounds.min.z) ||
    !Number.isFinite(object.bounds.max.x) || !Number.isFinite(object.bounds.max.y) || !Number.isFinite(object.bounds.max.z) ||
    object.bounds.min.x > object.bounds.max.x ||
    object.bounds.min.y > object.bounds.max.y ||
    object.bounds.min.z > object.bounds.max.z;

  return {
    added: true,
    selectable: object.selectable !== false,
    vertexCount: object.mesh.positions.length,
    indexCount: object.mesh.indices.length,
    invalidBounds,
  };
}

export function buildRenderSceneGroup(renderScene: RenderScene, options?: { kindVisibility?: KindVisibility; wireframe?: boolean }): RenderSceneBuildResult {
  const root = new THREE.Group();
  root.name = "render-scene-root";
  const kindVisibility = options?.kindVisibility ?? {};
  const wireframe = Boolean(options?.wireframe);

  const kindCounts: Record<string, number> = {};
  const levelIds = new Set<number>();
  let selectableObjectCount = 0;
  let visibleObjectCount = 0;
  let vertexCount = 0;
  let indexCount = 0;
  let missingGeometryCount = 0;
  let invalidBoundsCount = 0;

  renderScene.objects.forEach((object, index) => {
    const key = filterKindKey(object.kind);
    kindCounts[key] = (kindCounts[key] ?? 0) + 1;
    if (typeof object.levelId === "number") {
      levelIds.add(object.levelId);
    }
    if (object.selectable !== false) {
      selectableObjectCount += 1;
    }
    if (object.visibleByDefault !== false && kindVisibility[key] !== false) {
      visibleObjectCount += 1;
    }
    const result = addGeometryObject(root, object, index, kindVisibility, wireframe);
    if (!result.added) {
      missingGeometryCount += 1;
      return;
    }
    vertexCount += result.vertexCount;
    indexCount += result.indexCount;
    if (result.invalidBounds) {
      invalidBoundsCount += 1;
    }
  });

  const bounds = new THREE.Box3().setFromObject(root);
  if (!bounds.isEmpty()) {
    const center = new THREE.Vector3();
    bounds.getCenter(center);
    const minY = bounds.min.y;
    root.position.x -= center.x;
    root.position.z -= center.z;
    if (minY < 0) {
      root.position.y -= minY;
    }
    bounds.setFromObject(root);
  }

  return {
    root,
    bounds,
    diagnostics: {
      source: renderScene.source,
      objectCount: renderScene.objectCount,
      selectableObjectCount,
      visibleObjectCount,
      vertexCount,
      indexCount,
      triangleCount: Math.floor(indexCount / 3),
      levelCount: levelIds.size,
      missingGeometryCount,
      invalidBoundsCount,
      kindCounts,
    },
  };
}

export function renderSceneSummaryLabel(renderScene: RenderScene | null, fallback = "render_scene.json") {
  if (!renderScene) {
    return fallback;
  }
  return `${renderScene.source} • objects ${renderScene.objectCount} • vertices ${renderScene.vertexCount} • indices ${renderScene.indexCount}`;
}
