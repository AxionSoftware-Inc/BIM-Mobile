"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";

type ObjViewerProps = {
  projectJson: JsonObject | null;
  objText: string | null;
  loadedAtLabel?: string | null;
  preset?: ViewPreset;
  interactive?: boolean;
  selectedElementId?: number | null;
  hoveredElementId?: number | null;
  onHover?: (info: {
    elementId: number | null;
    kind: string | null;
    hitKind: string | null;
    modelPoint: { x: number; y: number } | null;
  }) => void;
  onPick?: (info: {
    elementId: number | null;
    kind: string | null;
    hitKind: string | null;
    modelPoint: { x: number; y: number } | null;
  }) => void;
};

type JsonPrimitive = string | number | boolean | null;
type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
type JsonObject = { [key: string]: JsonValue };

type ParsedComponent = {
  geometry: THREE.BufferGeometry;
  faceCount: number;
  vertexCount: number;
  bounds: THREE.Box3;
  name: string;
};

type ParsedObj = {
  vertexCount: number;
  faceCount: number;
  bounds: THREE.Box3;
  objectCount: number;
  components: ParsedComponent[];
};

type OrientedObj = ParsedObj & {
  dimensions: {
    width: number;
    depth: number;
    height: number;
  };
};

type ViewPreset = "isometric" | "top" | "front";

type ProjectPoint = {
  x: number;
  y: number;
};

type ProjectWallOpening = {
  element_id?: number;
  id?: number;
  kind?: string;
  offset?: number;
  offset_meters?: number;
  width?: number;
  width_meters?: number;
  height?: number;
  height_meters?: number;
  sill_height?: number;
  sill_height_meters?: number;
};

type ProjectWallElement = {
  id?: number;
  kind?: string;
  name?: string;
  wall?: {
    axis?: {
      start?: ProjectPoint;
      end?: ProjectPoint;
    };
    thickness?: number;
    thickness_meters?: number;
    height?: number;
    height_meters?: number;
    openings?: ProjectWallOpening[];
  };
};

type ProjectRoomElement = {
  id?: number;
  kind?: string;
  room?: {
    centerline_boundary_polygon?: ProjectPoint[];
    interior_boundary_polygon?: ProjectPoint[];
    preferred_boundary_mode?: string;
  };
};

type ProjectScene = {
  root: THREE.Group;
  bounds: THREE.Box3;
  walls: number;
  openings: number;
  rooms: number;
};

const ORIENT_MATRIX = new THREE.Matrix4().set(
  1, 0, 0, 0,
  0, 0, 1, 0,
  0, 1, 0, 0,
  0, 0, 0, 1,
);

function parseObj(text: string): ParsedObj | null {
  const vertices: THREE.Vector3[] = [];
  const faces: number[][] = [];

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }

    const parts = line.split(/\s+/);
    if (parts[0] === "v" && parts.length >= 4) {
      const x = Number(parts[1]);
      const y = Number(parts[2]);
      const z = Number(parts[3]);
      if ([x, y, z].every(Number.isFinite)) {
        vertices.push(new THREE.Vector3(x, y, z));
      }
      continue;
    }

    if (parts[0] !== "f" || parts.length < 4) {
      continue;
    }

    const faceVertices = parts
      .slice(1)
      .map((token) => {
        const [vertexIndex] = token.split("/");
        const parsed = Number(vertexIndex);
        if (!Number.isFinite(parsed)) {
          return null;
        }
        return parsed < 0 ? vertices.length + parsed : parsed - 1;
      })
      .filter((value): value is number => value !== null && value >= 0 && value < vertices.length);

    if (faceVertices.length >= 3) {
      faces.push(faceVertices);
    }
  }

  if (vertices.length === 0 || faces.length === 0) {
    return null;
  }

  const vertexToFaces = new Map<number, number[]>();
  faces.forEach((face, faceIndex) => {
    for (const vertexIndex of face) {
      const list = vertexToFaces.get(vertexIndex);
      if (list) {
        list.push(faceIndex);
      } else {
        vertexToFaces.set(vertexIndex, [faceIndex]);
      }
    }
  });

  const parent = Array.from({ length: faces.length }, (_, index) => index);
  const find = (value: number) => {
    let current = value;
    while (parent[current] !== current) {
      parent[current] = parent[parent[current]];
      current = parent[current];
    }
    return current;
  };
  const union = (left: number, right: number) => {
    const rootLeft = find(left);
    const rootRight = find(right);
    if (rootLeft !== rootRight) {
      parent[rootRight] = rootLeft;
    }
  };

  vertexToFaces.forEach((faceIndices) => {
    if (faceIndices.length < 2) {
      return;
    }
    const first = faceIndices[0];
    for (let index = 1; index < faceIndices.length; index += 1) {
      union(first, faceIndices[index]);
    }
  });

  const groupedFaces = new Map<number, number[][]>();
  faces.forEach((face, faceIndex) => {
    const root = find(faceIndex);
    const list = groupedFaces.get(root);
    if (list) {
      list.push(face);
    } else {
      groupedFaces.set(root, [face]);
    }
  });

  const buildComponent = (componentFaces: number[][], name: string): ParsedComponent => {
    const usedVertices = new Map<number, number>();
    const componentVertices: THREE.Vector3[] = [];
    const indices: number[] = [];

    for (const face of componentFaces) {
      const remapped = face.map((index) => {
        if (!usedVertices.has(index)) {
          usedVertices.set(index, componentVertices.length);
          componentVertices.push(vertices[index]);
        }
        return usedVertices.get(index) ?? 0;
      });

      for (let index = 1; index < remapped.length - 1; index += 1) {
        indices.push(remapped[0], remapped[index], remapped[index + 1]);
      }
    }

    const positions = new Float32Array(componentVertices.length * 3);
    componentVertices.forEach((vertex, index) => {
      positions[index * 3] = vertex.x;
      positions[index * 3 + 1] = vertex.y;
      positions[index * 3 + 2] = vertex.z;
    });

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
    geometry.setIndex(indices);
    geometry.computeVertexNormals();
    geometry.computeBoundingBox();

    return {
      geometry,
      faceCount: indices.length / 3,
      vertexCount: componentVertices.length,
      bounds: geometry.boundingBox?.clone() ?? new THREE.Box3(),
      name,
    };
  };

  const components = [...groupedFaces.values()]
    .map((componentFaces, index) => buildComponent(componentFaces, `component-${index + 1}`))
    .sort((left, right) => left.name.localeCompare(right.name));

  const positions = new Float32Array(vertices.length * 3);
  vertices.forEach((vertex, index) => {
    positions[index * 3] = vertex.x;
    positions[index * 3 + 1] = vertex.y;
    positions[index * 3 + 2] = vertex.z;
  });

  return {
    vertexCount: vertices.length,
    faceCount: faces.reduce((count, face) => count + Math.max(face.length - 2, 0), 0),
    bounds: new THREE.Box3().setFromArray(Array.from(positions)),
    objectCount: components.length,
    components,
  };
}

function projectElements(projectJson: JsonObject | null) {
  const document = projectJson && typeof projectJson === "object" ? (projectJson.document as JsonObject | null) : null;
  return document && Array.isArray(document.elements) ? (document.elements as JsonObject[]) : [];
}

function wallAxisFromProject(wall: ProjectWallElement["wall"] | null | undefined) {
  const start = wall?.axis?.start;
  const end = wall?.axis?.end;
  const startX = Number(start?.x);
  const startY = Number(start?.y);
  const endX = Number(end?.x);
  const endY = Number(end?.y);
  if (![startX, startY, endX, endY].every(Number.isFinite)) {
    return null;
  }
  return {
    start: { x: startX, y: startY },
    end: { x: endX, y: endY },
  };
}

function buildPolygonShape(points: ProjectPoint[]) {
  if (points.length < 3) {
    return null;
  }
  const shape = new THREE.Shape();
  const first = points[0];
  shape.moveTo(first.x, -first.y);
  for (const point of points.slice(1)) {
    shape.lineTo(point.x, -point.y);
  }
  shape.closePath();
  return shape;
}

function createRoomMesh(room: ProjectRoomElement, index: number) {
  const polygon = room.room?.interior_boundary_polygon ?? room.room?.centerline_boundary_polygon ?? [];
  const shape = buildPolygonShape(polygon);
  if (!shape) {
    return null;
  }
  const geometry = new THREE.ShapeGeometry(shape);
  geometry.rotateX(-Math.PI / 2);
  geometry.computeVertexNormals();
  const material = new THREE.MeshStandardMaterial({
    color: index % 2 === 0 ? 0xa7f3d0 : 0xbfdbfe,
    transparent: true,
    opacity: 0.16,
    side: THREE.DoubleSide,
    roughness: 1,
    metalness: 0,
    depthWrite: false,
  });
  const mesh = new THREE.Mesh(geometry, material);
  mesh.name = `room-${room.id ?? index + 1}`;
  mesh.userData = {
    elementId: room.id ?? null,
    kind: "Room",
    hitKind: "room_interior",
  };
  mesh.position.y = 0.01;
  return mesh;
}

function createWallPlanGroup(wall: ProjectWallElement, index: number) {
  const axis = wallAxisFromProject(wall.wall);
  if (!axis) {
    return null;
  }

  const start = new THREE.Vector3(axis.start.x, 0, -axis.start.y);
  const end = new THREE.Vector3(axis.end.x, 0, -axis.end.y);
  const wallVector = new THREE.Vector3().subVectors(end, start);
  const wallLengthMeters = wallVector.length();
  if (wallLengthMeters <= 1e-6) {
    return null;
  }

  const wallThicknessMeters = Math.max(0.03, Number(wall.wall?.thickness_meters ?? wall.wall?.thickness ?? 0.2));
  const wallMidpoint = new THREE.Vector3().addVectors(start, end).multiplyScalar(0.5);
  const angle = Math.atan2(wallVector.z, wallVector.x);

  const group = new THREE.Group();
  group.name = `wall-plan-${wall.id ?? index + 1}`;
  group.userData = {
    elementId: wall.id ?? null,
    kind: "Wall",
    hitKind: "wall_body",
  };
  group.position.copy(new THREE.Vector3(wallMidpoint.x, 0, wallMidpoint.z));
  group.rotation.y = angle;

  const wallMaterial = new THREE.MeshStandardMaterial({
    color: index % 2 === 0 ? 0x334155 : 0x475569,
    roughness: 0.95,
    metalness: 0,
    side: THREE.DoubleSide,
    transparent: true,
    opacity: 0.88,
  });

  const wallBody = new THREE.Mesh(new THREE.BoxGeometry(wallLengthMeters, 0.22, wallThicknessMeters), wallMaterial);
  wallBody.position.y = 0.11;
  wallBody.userData = {
    elementId: wall.id ?? null,
    kind: "Wall",
    hitKind: "wall_body",
  };
  group.add(wallBody);

  const openings = Array.isArray(wall.wall?.openings) ? [...wall.wall.openings] : [];
  openings.sort((left, right) => {
    const leftOffset = Number(left.offset_meters ?? left.offset ?? 0);
    const rightOffset = Number(right.offset_meters ?? right.offset ?? 0);
    return leftOffset - rightOffset;
  });

  for (const opening of openings) {
    const offset = Number(opening.offset_meters ?? opening.offset ?? NaN);
    const width = Number(opening.width_meters ?? opening.width ?? NaN);
    const height = Number(opening.height_meters ?? opening.height ?? NaN);
    if (![offset, width, height].every(Number.isFinite) || width <= 0 || height <= 0) {
      continue;
    }

    const openingGroup = new THREE.Group();
    const openingMaterial = new THREE.MeshStandardMaterial({
      color: String(opening.kind ?? "").toLowerCase() === "window" ? 0x60a5fa : 0xc084fc,
      roughness: 0.42,
      metalness: 0.02,
      transparent: true,
      opacity: 0.92,
      side: THREE.DoubleSide,
    });
    const openingMesh = new THREE.Mesh(new THREE.BoxGeometry(width, 0.28, Math.max(0.04, wallThicknessMeters * 0.9)), openingMaterial);
    openingMesh.position.set(offset - wallLengthMeters / 2, 0.18, 0);
    openingMesh.userData = {
      elementId: opening.element_id ?? opening.id ?? null,
      kind: String(opening.kind ?? "").toLowerCase() === "window" ? "Window" : "Door",
      hitKind: "opening",
    };
    openingGroup.userData = openingMesh.userData;
    openingGroup.add(openingMesh);
    group.add(openingGroup);
  }

  const label = new THREE.Mesh(
    new THREE.BoxGeometry(Math.min(0.2, wallLengthMeters * 0.1), 0.05, Math.min(0.04, wallThicknessMeters * 0.35)),
    new THREE.MeshBasicMaterial({ color: 0xf59e0b, transparent: true, opacity: 0.45 }),
  );
  label.position.set(0, 0.3, 0);
  group.add(label);

  return group;
}

function createWallGroup(wall: ProjectWallElement, index: number) {
  const axis = wallAxisFromProject(wall.wall);
  if (!axis) {
    return null;
  }

  const start = new THREE.Vector3(axis.start.x, 0, -axis.start.y);
  const end = new THREE.Vector3(axis.end.x, 0, -axis.end.y);
  const wallVector = new THREE.Vector3().subVectors(end, start);
  const wallLengthMeters = wallVector.length();
  if (wallLengthMeters <= 1e-6) {
    return null;
  }

  const wallHeightMeters = Math.max(0.1, Number(wall.wall?.height_meters ?? wall.wall?.height ?? 3));
  const wallThicknessMeters = Math.max(0.03, Number(wall.wall?.thickness_meters ?? wall.wall?.thickness ?? 0.2));
  const wallMidpoint = new THREE.Vector3().addVectors(start, end).multiplyScalar(0.5);
  const angle = Math.atan2(wallVector.z, wallVector.x);

  const group = new THREE.Group();
  group.name = `wall-${wall.id ?? index + 1}`;
  group.userData = {
    elementId: wall.id ?? null,
    kind: "Wall",
    hitKind: "wall_body",
  };
  group.position.copy(new THREE.Vector3(wallMidpoint.x, 0, wallMidpoint.z));
  group.rotation.y = angle;

  const openings = Array.isArray(wall.wall?.openings) ? [...wall.wall.openings] : [];
  openings.sort((left, right) => {
    const leftOffset = Number(left.offset_meters ?? left.offset ?? 0);
    const rightOffset = Number(right.offset_meters ?? right.offset ?? 0);
    return leftOffset - rightOffset;
  });

  const wallMaterial = new THREE.MeshStandardMaterial({
    color: index % 2 === 0 ? 0x334155 : 0x475569,
    roughness: 0.94,
    metalness: 0.0,
    side: THREE.DoubleSide,
    transparent: true,
    opacity: 0.84,
  });
  const segmentMaterial = wallMaterial.clone();

  const wallChildren: THREE.Object3D[] = [];
  const openingMeshes: THREE.Object3D[] = [];
  let cursor = 0;
  for (const opening of openings) {
    const offset = Number(opening.offset_meters ?? opening.offset ?? NaN);
    const width = Number(opening.width_meters ?? opening.width ?? NaN);
    const height = Number(opening.height_meters ?? opening.height ?? NaN);
    const sillHeight = Number(opening.sill_height_meters ?? opening.sill_height ?? 0);
    if (![offset, width, height].every(Number.isFinite) || width <= 0 || height <= 0) {
      continue;
    }
    const leftWidth = Math.max(0, offset - width / 2 - cursor);
    if (leftWidth > 0.02) {
      const leftGeometry = new THREE.BoxGeometry(leftWidth, wallHeightMeters, wallThicknessMeters);
      const leftMesh = new THREE.Mesh(leftGeometry, segmentMaterial.clone());
      leftMesh.position.set(cursor + leftWidth / 2 - wallLengthMeters / 2, wallHeightMeters / 2, 0);
      leftMesh.userData = { elementId: wall.id ?? null, kind: "Wall", hitKind: "wall_body" };
      wallChildren.push(leftMesh);
    }

    const openingCenterX = offset - wallLengthMeters / 2;
    if (sillHeight > 0.02) {
      const sillGeometry = new THREE.BoxGeometry(width, sillHeight, wallThicknessMeters);
      const sillMesh = new THREE.Mesh(sillGeometry, segmentMaterial.clone());
      sillMesh.position.set(openingCenterX, sillHeight / 2, 0);
      sillMesh.userData = { elementId: wall.id ?? null, kind: "Wall", hitKind: "wall_body" };
      wallChildren.push(sillMesh);
    }
    const lintelHeight = Math.max(0, wallHeightMeters - sillHeight - height);
    if (lintelHeight > 0.02) {
      const lintelGeometry = new THREE.BoxGeometry(width, lintelHeight, wallThicknessMeters);
      const lintelMesh = new THREE.Mesh(lintelGeometry, segmentMaterial.clone());
      lintelMesh.position.set(openingCenterX, sillHeight + height + lintelHeight / 2, 0);
      lintelMesh.userData = { elementId: wall.id ?? null, kind: "Wall", hitKind: "wall_body" };
      wallChildren.push(lintelMesh);
    }

    const openingGroup = new THREE.Group();
    const openingShape = new THREE.BoxGeometry(width * 0.92, Math.max(0.1, height * 0.96), Math.max(0.03, wallThicknessMeters * 0.55));
    const openingMaterial = new THREE.MeshStandardMaterial({
      color: String(opening.kind ?? "").toLowerCase() === "window" ? 0x60a5fa : 0xc084fc,
      roughness: 0.35,
      metalness: 0.04,
      transparent: true,
      opacity: 0.72,
      side: THREE.DoubleSide,
    });
  const openingMesh = new THREE.Mesh(openingShape, openingMaterial);
  openingMesh.position.set(openingCenterX, sillHeight + height / 2, 0);
  openingMesh.userData = {
    elementId: opening.element_id ?? opening.id ?? null,
    kind: String(opening.kind ?? "").toLowerCase() === "window" ? "Window" : "Door",
    hitKind: "opening",
  };
  openingGroup.add(openingMesh);
  openingGroup.userData = {
    elementId: opening.element_id ?? opening.id ?? null,
    kind: String(opening.kind ?? "").toLowerCase() === "window" ? "Window" : "Door",
    hitKind: "opening",
  };
  openingMeshes.push(openingGroup);

    cursor = Math.max(cursor, offset + width / 2);
  }

  const rightWidth = Math.max(0, wallLengthMeters - cursor);
  if (rightWidth > 0.02) {
    const rightGeometry = new THREE.BoxGeometry(rightWidth, wallHeightMeters, wallThicknessMeters);
    const rightMesh = new THREE.Mesh(rightGeometry, wallMaterial.clone());
    rightMesh.position.set(cursor + rightWidth / 2 - wallLengthMeters / 2, wallHeightMeters / 2, 0);
    rightMesh.userData = { elementId: wall.id ?? null, kind: "Wall", hitKind: "wall_body" };
    wallChildren.push(rightMesh);
  }

  if (wallChildren.length === 0) {
    const fullWall = new THREE.Mesh(new THREE.BoxGeometry(wallLengthMeters, wallHeightMeters, wallThicknessMeters), wallMaterial.clone());
    fullWall.position.set(0, wallHeightMeters / 2, 0);
    fullWall.userData = { elementId: wall.id ?? null, kind: "Wall", hitKind: "wall_body" };
    wallChildren.push(fullWall);
  }

  for (const child of wallChildren) {
    group.add(child);
  }
  for (const openingGroup of openingMeshes) {
    group.add(openingGroup);
  }

  const labelGeometry = new THREE.BoxGeometry(Math.min(0.2, wallLengthMeters * 0.1), Math.min(0.2, wallHeightMeters * 0.08), Math.min(0.02, wallThicknessMeters * 0.1));
  const labelMesh = new THREE.Mesh(
    labelGeometry,
    new THREE.MeshBasicMaterial({ color: 0xf59e0b, transparent: true, opacity: 0.3 }),
  );
  labelMesh.position.set(0, wallHeightMeters + 0.15, 0);
  group.add(labelMesh);

  return group;
}

function buildProjectScene(projectJson: JsonObject | null): ProjectScene | null {
  if (!projectJson) {
    return null;
  }
  const elements = projectElements(projectJson);
  if (elements.length === 0) {
    return null;
  }

  const root = new THREE.Group();
  root.name = "project-scene-root";
  let wallCount = 0;
  let openingCount = 0;
  let roomCount = 0;

  elements.forEach((element, index) => {
    if (element.kind === "Room") {
      const roomMesh = createRoomMesh(element as ProjectRoomElement, index);
      if (roomMesh) {
        root.add(roomMesh);
        roomCount += 1;
      }
    }
  });

  elements.forEach((element, index) => {
    if (element.kind !== "Wall") {
      return;
    }
    const wallGroup = createWallGroup(element as ProjectWallElement, index);
    if (wallGroup) {
      root.add(wallGroup);
      wallCount += 1;
      openingCount += Array.isArray((element as ProjectWallElement).wall?.openings) ? (element as ProjectWallElement).wall!.openings!.filter((opening) => {
        const width = Number(opening.width_meters ?? opening.width ?? NaN);
        const height = Number(opening.height_meters ?? opening.height ?? NaN);
        return Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0;
      }).length : 0;
    }
  });

  const bounds = new THREE.Box3().setFromObject(root);
  if (!bounds.isEmpty()) {
    const minY = bounds.min.y;
    if (minY < 0) {
      root.position.y += -minY;
      bounds.translate(new THREE.Vector3(0, -minY, 0));
    }
  }

  return {
    root,
    bounds,
    walls: wallCount,
    openings: openingCount,
    rooms: roomCount,
  };
}

function buildProjectPlanScene(projectJson: JsonObject | null): ProjectScene | null {
  if (!projectJson) {
    return null;
  }
  const elements = projectElements(projectJson);
  if (elements.length === 0) {
    return null;
  }

  const root = new THREE.Group();
  root.name = "project-plan-root";
  let wallCount = 0;
  let openingCount = 0;
  let roomCount = 0;

  elements.forEach((element, index) => {
    if (element.kind === "Room") {
      const roomMesh = createRoomMesh(element as ProjectRoomElement, index);
      if (roomMesh) {
        root.add(roomMesh);
        roomCount += 1;
      }
    }
  });

  elements.forEach((element, index) => {
    if (element.kind !== "Wall") {
      return;
    }
    const wallGroup = createWallPlanGroup(element as ProjectWallElement, index);
    if (wallGroup) {
      root.add(wallGroup);
      wallCount += 1;
      openingCount += Array.isArray((element as ProjectWallElement).wall?.openings)
        ? (element as ProjectWallElement).wall!.openings!.filter((opening) => {
            const width = Number(opening.width_meters ?? opening.width ?? NaN);
            const height = Number(opening.height_meters ?? opening.height ?? NaN);
            return Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0;
          }).length
        : 0;
    }
  });

  const bounds = new THREE.Box3().setFromObject(root);
  if (!bounds.isEmpty()) {
    const minY = bounds.min.y;
    if (minY < 0) {
      root.position.y += -minY;
      bounds.translate(new THREE.Vector3(0, -minY, 0));
    }
  }

  return {
    root,
    bounds,
    walls: wallCount,
    openings: openingCount,
    rooms: roomCount,
  };
}

function orientGeometry(parsed: ParsedObj): OrientedObj {
  const orientedComponents = parsed.components.map((component) => {
    const geometry = component.geometry.clone();
    geometry.applyMatrix4(ORIENT_MATRIX);
    geometry.computeVertexNormals();
    geometry.computeBoundingBox();
    return {
      ...component,
      geometry,
      bounds: geometry.boundingBox?.clone() ?? new THREE.Box3(),
    };
  });

  const combinedBounds = orientedComponents.reduce(
    (accumulator, component) => accumulator.union(component.bounds),
    new THREE.Box3(),
  );

  const center = new THREE.Vector3();
  combinedBounds.getCenter(center);

  orientedComponents.forEach((component) => {
    component.geometry.translate(-center.x, -combinedBounds.min.y, -center.z);
    component.geometry.computeVertexNormals();
    component.geometry.computeBoundingBox();
    component.bounds = component.geometry.boundingBox?.clone() ?? new THREE.Box3();
  });

  const fittedBounds = orientedComponents.reduce(
    (accumulator, component) => accumulator.union(component.bounds),
    new THREE.Box3(),
  );
  const fittedSize = new THREE.Vector3();
  fittedBounds.getSize(fittedSize);

  return {
    ...parsed,
    components: orientedComponents,
    bounds: fittedBounds,
    dimensions: {
      width: fittedSize.x,
      depth: fittedSize.z,
      height: fittedSize.y,
    },
  };
}

function fitCameraToBounds(
  camera: THREE.PerspectiveCamera | THREE.OrthographicCamera,
  controls: OrbitControls,
  bounds: THREE.Box3,
  preset: ViewPreset = "isometric",
) {
  const size = new THREE.Vector3();
  const center = new THREE.Vector3();
  bounds.getSize(size);
  bounds.getCenter(center);
  const maxDim = Math.max(size.x, size.y, size.z, 1);
  const distance = maxDim * 1.75;

  switch (preset) {
    case "top":
      if (camera instanceof THREE.OrthographicCamera) {
        const margin = maxDim * 0.65;
        camera.left = -size.x / 2 - margin;
        camera.right = size.x / 2 + margin;
        camera.top = size.z / 2 + margin;
        camera.bottom = -size.z / 2 - margin;
        camera.near = -maxDim * 20;
        camera.far = maxDim * 20;
        camera.zoom = Math.max(0.45, 1 / Math.max(size.x / 180, size.z / 180, 1));
        camera.position.set(center.x, center.y + distance * 2.0, center.z + 0.001);
        camera.up.set(0, 0, 1);
        camera.updateProjectionMatrix();
      } else {
        camera.near = Math.max(0.1, maxDim / 100);
        camera.far = Math.max(2000, maxDim * 20);
        camera.position.set(center.x, center.y + distance * 2.4, center.z + 0.001);
        camera.updateProjectionMatrix();
      }
      controls.target.set(center.x, center.y, center.z);
      break;
    case "front":
      if (camera instanceof THREE.OrthographicCamera) {
        const margin = maxDim * 0.5;
        camera.left = -size.x / 2 - margin;
        camera.right = size.x / 2 + margin;
        camera.top = size.y / 2 + margin;
        camera.bottom = -size.y / 2 - margin;
        camera.near = -maxDim * 20;
        camera.far = maxDim * 20;
        camera.zoom = Math.max(0.45, 1 / Math.max(size.x / 180, size.y / 180, 1));
        camera.position.set(center.x + distance * 0.1, center.y + distance * 0.4, center.z + distance * 2.15);
        camera.up.set(0, 1, 0);
        camera.updateProjectionMatrix();
      } else {
        camera.near = Math.max(0.1, maxDim / 100);
        camera.far = Math.max(2000, maxDim * 20);
        camera.position.set(center.x + distance * 0.1, center.y + distance * 0.4, center.z + distance * 2.15);
        camera.updateProjectionMatrix();
      }
      camera.position.set(center.x + distance * 0.1, center.y + distance * 0.4, center.z + distance * 2.15);
      controls.target.set(center.x, center.y, center.z);
      break;
    case "isometric":
    default:
      if (camera instanceof THREE.OrthographicCamera) {
        const margin = maxDim * 0.8;
        camera.left = -size.x / 2 - margin;
        camera.right = size.x / 2 + margin;
        camera.top = size.y / 2 + margin;
        camera.bottom = -size.y / 2 - margin;
        camera.near = -maxDim * 20;
        camera.far = maxDim * 20;
        camera.zoom = Math.max(0.4, 1 / Math.max(size.x / 160, size.y / 160, size.z / 160, 1));
        camera.position.set(center.x + distance * 1.2, center.y + distance * 1.1, center.z + distance * 1.2);
        camera.up.set(0, 1, 0);
        camera.updateProjectionMatrix();
      } else {
        camera.near = Math.max(0.1, maxDim / 100);
        camera.far = Math.max(2000, maxDim * 20);
        camera.position.set(center.x + distance * 1.2, center.y + distance * 1.1, center.z + distance * 1.2);
        camera.updateProjectionMatrix();
      }
      controls.target.set(center.x, center.y, center.z);
      break;
  }

  controls.update();
}

function colorForComponent(index: number) {
  const palette = [0x475569, 0x2563eb, 0x0f766e, 0x7c3aed, 0x0f172a, 0x14b8a6];
  return palette[index % palette.length];
}

function disposeObject3D(object: THREE.Object3D) {
  object.traverse((child) => {
    const mesh = child as THREE.Mesh;
    const hasGeometry = "geometry" in mesh && mesh.geometry instanceof THREE.BufferGeometry;
    if (hasGeometry) {
      mesh.geometry.dispose();
    }

    const material = (mesh as THREE.Mesh & { material?: THREE.Material | THREE.Material[] }).material;
    if (Array.isArray(material)) {
      material.forEach((item) => item.dispose());
    } else if (material) {
      material.dispose();
    }
  });
}

function cloneObject3DWithGeometry(object: THREE.Object3D) {
  const clone = object.clone(true) as THREE.Group;
  clone.traverse((child) => {
    const mesh = child as THREE.Mesh;
    if (mesh.geometry instanceof THREE.BufferGeometry) {
      mesh.geometry = mesh.geometry.clone();
    }
    const material = (mesh as THREE.Mesh & { material?: THREE.Material | THREE.Material[] }).material;
    if (Array.isArray(material)) {
      mesh.material = material.map((item) => item.clone());
    } else if (material) {
      mesh.material = material.clone();
    }
  });
  return clone;
}

function applyWireframeToObject(object: THREE.Object3D, enabled: boolean) {
  object.traverse((child) => {
    const mesh = child as THREE.Mesh;
    const material = (mesh as THREE.Mesh & { material?: THREE.Material | THREE.Material[] }).material;
    const materials = Array.isArray(material) ? material : material ? [material] : [];
    for (const item of materials) {
      if ("wireframe" in item) {
        (item as THREE.MeshStandardMaterial).wireframe = enabled;
      }
      if ("opacity" in item) {
        const nextOpacity = enabled ? 1 : typeof (item as THREE.Material & { opacity?: number }).opacity === "number" ? (item as THREE.Material & { opacity?: number }).opacity : 1;
        if ("transparent" in item) {
          (item as THREE.Material & { transparent?: boolean }).transparent = enabled ? false : Boolean((item as THREE.Material & { transparent?: boolean }).transparent);
        }
        if (!enabled && "opacity" in item) {
          const opacity = (item as THREE.Material & { opacity?: number }).opacity;
          if (typeof opacity === "number") {
            (item as THREE.Material & { opacity?: number }).opacity = opacity;
          }
        }
        if (enabled && "opacity" in item) {
          (item as THREE.Material & { opacity?: number }).opacity = 1;
        } else if (!enabled && typeof nextOpacity === "number" && nextOpacity > 0) {
          (item as THREE.Material & { opacity?: number }).opacity = nextOpacity;
        }
      }
      item.needsUpdate = true;
    }
  });
}

function applyElementHighlights(root: THREE.Object3D | null, selectedElementId: number | null, hoveredElementId: number | null) {
  if (!root) {
    return;
  }
  root.traverse((child) => {
    const mesh = child as THREE.Mesh & { userData?: { elementId?: number | null } };
    const material = (mesh as THREE.Mesh & { material?: THREE.Material | THREE.Material[] }).material;
    const materials = Array.isArray(material) ? material : material ? [material] : [];
    const elementId = typeof mesh.userData?.elementId === "number" ? mesh.userData.elementId : null;
    const selected = elementId !== null && selectedElementId !== null && elementId === selectedElementId;
    const hovered = elementId !== null && hoveredElementId !== null && elementId === hoveredElementId;
    for (const item of materials) {
      if ("emissive" in item) {
        const emissive = item as THREE.MeshStandardMaterial & { emissive: THREE.Color };
        emissive.emissive.set(selected ? "#16a34a" : hovered ? "#0ea5e9" : "#000000");
        emissive.emissiveIntensity = selected ? 0.28 : hovered ? 0.18 : 0;
      }
      if ("opacity" in item && "transparent" in item) {
        (item as THREE.Material & { opacity?: number; transparent?: boolean }).opacity = selected ? 0.98 : hovered ? 0.92 : (item as THREE.Material & { opacity?: number }).opacity ?? 1;
      }
      item.needsUpdate = true;
    }
  });
}

export default function ObjViewer({
  projectJson,
  objText,
  loadedAtLabel,
  preset = "isometric",
  interactive = false,
  selectedElementId = null,
  hoveredElementId = null,
  onHover,
  onPick,
}: ObjViewerProps) {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null);
  const sceneRef = useRef<THREE.Scene | null>(null);
  const cameraRef = useRef<THREE.PerspectiveCamera | THREE.OrthographicCamera | null>(null);
  const controlsRef = useRef<OrbitControls | null>(null);
  const modelGroupRef = useRef<THREE.Group | null>(null);
  const gridRef = useRef<THREE.GridHelper | null>(null);
  const axesRef = useRef<THREE.AxesHelper | null>(null);
  const frameRef = useRef<number | null>(null);
  const [wireframe, setWireframe] = useState(false);
  const [showGrid, setShowGrid] = useState(true);
  const [showAxes, setShowAxes] = useState(true);
  const [viewPreset, setViewPreset] = useState<ViewPreset>(preset);
  const parsed = useMemo(() => (objText ? parseObj(objText) : null), [objText]);
  const oriented = useMemo(() => (parsed ? orientGeometry(parsed) : null), [parsed]);
  const projectScene = useMemo(() => buildProjectScene(projectJson), [projectJson]);
  const projectPlanScene = useMemo(() => buildProjectPlanScene(projectJson), [projectJson]);
  const activeProjectScene = viewPreset === "top" ? projectPlanScene : projectScene;
  const sceneMode: "project" | "obj" = activeProjectScene ? "project" : "obj";
  const activeBounds = useMemo(
    () => activeProjectScene?.bounds ?? oriented?.bounds ?? new THREE.Box3(),
    [activeProjectScene?.bounds, oriented?.bounds],
  );
  const activeDimensions = useMemo(() => {
    const bounds = activeBounds;
    if (bounds.isEmpty()) {
      return null;
    }
    const size = new THREE.Vector3();
    bounds.getSize(size);
    return {
      width: size.x,
      depth: size.z,
      height: size.y,
    };
  }, [activeBounds]);

  const status = sceneMode === "project"
    ? `${viewPreset === "top" ? "Top plan scene" : "Project scene"} • walls ${activeProjectScene?.walls ?? 0} • openings ${activeProjectScene?.openings ?? 0} • rooms ${activeProjectScene?.rooms ?? 0}`
    : !objText
      ? "No geometry loaded"
      : oriented
        ? `OBJ vertices ${oriented.vertexCount} • faces ${oriented.faceCount}`
        : "OBJ could not be parsed";
  const dimensions = activeDimensions
    ? `W ${activeDimensions.width.toFixed(1)} • D ${activeDimensions.depth.toFixed(1)} • H ${activeDimensions.height.toFixed(1)}`
    : null;
  const loadedSource = sceneMode === "project" ? "project.json" : "/sample/walls.obj";

  useEffect(() => {
    const host = hostRef.current;
    if (!host) {
      return;
    }

    const scene = new THREE.Scene();
    scene.background = new THREE.Color("#eef2f0");
    scene.fog = new THREE.Fog("#eef2f0", 120, 1000);
    sceneRef.current = scene;

    const camera = preset === "top"
      ? new THREE.OrthographicCamera(-100, 100, 100, -100, -5000, 5000)
      : new THREE.PerspectiveCamera(45, 1, 0.1, 5000);
    camera.position.set(140, preset === "top" ? 260 : 120, 160);
    cameraRef.current = camera;

    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    renderer.setClearColor("#eef2f0");
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.shadowMap.enabled = false;
    rendererRef.current = renderer;
    host.appendChild(renderer.domElement);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.08;
    controls.enableRotate = preset !== "top";
    controls.screenSpacePanning = true;
    controls.target.set(0, 0, 0);
    controlsRef.current = controls;

    const ambient = new THREE.AmbientLight(0xffffff, 1.35);
    scene.add(ambient);
    const light1 = new THREE.DirectionalLight(0xffffff, 1.05);
    light1.position.set(140, 220, 180);
    scene.add(light1);
    const light2 = new THREE.DirectionalLight(0xcbd5e1, 0.5);
    light2.position.set(-120, 120, -150);
    scene.add(light2);

    const grid = new THREE.GridHelper(400, 40, 0x94a3b8, 0xdbe4de);
    grid.position.y = 0;
    gridRef.current = grid;
    scene.add(grid);

    const axes = new THREE.AxesHelper(80);
    axesRef.current = axes;
    scene.add(axes);

    const resize = () => {
      const width = host.clientWidth || 1;
      const height = host.clientHeight || 1;
      renderer.setSize(width, height, false);
      if (camera instanceof THREE.PerspectiveCamera) {
        camera.aspect = width / height;
      } else {
        const aspect = width / height;
        const frustumWidth = camera.right - camera.left;
        const frustumHeight = camera.top - camera.bottom;
        if (frustumWidth / frustumHeight < aspect) {
          const centerX = (camera.left + camera.right) / 2;
          const halfWidth = (frustumHeight * aspect) / 2;
          camera.left = centerX - halfWidth;
          camera.right = centerX + halfWidth;
        } else {
          const centerY = (camera.top + camera.bottom) / 2;
          const halfHeight = (frustumWidth / aspect) / 2;
          camera.top = centerY + halfHeight;
          camera.bottom = centerY - halfHeight;
        }
      }
      camera.updateProjectionMatrix();
    };

    const observer = new ResizeObserver(resize);
    observer.observe(host);
    resize();

    const animate = () => {
      frameRef.current = window.requestAnimationFrame(animate);
      controls.update();
      renderer.render(scene, camera);
    };
    animate();

    return () => {
      observer.disconnect();
      if (frameRef.current !== null) {
        window.cancelAnimationFrame(frameRef.current);
      }
      controls.dispose();
      renderer.dispose();
      renderer.domElement.remove();
      scene.clear();
      sceneRef.current = null;
      cameraRef.current = null;
      controlsRef.current = null;
      rendererRef.current = null;
      modelGroupRef.current = null;
      gridRef.current = null;
      axesRef.current = null;
    };
  }, [objText, preset]);

  useEffect(() => {
    if (gridRef.current) {
      gridRef.current.visible = showGrid;
    }
  }, [showGrid]);

  useEffect(() => {
    if (axesRef.current) {
      axesRef.current.visible = showAxes;
    }
  }, [showAxes]);

  useEffect(() => {
    const scene = sceneRef.current;
    const camera = cameraRef.current;
    const controls = controlsRef.current;
    if (!scene || !camera || !controls) {
      return;
    }

    if (modelGroupRef.current) {
      scene.remove(modelGroupRef.current);
      disposeObject3D(modelGroupRef.current);
      modelGroupRef.current = null;
    }

    const sourceGroup = activeProjectScene?.root ?? null;
    const sourceBounds = activeProjectScene?.bounds ?? oriented?.bounds ?? null;
    if (sourceGroup && sourceBounds) {
      const group = cloneObject3DWithGeometry(sourceGroup);
      applyWireframeToObject(group, wireframe);
      modelGroupRef.current = group;
      scene.add(group);
      fitCameraToBounds(camera, controls, sourceBounds, viewPreset);
      return;
    }

    if (!oriented) {
      return;
    }

    const group = new THREE.Group();
    group.name = "walls-obj-root";

    oriented.components.forEach((component, index) => {
      const color = colorForComponent(index);
      const mesh = new THREE.Mesh(
        component.geometry.clone(),
        new THREE.MeshStandardMaterial({
          color,
          roughness: 0.96,
          metalness: 0.0,
          wireframe,
          side: THREE.DoubleSide,
          transparent: true,
          opacity: wireframe ? 1 : 0.28,
          depthWrite: false,
          polygonOffset: true,
          polygonOffsetFactor: 1,
          polygonOffsetUnits: 1,
          flatShading: true,
        }),
      );
      mesh.name = component.name;
      mesh.renderOrder = index * 2;
      group.add(mesh);

      if (!wireframe) {
        const edges = new THREE.LineSegments(
          new THREE.EdgesGeometry(component.geometry.clone(), 18),
          new THREE.LineBasicMaterial({
            color: 0x0f172a,
            transparent: true,
            opacity: 0.72,
            depthWrite: false,
          }),
        );
        edges.name = `${component.name}-edges`;
        edges.renderOrder = index * 2 + 1;
        group.add(edges);
      }
    });

    modelGroupRef.current = group;
    scene.add(group);
    fitCameraToBounds(camera, controls, oriented.bounds, viewPreset);
  }, [activeProjectScene, oriented, viewPreset, wireframe]);

  useEffect(() => {
    applyElementHighlights(modelGroupRef.current, selectedElementId, hoveredElementId);
  }, [hoveredElementId, selectedElementId, projectScene, oriented]);

  useEffect(() => {
    const host = hostRef.current;
    const scene = sceneRef.current;
    const camera = cameraRef.current;
    if (!interactive || !host || !scene || !camera || (!onPick && !onHover)) {
      return;
    }

    const raycaster = new THREE.Raycaster();
    const pointer = new THREE.Vector2();
    const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    const planeHit = new THREE.Vector3();
    let lastHoverId: number | null = null;
    let hoverFrame: number | null = null;

    const extract = (object: THREE.Object3D | null) => {
      let current: THREE.Object3D | null = object;
      while (current) {
        const data = current.userData as { elementId?: number | null; kind?: string | null; hitKind?: string | null } | undefined;
        if (data && typeof data.elementId === "number") {
          return {
            elementId: data.elementId,
            kind: data.kind ?? null,
            hitKind: data.hitKind ?? null,
          };
        }
        current = current.parent;
      }
      return null;
    };

    const emitHover = (event: PointerEvent) => {
      const rect = host.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) {
        return;
      }
      pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
      pointer.y = -(((event.clientY - rect.top) / rect.height) * 2 - 1);
      raycaster.setFromCamera(pointer, camera);
      const hits = modelGroupRef.current ? raycaster.intersectObject(modelGroupRef.current, true) : [];
      const hit = hits.find((candidate) => candidate.object.visible !== false) ?? null;
      const targetData = extract(hit?.object ?? null);
      const nextHoverId = targetData?.elementId ?? null;
      if (nextHoverId === lastHoverId) {
        return;
      }
      lastHoverId = nextHoverId;
      if (onHover) {
        if (targetData) {
          onHover({
            elementId: targetData.elementId,
            kind: targetData.kind,
            hitKind: targetData.hitKind,
            modelPoint: hit?.point ? { x: hit.point.x, y: -hit.point.z } : null,
          });
          return;
        }
        if (raycaster.ray.intersectPlane(plane, planeHit)) {
          onHover({
            elementId: null,
            kind: null,
            hitKind: null,
            modelPoint: { x: planeHit.x, y: -planeHit.z },
          });
        } else {
          onHover({
            elementId: null,
            kind: null,
            hitKind: null,
            modelPoint: null,
          });
        }
      }
    };

    const handlePointerLeave = () => {
      lastHoverId = null;
      if (onHover) {
        onHover({ elementId: null, kind: null, hitKind: null, modelPoint: null });
      }
    };

    const emitPick = (event: PointerEvent) => {
      const rect = host.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) {
        return;
      }
      pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
      pointer.y = -(((event.clientY - rect.top) / rect.height) * 2 - 1);
      raycaster.setFromCamera(pointer, camera);
      const hits = modelGroupRef.current ? raycaster.intersectObject(modelGroupRef.current, true) : [];
      const hit = hits.find((candidate) => candidate.object.visible !== false) ?? null;
      const targetData = extract(hit?.object ?? null);
      if (targetData && onPick) {
        onPick({
          elementId: targetData.elementId,
          kind: targetData.kind,
          hitKind: targetData.hitKind,
          modelPoint: hit?.point ? { x: hit.point.x, y: -hit.point.z } : null,
        });
        return;
      }
      if (raycaster.ray.intersectPlane(plane, planeHit) && onPick) {
        onPick({
          elementId: null,
          kind: null,
          hitKind: null,
          modelPoint: { x: planeHit.x, y: -planeHit.z },
        });
      } else if (onPick) {
        onPick({
          elementId: null,
          kind: null,
          hitKind: null,
          modelPoint: null,
        });
      }
    };

    const scheduleHover = (event: PointerEvent) => {
      if (hoverFrame !== null) {
        window.cancelAnimationFrame(hoverFrame);
      }
      hoverFrame = window.requestAnimationFrame(() => {
        emitHover(event);
      });
    };

    host.addEventListener("pointerdown", emitPick);
    host.addEventListener("pointermove", scheduleHover);
    host.addEventListener("pointerleave", handlePointerLeave);
    return () => {
      host.removeEventListener("pointerdown", emitPick);
      host.removeEventListener("pointermove", scheduleHover);
      host.removeEventListener("pointerleave", handlePointerLeave);
      if (hoverFrame !== null) {
        window.cancelAnimationFrame(hoverFrame);
      }
    };
  }, [interactive, onHover, onPick, projectScene, viewPreset]);

  const handleResetView = () => {
    if (!cameraRef.current || !controlsRef.current || !activeBounds || activeBounds.isEmpty()) {
      return;
    }
    fitCameraToBounds(cameraRef.current, controlsRef.current, activeBounds, viewPreset);
  };

  const handleTopView = () => {
    setViewPreset("top");
    if (!cameraRef.current || !controlsRef.current || !activeBounds || activeBounds.isEmpty()) {
      return;
    }
    fitCameraToBounds(cameraRef.current, controlsRef.current, activeBounds, "top");
  };

  const handleIsoView = () => {
    setViewPreset("isometric");
    if (!cameraRef.current || !controlsRef.current || !activeBounds || activeBounds.isEmpty()) {
      return;
    }
    fitCameraToBounds(cameraRef.current, controlsRef.current, activeBounds, "isometric");
  };

  const handleFrontView = () => {
    setViewPreset("front");
    if (!cameraRef.current || !controlsRef.current || !activeBounds || activeBounds.isEmpty()) {
      return;
    }
    fitCameraToBounds(cameraRef.current, controlsRef.current, activeBounds, "front");
  };

  return (
    <div className="flex h-full flex-col gap-3">
      <div className="flex flex-wrap items-center justify-between gap-2 rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
        <div>
          <p className="font-medium text-slate-900">3D viewer</p>
          <p className="text-slate-500">{status}</p>
          <p className="text-[11px] text-slate-500">Engine XY plan → Three XZ ground, engine Z → Three Y up</p>
          {dimensions ? <p className="text-[11px] text-slate-500">{dimensions}</p> : null}
          <p className="text-[11px] text-slate-500">Source: {loadedSource}</p>
          <p className="text-[11px] text-slate-500">Reloaded: {loadedAtLabel ?? "-"}</p>
          <p className="text-[11px] text-slate-500">
            {sceneMode === "project"
              ? `Walls: ${projectScene?.walls ?? 0} • Openings: ${projectScene?.openings ?? 0} • Rooms: ${projectScene?.rooms ?? 0}`
              : `Objects: ${oriented?.objectCount ?? parsed?.objectCount ?? 0} • Components: ${oriented?.components.length ?? parsed?.components.length ?? 0} • Vertices: ${oriented?.vertexCount ?? parsed?.vertexCount ?? 0} • Faces: ${oriented?.faceCount ?? parsed?.faceCount ?? 0}`}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <button className="rounded-full border border-slate-200 bg-white px-3 py-1.5 hover:bg-slate-50" onClick={() => setShowGrid((value) => !value)}>
            {showGrid ? "Hide grid" : "Show grid"}
          </button>
          <button className="rounded-full border border-slate-200 bg-white px-3 py-1.5 hover:bg-slate-50" onClick={() => setShowAxes((value) => !value)}>
            {showAxes ? "Hide axes" : "Show axes"}
          </button>
          <button className="rounded-full border border-slate-200 bg-white px-3 py-1.5 hover:bg-slate-50" onClick={() => setWireframe((value) => !value)}>
            {wireframe ? "Wireframe" : "Solid"}
          </button>
          {viewPreset !== "top" ? (
            <>
              <button className="rounded-full border border-slate-200 bg-white px-3 py-1.5 hover:bg-slate-50" onClick={handleIsoView}>
                Isometric
              </button>
              <button className="rounded-full border border-slate-200 bg-white px-3 py-1.5 hover:bg-slate-50" onClick={handleTopView}>
                Top
              </button>
              <button className="rounded-full border border-slate-200 bg-white px-3 py-1.5 hover:bg-slate-50" onClick={handleFrontView}>
                Front
              </button>
            </>
          ) : (
            <div className="rounded-full border border-slate-200 bg-slate-50 px-3 py-1.5 text-xs text-slate-600">
              Top plan view
            </div>
          )}
          <button className="rounded-full border border-slate-200 bg-white px-3 py-1.5 hover:bg-slate-50" onClick={handleResetView}>
            Reset camera
          </button>
        </div>
      </div>
      <div
        ref={hostRef}
        className="min-h-0 flex-1 overflow-hidden rounded-2xl border border-slate-200 bg-[linear-gradient(180deg,#f4f7f5_0%,#e6ece7_100%)]"
      />
    </div>
  );
}
