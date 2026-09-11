import 'dart:convert';
import 'dart:io';

import '../../application/import/ifc_source_inventory.dart';

/// Streaming STEP inventory. The complete IFC file is never loaded into Dart
/// memory, so even very large files can be audited before the native parser is
/// asked to commit a model.
class IfcSourceInventoryReader {
  const IfcSourceInventoryReader();

  Future<IfcSourceInventory> readPath(String path) async {
    final file = File(path);
    var assignmentCount = 0;
    final products = <IfcSourceProduct>[];
    final typeCounts = <String, int>{};

    final record = StringBuffer();
    var quoted = false;
    var pendingQuote = false;

    await for (final chunk in file.openRead().transform(utf8.decoder)) {
      for (var index = 0; index < chunk.length; index += 1) {
        final char = chunk[index];
        record.write(char);
        if (char == "'") {
          if (quoted) {
            if (pendingQuote) {
              pendingQuote = false;
            } else {
              pendingQuote = true;
            }
          } else {
            quoted = true;
            pendingQuote = false;
          }
          continue;
        }
        if (quoted && pendingQuote) {
          quoted = false;
          pendingQuote = false;
        }
        if (!quoted && char == ';') {
          final parsed = _parseRecord(record.toString());
          record.clear();
          if (parsed == null) continue;
          assignmentCount += 1;
          if (!_isRenderableProduct(parsed.entityType, parsed.arguments)) {
            continue;
          }
          products.add(
            IfcSourceProduct(
              stepId: parsed.stepId,
              entityType: parsed.entityType,
              globalId: _ifcString(
                parsed.arguments.isEmpty ? '' : parsed.arguments.first,
              ),
            ),
          );
          typeCounts.update(
            parsed.entityType,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      }
    }

    return IfcSourceInventory(
      assignmentCount: assignmentCount,
      physicalProductCount: products.length,
      products: List<IfcSourceProduct>.unmodifiable(products),
      typeCounts: Map<String, int>.unmodifiable(typeCounts),
    );
  }

  _IfcStepRecord? _parseRecord(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('#')) return null;
    final equals = trimmed.indexOf('=');
    final open = trimmed.indexOf('(', equals + 1);
    final close = trimmed.lastIndexOf(')');
    if (equals <= 1 || open <= equals || close <= open) return null;
    final stepId = int.tryParse(trimmed.substring(1, equals).trim());
    if (stepId == null) return null;
    final entityType = trimmed.substring(equals + 1, open).trim().toUpperCase();
    if (!entityType.startsWith('IFC')) return null;
    return _IfcStepRecord(
      stepId: stepId,
      entityType: entityType,
      arguments: _splitArguments(trimmed.substring(open + 1, close)),
    );
  }

  List<String> _splitArguments(String value) {
    final result = <String>[];
    var start = 0;
    var depth = 0;
    var quoted = false;
    for (var index = 0; index < value.length; index += 1) {
      final char = value[index];
      if (char == "'") {
        if (quoted && index + 1 < value.length && value[index + 1] == "'") {
          index += 1;
          continue;
        }
        quoted = !quoted;
      } else if (!quoted && char == '(') {
        depth += 1;
      } else if (!quoted && char == ')') {
        depth -= 1;
      } else if (!quoted && depth == 0 && char == ',') {
        result.add(value.substring(start, index).trim());
        start = index + 1;
      }
    }
    result.add(value.substring(start).trim());
    return result;
  }

  bool _isRenderableProduct(String type, List<String> arguments) {
    if (arguments.length < 7) return false;
    if (_nonRenderableExactTypes.contains(type)) return false;
    for (final prefix in _nonRenderablePrefixes) {
      if (type.startsWith(prefix)) return false;
    }

    final placement = arguments[5];
    final representation = arguments[6];
    final hasProductShape = representation.startsWith('#');
    final hasPlacement = placement == r'$' || placement.startsWith('#');
    return hasProductShape && hasPlacement;
  }

  String _ifcString(String value) {
    if (value.length < 2 || !value.startsWith("'") || !value.endsWith("'")) {
      return '';
    }
    return value
        .substring(1, value.length - 1)
        .replaceAll("''", "'")
        .trim();
  }
}

class _IfcStepRecord {
  const _IfcStepRecord({
    required this.stepId,
    required this.entityType,
    required this.arguments,
  });

  final int stepId;
  final String entityType;
  final List<String> arguments;
}

const Set<String> _nonRenderableExactTypes = <String>{
  'IFCPROJECT',
  'IFCSITE',
  'IFCBUILDING',
  'IFCBUILDINGSTOREY',
  'IFCSPACE',
  'IFCOPENINGELEMENT',
  'IFCVOIDINGFEATURE',
  'IFCANNOTATION',
  'IFCGRID',
};

const List<String> _nonRenderablePrefixes = <String>[
  'IFCREL',
  'IFCPROPERTY',
  'IFCQUANTITY',
  'IFCMATERIAL',
  'IFCSTYLE',
  'IFCPRESENTATION',
  'IFCREPRESENTATION',
  'IFCSHAPE',
  'IFCGEOMETRIC',
  'IFCCARTESIAN',
  'IFCDIRECTION',
  'IFCAXIS',
  'IFCLOCALPLACEMENT',
  'IFCOWNERHISTORY',
  'IFCPERSON',
  'IFCORGANIZATION',
  'IFCAPPLICATION',
  'IFCSIUNIT',
  'IFCUNIT',
  'IFCDIMENSIONAL',
  'IFCMEASURE',
  'IFCTYPE',
  'IFCROOT',
];
