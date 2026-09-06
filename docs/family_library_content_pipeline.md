# Family Library and content pipeline

This document freezes the production persistence/content contract for reusable
Family assets.

## User-visible contract

- **Save** writes an authored Family into the persistent app-owned Family
  Library.
- **Edit Family → Save** updates the same stable family id even when its display
  name changes.
- **Import family** validates an external `.bimfamily` file and copies/updates it
  into the app-owned Library before placement. Projects do not depend on the
  original picked file remaining at its old path.
- **Export** is an explicit external-file operation and is separate from Save;
  the storage API is `FamilyFileStore.exportFile()`.
- Library placement carries the explicitly selected Family Type into the
  existing placement workflow.
- Search, category filters, Favorites and Recent operate on Library assets, not
  on duplicated project copies.

## Persistent storage

`AppProjectStorage.projectDirectory()` is the application-owned persistence
root:

- Android: native `Context.filesDir` through `tbe/app_storage`.
- iOS/macOS: sandbox/user `Library/Application Support/TabletBIM`.
- Windows: `%LOCALAPPDATA%/TabletBIM` with `%APPDATA%` fallback.
- Linux: `$XDG_DATA_HOME/TabletBIM` or `$HOME/.local/share/TabletBIM`.
- `systemTemp/tablet_bim_projects` is only a last-resort development fallback
  when the host exposes no persistent location.

Family files live under the `families/` child directory. Stable
`FamilyDocument.id`, not filename, is authoritative for update/deduplication.

## Shipped content

Two seed sources still exist for compatibility:

1. code-free `assets/families/*.bimfamily`, discovered by
   `FamilyBundledCatalog` from Flutter's asset manifest;
2. legacy `BuiltInFamilyCatalog.families`, retained only as a compatibility
   fallback/reference while the old Dart definitions are retired safely.

Bundled `.bimfamily` content is authoritative over the legacy Dart catalog for
the same stable id. `FamilyFileStore.ensureBuiltInFamilies()` composes both
sources by stable id, validates every seed and writes only ids missing from the
local Library. Existing local assets are never overwritten by app startup, so
user edits remain authoritative.

The bundled catalog now covers **all 23 shipped legacy production stable ids**.
`family_bundled_legacy_coverage_test.dart` locks this invariant. Future product
content must be asset-first; no new code-defined Family definitions should be
added to the legacy Dart catalog. Once a real Flutter test/build pass is
available, the legacy implementation can be reduced or removed without changing
runtime Family identity.

Conflicting duplicate ids inside bundled assets fail visibly instead of being
resolved by file order.

The project placement command calls `ensureBuiltInFamilies()` before
`listStored()` and before opening `FamilyLibraryDialog`, so newly shipped asset
families become visible without another bootstrap hook.

## Adding new production content

New reusable product content must normally be authored as a validated
`.bimfamily` document and added under `apps/viewer_flutter/assets/families/`.
The directory is bundled from `pubspec.yaml`; no Dart catalog edit is required.

A bundled family must:

- use a globally stable and unique Family id;
- use stable Family Type ids;
- pass `FamilyDocumentValidator`;
- carry category, parameters, formulas, types and geometry in the document;
- avoid depending on its package filename for identity.

## Library capability metadata

`FamilyLibraryMetadata` is the single derived classification contract for
Library presentation and future indexing. It computes deterministic counts and
capabilities from a `FamilyDocument`: types, parameters, formulas, constraints,
sketches, nested families, freeform meshes, booleans and parametric features.
Library UI/search code should consume this model instead of repeating feature
classification rules in multiple widgets. The model is presentation-safe and
does not mutate or persist additional BIM data.

## Authoring integration

V5 Advanced Sketch authoring composes three responsibilities into one surface:

- `FamilyParametersPanel` — custom parameters, formulas and current-type edits;
- `FamilyTypeMatrixPanel` — spreadsheet-style multi-type value editing plus
  duplicate/rename/delete across all named Family Types;
- geometric `FamilyConstraintsPanel` implementation — reference planes and
  sketch constraints.

The public `family_constraints_panel.dart` is the composite shell; the
geometric implementation lives in `family_constraints_geometry_panel.dart`.
All parameter/type mutations remain centralized in `FamilyParameterAuthoring`
and every committed document crosses `FamilyDocumentValidator`.

## Regression rules

A Family persistence/content change must preserve these invariants:

1. Save creates/updates one app-owned stable-id Library asset.
2. Import survives moving/deleting the external source after import.
3. Rename does not create a second Library family.
4. Existing user-edited Library assets are not overwritten during seed.
5. Bundled `.bimfamily` content needs no Dart catalog change.
6. Bundled assets shadow legacy definitions with the same stable id.
7. Every one of the 23 legacy shipped stable ids has a bundled asset.
8. Conflicting duplicate ids inside bundled content fail visibly.
9. Library-selected Family Type remains selected in placement.
10. Multi-type edits use `FamilyParameterAuthoring` and semantic validation.
11. Library capability classification comes from `FamilyLibraryMetadata`.
12. Invalid external or bundled families never cross into placement.
