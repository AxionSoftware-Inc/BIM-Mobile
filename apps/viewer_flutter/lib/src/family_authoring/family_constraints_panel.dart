import 'package:flutter/material.dart';

import 'family_constraints_geometry_panel.dart' as geometry;
import 'family_document.dart';
import 'family_parameters_panel.dart';
import 'family_type_matrix_panel.dart';

/// Unified advanced Family authoring surface.
///
/// Parameter/type authoring and geometric constraints deliberately stay in
/// separate implementation widgets, but the editor exposes them as one
/// production panel so a user can define a parameter and immediately consume
/// it in formulas, reference planes and constraints without leaving Sketch.
class FamilyConstraintsPanel extends StatelessWidget {
  const FamilyConstraintsPanel({
    super.key,
    required this.document,
    required this.type,
    required this.selectedSketchId,
    required this.onChanged,
    required this.onStatus,
  });

  final FamilyDocument document;
  final FamilyTypeDefinition type;
  final String? selectedSketchId;
  final ValueChanged<FamilyDocument> onChanged;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FamilyParametersPanel(
          document: document,
          type: type,
          onChanged: onChanged,
          onStatus: onStatus,
        ),
        const SizedBox(height: 10),
        FamilyTypeMatrixPanel(
          document: document,
          currentTypeId: type.id,
          onChanged: onChanged,
          onStatus: onStatus,
        ),
        const SizedBox(height: 10),
        geometry.FamilyConstraintsPanel(
          document: document,
          type: type,
          selectedSketchId: selectedSketchId,
          onChanged: onChanged,
          onStatus: onStatus,
        ),
      ],
    );
  }
}
