import '../render_scene_models.dart';
import 'ifc_source_inventory.dart';

class ModelImportMissingProduct {
  const ModelImportMissingProduct({
    required this.stepId,
    required this.entityType,
    required this.globalId,
  });

  final int stepId;
  final String entityType;
  final String globalId;

  String get label => globalId.isEmpty
      ? '#$stepId · $entityType'
      : '$entityType · $globalId · #$stepId';
}

/// Independent import quality report.
///
/// The source inventory is built before the native importer runs, while the
/// semantic side is measured from the resulting RenderScene. This means an
/// importer cannot accidentally redefine success by omitting unsupported IFC
/// products from its own counters.
class ModelImportAudit {
  const ModelImportAudit({
    required this.sourcePhysicalProducts,
    required this.importedSourceProducts,
    required this.nativeSemanticProducts,
    required this.exactSourceMeshProducts,
    required this.proxyProducts,
    required this.approximateProducts,
    required this.missingGeometryProducts,
    required this.unmatchedSourceProducts,
    required this.duplicateSourceIdentityObjects,
    required this.sourceProductsWithoutGlobalId,
    required this.unmatched,
    required this.sourceTypeCounts,
    required this.importedTypeCounts,
  });

  final int sourcePhysicalProducts;
  final int importedSourceProducts;
  final int nativeSemanticProducts;
  final int exactSourceMeshProducts;
  final int proxyProducts;
  final int approximateProducts;
  final int missingGeometryProducts;
  final int unmatchedSourceProducts;
  final int duplicateSourceIdentityObjects;
  final int sourceProductsWithoutGlobalId;
  final List<ModelImportMissingProduct> unmatched;
  final Map<String, int> sourceTypeCounts;
  final Map<String, int> importedTypeCounts;

  /// There is no silent loss: every uncovered source product is explicitly
  /// surfaced by this audit. `isComplete` is stricter and requires zero loss.
  bool get hasSilentDrops => false;
  bool get isComplete => unmatchedSourceProducts == 0;
  bool get hasQualityWarnings =>
      unmatchedSourceProducts > 0 ||
      approximateProducts > 0 ||
      missingGeometryProducts > 0 ||
      duplicateSourceIdentityObjects > 0;

  double get coverageRatio => sourcePhysicalProducts == 0
      ? 1.0
      : importedSourceProducts / sourcePhysicalProducts;

  String get compactSummary {
    final percent = (coverageRatio * 100).clamp(0, 100).toStringAsFixed(1);
    return 'IFC coverage $importedSourceProducts/$sourcePhysicalProducts '
        '($percent%) · exact $exactSourceMeshProducts · '
        'proxy $proxyProducts · missing $unmatchedSourceProducts';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'source_physical_products': sourcePhysicalProducts,
        'imported_source_products': importedSourceProducts,
        'native_semantic_products': nativeSemanticProducts,
        'exact_source_mesh_products': exactSourceMeshProducts,
        'proxy_products': proxyProducts,
        'approximate_products': approximateProducts,
        'missing_geometry_products': missingGeometryProducts,
        'unmatched_source_products': unmatchedSourceProducts,
        'duplicate_source_identity_objects': duplicateSourceIdentityObjects,
        'source_products_without_global_id': sourceProductsWithoutGlobalId,
        'coverage_ratio': coverageRatio,
        'source_type_counts': sourceTypeCounts,
        'imported_type_counts': importedTypeCounts,
        'unmatched': unmatched
            .map(
              (entry) => <String, Object?>{
                'step_id': entry.stepId,
                'entity_type': entry.entityType,
                'global_id': entry.globalId,
              },
            )
            .toList(growable: false),
      };

  static ModelImportAudit build({
    required IfcSourceInventory source,
    required RenderScene scene,
    int maxMissingDetails = 200,
  }) {
    final importedByGuid = <String, RenderSceneObject>{};
    final duplicateGuids = <String>{};
    final importedTypeCounts = <String, int>{};
    var nativeSemantic = 0;
    var exactMesh = 0;
    var proxies = 0;
    var approximated = 0;
    var missingGeometry = 0;

    for (final object in scene.objects) {
      final metadata = object.metadata;
      final guid = _metadataText(metadata, 'ifc_guid');
      final sourceEntity = _metadataText(metadata, 'ifc_entity').toUpperCase();
      if (guid.isEmpty && sourceEntity.isEmpty) continue;

      if (sourceEntity.isNotEmpty) {
        importedTypeCounts.update(
          sourceEntity,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      if (guid.isNotEmpty) {
        if (importedByGuid.containsKey(guid)) duplicateGuids.add(guid);
        importedByGuid[guid] = object;
      }

      final isProxy = object.kindKey == 'proxy';
      final isExact = _metadataBool(metadata, 'ifc_exact_geometry');
      if (isProxy) {
        proxies += 1;
      } else {
        nativeSemantic += 1;
      }
      if (isExact) exactMesh += 1;
      if (!object.mesh.hasGeometry) missingGeometry += 1;
      if (isProxy && !isExact) approximated += 1;
    }

    final missing = <ModelImportMissingProduct>[];
    var matched = 0;
    var withoutGuid = 0;
    for (final product in source.products) {
      if (product.globalId.isEmpty) {
        withoutGuid += 1;
        // A source product without a GlobalId cannot be proven against the
        // current legacy semantic objects. It remains explicitly unmatched.
        if (missing.length < maxMissingDetails) {
          missing.add(
            ModelImportMissingProduct(
              stepId: product.stepId,
              entityType: product.entityType,
              globalId: product.globalId,
            ),
          );
        }
        continue;
      }
      if (importedByGuid.containsKey(product.globalId)) {
        matched += 1;
      } else if (missing.length < maxMissingDetails) {
        missing.add(
          ModelImportMissingProduct(
            stepId: product.stepId,
            entityType: product.entityType,
            globalId: product.globalId,
          ),
        );
      }
    }

    return ModelImportAudit(
      sourcePhysicalProducts: source.physicalProductCount,
      importedSourceProducts: matched,
      nativeSemanticProducts: nativeSemantic,
      exactSourceMeshProducts: exactMesh,
      proxyProducts: proxies,
      approximateProducts: approximated,
      missingGeometryProducts: missingGeometry,
      unmatchedSourceProducts: source.physicalProductCount - matched,
      duplicateSourceIdentityObjects: duplicateGuids.length,
      sourceProductsWithoutGlobalId: withoutGuid,
      unmatched: List<ModelImportMissingProduct>.unmodifiable(missing),
      sourceTypeCounts: Map<String, int>.unmodifiable(source.typeCounts),
      importedTypeCounts: Map<String, int>.unmodifiable(importedTypeCounts),
    );
  }

  static String _metadataText(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    return value == null ? '' : '$value'.trim();
  }

  static bool _metadataBool(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    if (value is bool) return value;
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
}
