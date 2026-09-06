# Bundled Family content

Drop validated `*.bimfamily` files in this directory to ship reusable Family
content without changing Dart source.

At app bootstrap, `FamilyBundledCatalog` discovers every bundled `.bimfamily`
asset, validates it with the same production validator used by save/import, and
`FamilyFileStore.ensureBuiltInFamilies()` seeds missing stable family ids into
the app-owned Family Library.

Rules:

- `FamilyDocument.id` must be stable and globally unique inside the shipped
  catalog.
- Every asset must pass `FamilyDocumentValidator`.
- File names are packaging only; stable family/type ids are authoritative.
- Existing local families are never overwritten during seed, so user edits are
  preserved.
- Category, types, parameters, formulas, geometry and description belong in the
  `.bimfamily` document itself.

This directory is intentionally content-driven. New chairs, casework, doors,
windows or generic components should normally be added here rather than by
editing `built_in_family_catalog.dart`.
