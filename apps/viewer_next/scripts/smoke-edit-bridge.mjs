import { readFile, stat } from "node:fs/promises";
import path from "node:path";

const baseUrl = process.env.VIEWER_BASE_URL ?? "http://127.0.0.1:3000";
const sampleDir = path.resolve(process.cwd(), "public/sample");

async function readJson(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}

async function readDebug() {
  return readJson(path.join(sampleDir, "debug_report.json"));
}

function validationErrors(debugJson) {
  return Number(debugJson?.validation?.errors ?? 0);
}

async function postJson(route, body) {
  const response = await fetch(new URL(route, baseUrl), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => null);
  if (!payload) {
    throw new Error(`${route}: invalid JSON response`);
  }
  if (!response.ok || !payload.success) {
    throw new Error(`${route}: ${payload.error ?? payload.message ?? `HTTP ${response.status}`}`);
  }
  return payload;
}

async function ensureArtifacts() {
  const files = ["project.json", "debug_report.json", "floorplan.svg", "walls.obj", "metadata.json", "render_scene.json"];
  for (const file of files) {
    await stat(path.join(sampleDir, file));
  }
  await readJson(path.join(sampleDir, "project.json"));
  await readJson(path.join(sampleDir, "debug_report.json"));
  await readJson(path.join(sampleDir, "render_scene.json"));
}

function firstWallId(projectJson) {
  const walls = wallCandidates(projectJson);
  const wall = walls[0];
  if (!wall?.id) {
    throw new Error("No wall found in public/sample/project.json");
  }
  return wall.id;
}

function wallCandidates(projectJson) {
  const elements = projectJson?.document?.elements ?? [];
  return elements
    .filter((element) => element?.kind === "Wall")
    .map((wall) => {
      const openings = Array.isArray(wall?.wall?.openings) ? wall.wall.openings.length : 0;
      const axis = wall?.wall?.axis;
      const start = axis?.start ?? { x: 0, y: 0 };
      const end = axis?.end ?? { x: 0, y: 0 };
      const length = Math.hypot((end.x ?? 0) - (start.x ?? 0), (end.y ?? 0) - (start.y ?? 0));
      return { id: wall.id, openings, length };
    })
    .sort((left, right) => left.openings - right.openings || right.length - left.length);
}

function countSchedules(debugJson, key) {
  return Array.isArray(debugJson?.schedules?.[key]) ? debugJson.schedules[key].length : 0;
}

async function main() {
  const projectJson = await readJson(path.join(sampleDir, "project.json"));
  const initialDebug = await readDebug();
  const walls = wallCandidates(projectJson);
  const hostWallId = walls[0]?.id ?? firstWallId(projectJson);
  const secondaryWallId = walls[1]?.id ?? hostWallId;
  const initialWallCount = countSchedules(initialDebug, "walls");
  const initialOpeningCount = countSchedules(initialDebug, "openings");
  const initialRoomCount = countSchedules(initialDebug, "rooms");
  const initialRenderScene = await readJson(path.join(sampleDir, "render_scene.json"));
  const initialRenderSceneObjects = Array.isArray(initialRenderScene?.objects) ? initialRenderScene.objects.length : 0;

  const createdWall = await postJson("/api/edit/create-wall", {
    start: { x: 20, y: 20 },
    end: { x: 24, y: 20 },
    height_meters: 3,
    thickness_meters: 0.2,
  });
  const createdWallId = createdWall.commandOutput?.wall_id ?? createdWall.wall_id;
  if (!createdWallId) {
    throw new Error("create_wall did not return a wall_id");
  }
  const afterCreateDebug = await readDebug();
  if (countSchedules(afterCreateDebug, "walls") < initialWallCount + 1) {
    throw new Error("wall count did not increase after create_wall");
  }
  const afterCreateRenderScene = await readJson(path.join(sampleDir, "render_scene.json"));
  if ((Array.isArray(afterCreateRenderScene?.objects) ? afterCreateRenderScene.objects.length : 0) < initialRenderSceneObjects + 1) {
    throw new Error("render_scene object count did not increase after create_wall");
  }

  const insertedDoor = await postJson("/api/edit/insert-door", {
    host_wall_id: hostWallId,
    offset_meters: 1.2,
    width_meters: 0.9,
    height_meters: 2.1,
    clearance_meters: 0.05,
  });
  const doorId = insertedDoor.commandOutput?.opening_id ?? insertedDoor.opening_id;
  if (!doorId) {
    throw new Error("insert_door did not return an opening_id");
  }
  const afterDoorDebug = await readDebug();
  if (countSchedules(afterDoorDebug, "openings") < initialOpeningCount + 1) {
    throw new Error("opening count did not increase after insert_door");
  }
  const afterDoorRenderScene = await readJson(path.join(sampleDir, "render_scene.json"));
  if ((Array.isArray(afterDoorRenderScene?.objects) ? afterDoorRenderScene.objects.length : 0) <= (Array.isArray(afterCreateRenderScene?.objects) ? afterCreateRenderScene.objects.length : 0)) {
    throw new Error("render_scene object count did not update after insert_door");
  }

  await postJson("/api/edit/update-door", {
    door_id: doorId,
    offset_meters: 1.4,
    width_meters: 0.9,
    height_meters: 2.1,
  });

  const insertedWindow = await postJson("/api/edit/insert-window", {
    host_wall_id: secondaryWallId,
    offset_meters: 1.8,
    width_meters: 1.2,
    height_meters: 1.2,
    sill_height_meters: 0.9,
    clearance_meters: 0.05,
  });
  const windowId = insertedWindow.commandOutput?.opening_id ?? insertedWindow.opening_id;
  if (!windowId) {
    throw new Error("insert_window did not return an opening_id");
  }
  const afterWindowDebug = await readDebug();
  if (countSchedules(afterWindowDebug, "openings") < initialOpeningCount + 2) {
    throw new Error("opening count did not increase after insert_window");
  }
  const afterWindowRenderScene = await readJson(path.join(sampleDir, "render_scene.json"));
  if ((Array.isArray(afterWindowRenderScene?.objects) ? afterWindowRenderScene.objects.length : 0) <= (Array.isArray(afterDoorRenderScene?.objects) ? afterDoorRenderScene.objects.length : 0)) {
    throw new Error("render_scene object count did not update after insert_window");
  }

  await postJson("/api/edit/update-window", {
    window_id: windowId,
    offset_meters: 2.2,
    width_meters: 1.2,
    height_meters: 1.1,
    sill_height_meters: 0.95,
  });

  await postJson("/api/edit/delete-element", {
    element_id: windowId,
  });
  const afterDeleteDebug = await readDebug();
  if (countSchedules(afterDeleteDebug, "openings") > initialOpeningCount + 1) {
    throw new Error("opening count did not decrease after delete_element");
  }

  await postJson("/api/edit/set-wall-axis", {
    wall_id: createdWallId,
    start: { x: 20.2, y: 20 },
    end: { x: 24.2, y: 20 },
  });

  await postJson("/api/edit/update-wall", {
    wall_id: createdWallId,
    height_meters: 3.2,
    thickness_meters: 0.18,
  });

  await ensureArtifacts();
  const finalDebug = await readDebug();
  const finalRenderScene = await readJson(path.join(sampleDir, "render_scene.json"));
  if (validationErrors(finalDebug) !== 0) {
    throw new Error(`final validation errors were not zero (${validationErrors(finalDebug)})`);
  }

  console.log(JSON.stringify({
    success: true,
    hostWallId,
    createdWallId,
    doorId,
    windowId,
    initialCounts: {
      walls: initialWallCount,
      openings: initialOpeningCount,
      rooms: initialRoomCount,
      renderSceneObjects: initialRenderSceneObjects,
    },
    finalCounts: {
      walls: countSchedules(finalDebug, "walls"),
      openings: countSchedules(finalDebug, "openings"),
      rooms: countSchedules(finalDebug, "rooms"),
      renderSceneObjects: Array.isArray(finalRenderScene?.objects) ? finalRenderScene.objects.length : 0,
    },
    artifacts: ["project.json", "debug_report.json", "floorplan.svg", "walls.obj", "metadata.json", "render_scene.json"],
  }, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
