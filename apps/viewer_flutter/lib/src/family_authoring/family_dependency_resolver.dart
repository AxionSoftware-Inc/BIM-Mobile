import 'dart:math' as math;

import 'family_document.dart';
import 'family_file_store.dart';
import 'family_geometry.dart';
import 'family_parameter_resolver.dart';
import 'family_validation.dart';

/// Resolves nested-family references before the synchronous geometry evaluator
/// runs. Child documents remain separate reusable assets on disk; only their
/// evaluated mesh is materialized into a transient document.
///
/// This separation is intentional: geometry evaluation stays deterministic and
/// file-system independent, while missing assets, invalid type references and
/// dependency cycles are rejected at one async boundary.
abstract final class FamilyDependencyResolver {
  /// Resolves [root] against the app-owned Family Library.
  static Future<FamilyDocument> resolveFromLibrary(
    FamilyDocument root,
    FamilyTypeDefinition rootType,
  ) async {
    final stored = await FamilyFileStore.listStored();
    return resolve(
      root,
      rootType,
      availableDocuments: <FamilyDocument>[
        root,
        for (final asset in stored) asset.document,
      ],
    );
  }

  /// Pure dependency resolver used by tests and non-file-system callers.
  static FamilyDocument resolve(
    FamilyDocument root,
    FamilyTypeDefinition rootType, {
    required Iterable<FamilyDocument> availableDocuments,
  }) {
    if (!root.types.any((type) => type.id == rootType.id)) {
      throw const FormatException(
        'Selected root Family Type does not belong to the root family.',
      );
    }

    final documents = <String, FamilyDocument>{};
    for (final document in availableDocuments) {
      final id = document.id.trim();
      if (id.isEmpty) continue;
      final existing = documents[id];
      if (existing != null && !identical(existing, document)) {
        if (existing.toJsonText() != document.toJsonText()) {
          throw FormatException('Duplicate Family Library id: $id');
        }
      }
      documents[id] = document;
    }
    documents[root.id] = root;

    final cache = <String, FamilyDocument>{};
    final visiting = <String>[];
    return _resolveDocument(
      root,
      rootType,
      documents: documents,
      cache: cache,
      visiting: visiting,
    );
  }

  static FamilyDocument _resolveDocument(
    FamilyDocument document,
    FamilyTypeDefinition type, {
    required Map<String, FamilyDocument> documents,
    required Map<String, FamilyDocument> cache,
    required List<String> visiting,
  }) {
    final nodeKey = _nodeKey(document.id, type.id);
    final cached = cache[nodeKey];
    if (cached != null) return cached;

    final cycleAt = visiting.indexOf(nodeKey);
    if (cycleAt >= 0) {
      final cycle = <String>[...visiting.sublist(cycleAt), nodeKey].join(' -> ');
      throw FormatException('Nested family dependency cycle: $cycle');
    }

    final validation = FamilyDocumentValidator.validate(document);
    if (!validation.isValid) {
      throw FormatException(
        '${document.name}: ${validation.errors.join('; ')}',
      );
    }

    visiting.add(nodeKey);
    try {
      final resolvedFeatures = <FamilyFeature>[];
      for (final feature in document.features) {
        if (feature.kind != FamilyFeatureKind.nestedFamily) {
          resolvedFeatures.add(feature);
          continue;
        }

        final familyId = _requiredToken(
          feature.parameters['familyId'],
          'Nested feature ${feature.id} requires familyId.',
        );
        final typeId = _requiredToken(
          feature.parameters['typeId'],
          'Nested feature ${feature.id} requires typeId.',
        );
        final child = documents[familyId];
        if (child == null) {
          throw FormatException(
            'Nested family "$familyId" referenced by ${document.name} is unavailable.',
          );
        }
        FamilyTypeDefinition? childType;
        for (final candidate in child.types) {
          if (candidate.id == typeId) {
            childType = candidate;
            break;
          }
        }
        if (childType == null) {
          throw FormatException(
            'Nested family ${child.name} has no Family Type "$typeId".',
          );
        }

        final resolvedChild = _resolveDocument(
          child,
          childType,
          documents: documents,
          cache: cache,
          visiting: visiting,
        );
        final childMesh = FamilyGeometryEvaluator.evaluateMesh(
          resolvedChild,
          childType,
        );
        if (childMesh.vertices.isEmpty || childMesh.faces.isEmpty) {
          throw FormatException(
            'Nested family ${child.name} · ${childType.name} has no renderable geometry.',
          );
        }
        final transformed = _transformNestedMesh(
          document,
          type,
          childMesh,
          feature,
        );
        resolvedFeatures.add(
          FamilyFeature(
            id: feature.id,
            kind: FamilyFeatureKind.freeformMesh,
            label: feature.label.isEmpty
                ? '${child.name} · ${childType.name}'
                : feature.label,
            inputs: feature.inputs,
            parameters: <String, Object?>{
              'sourceFormat': 'nestedFamily',
              'nestedFamilyId': child.id,
              'nestedTypeId': childType.id,
              // Parent width/depth/height must not implicitly stretch a child.
              // A nested instance changes size only through the selected child
              // type or its explicit parent transform/constraints.
              'preserveDimensions': true,
              'vertices': <List<double>>[
                for (final vertex in transformed.vertices)
                  <double>[vertex.x, vertex.y, vertex.z],
              ],
              'faces': <List<int>>[
                for (final face in transformed.faces)
                  List<int>.unmodifiable(face.indices),
              ],
            },
          ),
        );
      }

      final resolved = document.copyWith(features: resolvedFeatures);
      cache[nodeKey] = resolved;
      return resolved;
    } finally {
      visiting.removeLast();
    }
  }

  static FamilyEvaluatedMesh _transformNestedMesh(
    FamilyDocument parent,
    FamilyTypeDefinition parentType,
    FamilyEvaluatedMesh child,
    FamilyFeature feature,
  ) {
    final resolver = FamilyParameterResolver(parent, parentType);
    final tx = _resolveScalar(
      feature.parameters['translationX'],
      resolver,
      fallback: 0.0,
    );
    final ty = _resolveScalar(
      feature.parameters['translationY'],
      resolver,
      fallback: 0.0,
    );
    final tz = _resolveScalar(
      feature.parameters['translationZ'],
      resolver,
      fallback: 0.0,
    );
    final rotation = _resolveScalar(
          feature.parameters['rotationZ'],
          resolver,
          fallback: 0.0,
        ) *
        math.pi /
        180.0;
    final scale = _resolveScalar(
      feature.parameters['scale'],
      resolver,
      fallback: 1.0,
    );
    if (!scale.isFinite || scale <= 0.0) {
      throw FormatException(
        'Nested feature ${feature.id} scale must be positive.',
      );
    }

    final cosine = math.cos(rotation);
    final sine = math.sin(rotation);
    return child.copyWith(
      vertices: List<FamilyMeshVertex>.unmodifiable(
        child.vertices.map((vertex) {
          final x = vertex.x * scale;
          final y = vertex.y * scale;
          return FamilyMeshVertex(
            x: x * cosine - y * sine + tx,
            y: x * sine + y * cosine + ty,
            z: vertex.z * scale + tz,
          );
        }),
      ),
      source: feature.label.isEmpty ? child.source : feature.label,
    );
  }

  static double _resolveScalar(
    Object? raw,
    FamilyParameterResolver resolver, {
    required double fallback,
  }) {
    if (raw == null) return fallback;
    if (raw is num) {
      final value = raw.toDouble();
      if (!value.isFinite) {
        throw const FormatException('Nested transform contains a non-finite value.');
      }
      return value;
    }
    final token = raw.toString().trim();
    if (token.isEmpty) return fallback;
    final direct = double.tryParse(token.replaceAll(',', '.'));
    if (direct != null) {
      if (!direct.isFinite) {
        throw const FormatException('Nested transform contains a non-finite value.');
      }
      return direct;
    }
    return resolver.resolveExpression(token);
  }

  static String _requiredToken(Object? raw, String error) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) throw FormatException(error);
    return value;
  }

  static String _nodeKey(String familyId, String typeId) =>
      '${familyId.trim()}::${typeId.trim()}';
}
