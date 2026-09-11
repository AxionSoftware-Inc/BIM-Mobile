/// One renderable IFC product discovered directly in the source STEP stream.
///
/// This inventory is deliberately independent from the native importer. It is
/// the outside truth used to detect products that disappeared during import.
class IfcSourceProduct {
  const IfcSourceProduct({
    required this.stepId,
    required this.entityType,
    required this.globalId,
  });

  final int stepId;
  final String entityType;
  final String globalId;

  String get stableSourceId =>
      globalId.isNotEmpty ? globalId : '#$stepId:$entityType';
}

class IfcSourceInventory {
  const IfcSourceInventory({
    required this.assignmentCount,
    required this.physicalProductCount,
    required this.products,
    required this.typeCounts,
  });

  final int assignmentCount;
  final int physicalProductCount;
  final List<IfcSourceProduct> products;
  final Map<String, int> typeCounts;

  Map<String, Object?> toJson() => <String, Object?>{
        'assignment_count': assignmentCount,
        'physical_product_count': physicalProductCount,
        'type_counts': typeCounts,
        'products': products
            .map(
              (product) => <String, Object?>{
                'step_id': product.stepId,
                'entity_type': product.entityType,
                'global_id': product.globalId,
              },
            )
            .toList(growable: false),
      };

  static IfcSourceInventory fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid IFC source inventory.');
    }
    final products = <IfcSourceProduct>[];
    final rawProducts = value['products'];
    if (rawProducts is List) {
      for (final item in rawProducts) {
        if (item is! Map) continue;
        final stepId = int.tryParse('${item['step_id'] ?? ''}');
        final entityType = '${item['entity_type'] ?? ''}'.trim().toUpperCase();
        if (stepId == null || entityType.isEmpty) continue;
        products.add(
          IfcSourceProduct(
            stepId: stepId,
            entityType: entityType,
            globalId: '${item['global_id'] ?? ''}'.trim(),
          ),
        );
      }
    }
    final typeCounts = <String, int>{};
    final rawCounts = value['type_counts'];
    if (rawCounts is Map) {
      for (final entry in rawCounts.entries) {
        final count = int.tryParse('${entry.value}');
        if (count != null && count >= 0) {
          typeCounts['${entry.key}'] = count;
        }
      }
    }
    return IfcSourceInventory(
      assignmentCount: int.tryParse('${value['assignment_count'] ?? 0}') ?? 0,
      physicalProductCount:
          int.tryParse('${value['physical_product_count'] ?? products.length}') ??
              products.length,
      products: List<IfcSourceProduct>.unmodifiable(products),
      typeCounts: Map<String, int>.unmodifiable(typeCounts),
    );
  }
}
