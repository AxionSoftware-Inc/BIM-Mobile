"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";

type ObjViewerProps = {
  objText: string | null;
};

type ParsedObj = {
  geometry: THREE.BufferGeometry;
  vertexCount: number;
  faceCount: number;
  bounds: THREE.Box3;
};

function parseObj(text: string): ParsedObj | null {
  const vertices: THREE.Vector3[] = [];
  const indices: number[] = [];
  const lines = text.split(/\r?\n/);

  for (const rawLine of lines) {
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

    if (faceVertices.length < 3) {
      continue;
    }

    for (let index = 1; index < faceVertices.length - 1; index += 1) {
      indices.push(faceVertices[0], faceVertices[index], faceVertices[index + 1]);
    }
  }

  if (vertices.length === 0 || indices.length === 0) {
    return null;
  }

  const positions = new Float32Array(vertices.length * 3);
  vertices.forEach((vertex, index) => {
    positions[index * 3] = vertex.x;
    positions[index * 3 + 1] = vertex.y;
    positions[index * 3 + 2] = vertex.z;
  });

  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  geometry.computeBoundingBox();

  const bounds = geometry.boundingBox?.clone() ?? new THREE.Box3().setFromArray(Array.from(positions));

  return {
    geometry,
    vertexCount: vertices.length,
    faceCount: indices.length / 3,
    bounds,
  };
}

export default function ObjViewer({ objText }: ObjViewerProps) {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null);
  const sceneRef = useRef<THREE.Scene | null>(null);
  const cameraRef = useRef<THREE.PerspectiveCamera | null>(null);
  const controlsRef = useRef<OrbitControls | null>(null);
  const meshRef = useRef<THREE.Mesh | null>(null);
  const frameRef = useRef<number | null>(null);
  const [wireframe, setWireframe] = useState(false);
  const parsed = useMemo(() => (objText ? parseObj(objText) : null), [objText]);
  const status = !objText ? "No OBJ loaded" : parsed ? `Vertices ${parsed.vertexCount} • Faces ${parsed.faceCount}` : "OBJ could not be parsed";

  useEffect(() => {
    const host = hostRef.current;
    if (!host) {
      return;
    }

    const scene = new THREE.Scene();
    scene.background = new THREE.Color("#eef2f0");
    scene.fog = new THREE.Fog("#eef2f0", 120, 1000);
    sceneRef.current = scene;

    const camera = new THREE.PerspectiveCamera(45, 1, 0.1, 5000);
    camera.position.set(140, 120, 160);
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
    controls.target.set(0, 0, 0);
    controlsRef.current = controls;

    const ambient = new THREE.AmbientLight(0xffffff, 1.45);
    scene.add(ambient);
    const light1 = new THREE.DirectionalLight(0xffffff, 1.0);
    light1.position.set(140, 220, 180);
    scene.add(light1);
    const light2 = new THREE.DirectionalLight(0xcbd5e1, 0.5);
    light2.position.set(-120, 120, -150);
    scene.add(light2);
    scene.add(new THREE.GridHelper(400, 40, 0x94a3b8, 0xdbe4de));
    scene.add(new THREE.AxesHelper(80));

    const resize = () => {
      const width = host.clientWidth || 1;
      const height = host.clientHeight || 1;
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
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
    };
  }, [objText]);

  const fitCamera = () => {
    const camera = cameraRef.current;
    const controls = controlsRef.current;
    const mesh = meshRef.current;
    if (!camera || !controls || !mesh) {
      return;
    }

    const bounds = new THREE.Box3().setFromObject(mesh);
    const size = new THREE.Vector3();
    const center = new THREE.Vector3();
    bounds.getSize(size);
    bounds.getCenter(center);
    const maxDim = Math.max(size.x, size.y, size.z, 1);
    const distance = maxDim * 1.65;

    controls.target.copy(center);
    camera.near = Math.max(0.1, maxDim / 100);
    camera.far = Math.max(2000, maxDim * 20);
    camera.updateProjectionMatrix();
    camera.position.set(center.x + distance, center.y + distance * 0.75, center.z + distance);
    controls.update();
  };

  useEffect(() => {
    const scene = sceneRef.current;
    const host = hostRef.current;
    const renderer = rendererRef.current;
    if (!scene || !renderer || !host) {
      return;
    }

    if (meshRef.current) {
      scene.remove(meshRef.current);
      meshRef.current.geometry.dispose();
      const existingMaterial = meshRef.current.material;
      if (Array.isArray(existingMaterial)) {
        existingMaterial.forEach((material) => material.dispose());
      } else {
        existingMaterial.dispose();
      }
      meshRef.current = null;
    }

    if (!parsed) {
      return;
    }

    const material = new THREE.MeshStandardMaterial({
      color: 0x64748b,
      roughness: 0.9,
      metalness: 0.05,
      wireframe,
    });
    const mesh = new THREE.Mesh(parsed.geometry.clone(), material);
    mesh.rotation.x = Math.PI / 2;
    meshRef.current = mesh;
    scene.add(mesh);
    fitCamera();
  }, [parsed, wireframe, objText]);

  useEffect(() => {
    if (meshRef.current) {
      const material = meshRef.current.material;
      if (!Array.isArray(material)) {
        (material as THREE.MeshStandardMaterial).wireframe = wireframe;
      }
    }
  }, [wireframe]);

  return (
    <div className="flex h-full flex-col gap-3">
      <div className="flex flex-wrap items-center justify-between gap-2 rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
        <div>
          <p className="font-medium text-slate-900">OBJ viewer</p>
          <p className="text-slate-500">{status}</p>
        </div>
        <div className="flex items-center gap-2">
          <button className="rounded-full border border-slate-200 bg-white px-3 py-1.5 hover:bg-slate-50" onClick={() => setWireframe((value) => !value)}>
            {wireframe ? "Wireframe" : "Solid"}
          </button>
          <button className="rounded-full border border-slate-200 bg-white px-3 py-1.5 hover:bg-slate-50" onClick={fitCamera}>
            Reset camera
          </button>
        </div>
      </div>

      <div ref={hostRef} className="min-h-0 flex-1 overflow-hidden rounded-3xl border border-slate-200 bg-[#eef2f0]">
        {!objText ? (
          <div className="flex h-full items-center justify-center p-8 text-center text-sm text-slate-500">
            <div>
              <p className="font-medium text-slate-700">No OBJ file found in the sample artifacts.</p>
              <p className="mt-2">Drop `public/sample/walls.obj` into place to enable the 3D preview.</p>
            </div>
          </div>
        ) : parsed ? null : (
          <div className="flex h-full items-center justify-center p-8 text-center text-sm text-slate-500">
            <div>
              <p className="font-medium text-slate-700">OBJ loaded, but no renderable geometry was detected.</p>
              <p className="mt-2">The viewer currently expects a simple triangular or polygonal OBJ mesh.</p>
            </div>
          </div>
        )}
      </div>

      <div className="text-xs text-slate-500">
        3D selection is not wired yet. Per-element picking will need OBJ or glTF metadata later.
      </div>
    </div>
  );
}
