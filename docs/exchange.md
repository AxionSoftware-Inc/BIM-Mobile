# IFC/RVT exchange contract

Tablet BIM keeps authored coordinates in metres and stores project display
units separately. Elements can carry typed metadata values (`text`, `number`,
`boolean`, `length`, `area`, `volume`, `angle`, and `element_reference`). The
same contract is available through the native API and the Flutter FFI layer.

## IFC

The current exporter writes an IFC4 STEP container with semantic IFC entities
for levels, walls, openings, rooms, slabs, roofs, columns, beams, and stairs.
It also writes a `TBE_DOCUMENT_JSON_HEX` IFC comment. That sidecar is the
lossless Tablet BIM interchange channel: it preserves exact geometry,
constraints, relations, project units, and typed metadata without converting
them to a lossy mesh.

Importing an IFC exported by Tablet BIM is lossless. Third-party IFC files are
also accepted through a conservative semantic fallback for storeys, walls,
doors, windows, slabs, roofs, columns, beams, and stairs. When a swept
profile, placement relation, or host relation cannot be resolved, the imported
element is marked with `ifc_import_note` and the API returns a warning so the
model is reviewable rather than silently treated as exact geometry.

The next IFC milestone is a kernel-backed profile/mesh parser for common
Revit/Archicad geometry representations.

## RVT

RVT is Autodesk's native database format, not a documented standalone file
format that can safely be implemented as a local byte-level converter. The
production bridge should use Autodesk Platform Services or an Autodesk/Revit
licensed worker to convert RVT to IFC/JSON, then import through the same
engine contract. The bridge needs tenant/client credentials and a controlled
cloud or licensed worker environment; those credentials are not present in
this workspace, so no fake `.rvt` exporter is included.

The app-facing exchange boundary is already separated from the document and
viewport layers, so adding that worker later will not change authoring or
navigation code.
