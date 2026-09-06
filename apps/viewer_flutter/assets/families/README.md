# Bundled Family content

Drop validated `*.bimfamily` files in this directory to ship reusable Family
content without changing Dart source.

At app bootstrap, `FamilyBundledCatalog` discovers every bundled `.bimfamily`
asset, validates it with the same production validator used by save/import, and
`FamilyFileStore.ensureBuiltInFamilies()` seeds missing stable family ids into
the app-owned Family Library.

Rules:

- `FamilyDocument.id` must be stable and globally unique inside bundled content.
- Every asset must pass `FamilyDocumentValidator`.
- File names are packaging only; stable family/type ids are authoritative.
- Existing local families are never overwritten during seed, so user edits are
  preserved.
- Category, types, parameters, formulas, geometry and description belong in the
  `.bimfamily` document itself.
- A bundled asset intentionally shadows a legacy Dart built-in with the same
  stable id. This preserves user/project identity during migration.
- Two different bundled documents must never reuse the same stable id.

The bundled directory now covers all **23 legacy shipped production stable
ids**. `family_bundled_legacy_coverage_test.dart` locks that invariant. The old
Dart catalog remains only as a compatibility fallback/reference while real
Flutter build/test coverage is unavailable; new production content must be
asset-first.

This directory is intentionally content-driven. New chairs, casework, doors,
windows, stairs, fixtures or generic components should be added here rather
than by editing `built_in_family_catalog.dart`.
