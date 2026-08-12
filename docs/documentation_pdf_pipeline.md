# Documentation and PDF pipeline

## User workflow

1. Expand **Project Browser > Sheets** and press **New Sheet**. The main model
   viewport becomes an A3 landscape sheet canvas.
2. Long-press a 3D View, Floor Plan, Elevation or Section in Project Browser,
   then drag it onto the sheet. A Section resolves a true engine cut snapshot,
   not an elevation substitute.
3. Move a placed view from its title strip, resize it from the lower-right
   handle, or remove it with the close button.
4. Press **PDF** on the sheet context bar. The preview preserves the normalized
   viewport positions and title block from the interactive sheet.
5. Enter project/title-block data, inspect the A3 preview, then print/share or
   press **Save PDF** to create the stable
   project document in the app-owned `documents` directory.

The top application-bar **Documentation and PDF** action remains the fast path
for automatically generated current/all-level floor-plan sets.

The interactive viewport is never captured directly. Selection, temporary
sketches, zoom and Inspector state therefore cannot leak into an issued sheet.

## Architecture

- `document_models.dart` owns immutable sheet settings, semantic view
  references, normalized viewport placements, numbering and the
  current/all-level sheet resolver.
- `sheet_workspace_controller.dart` owns sheet creation and view placement,
  move, resize and removal commands without owning model geometry.
- `sheet_canvas.dart` owns the interactive A3 canvas and drag target.
- `document_pdf_service.dart` owns high-resolution plan/3D/elevation/section
  rendering, composed A3 sheets, title blocks, PDF metadata and durable output.
- `documentation_workspace.dart` owns sheet setup, preview, print/share and
  save interactions.
- The Project Browser publishes semantic drag payloads only. Section geometry
  is resolved through `SceneViewService`; neither browser nor canvas touches
  native session handles.

The plan image is regenerated from authoritative `RenderScene` data at about
200 dpi. It reuses the same joined wall-cut painter as the live floor plan, but
suppresses transient object-ID labels. PDF generation is explicit and on
demand; it is not part of normal viewport rendering.

The selected scale is a physical paper scale, not a fit-to-page caption. Model
meters are converted to PDF millimeters. If the requested scale cannot fit the
A3 drawing frame, that sheet advances to the next standard denominator (for
example, a campus requested at 1:100 is issued at 1:200) and both title-block
scale labels report the effective value.

## Floor-plan wall cut contract

- Normal walls are painted as one unioned horizontal cut network.
- Material layer strips are unioned by material and ordered layer index before
  hatch/line rendering.
- Miter, tee and cross joins must not receive a separate rectangular end cap
  or doubled normal outline.
- Selection remains a separate per-wall overlay, preserving edit identity
  without changing the normal documentation linework.
- Large scenes keep semantic layer data even when detailed hatch rendering is
  skipped for responsiveness.

## Current production boundary

This release provides A3 sheet creation, deterministic numbering, arbitrary
3D/floor/elevation/section viewport composition, move/resize/remove, automatic
floor-plan sets, title-block metadata, preview, print, share and PDF output.
Dimensions, annotations, legends, schedules, revision clouds and persistence of
sheet composition inside the native project schema remain subsequent document
features. They should extend the sheet model and PDF service rather than adding
export logic to `viewer_app.dart` or the viewport renderer.
