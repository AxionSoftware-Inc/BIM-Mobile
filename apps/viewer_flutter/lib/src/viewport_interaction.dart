import 'package:flutter/material.dart';

/// Backend-independent selection state used by both the Flutter canvas and the
/// Android platform view.  IDs are stable engine element IDs encoded as text.
@immutable
class ViewportSelectionState {
  const ViewportSelectionState({
    this.selectedElementIds = const <String>{},
    this.activeElementId,
    this.selectedLevelId,
    this.hoveredElementId,
    this.selectionRect,
  });

  final Set<String> selectedElementIds;
  final String? activeElementId;
  final int? selectedLevelId;
  final String? hoveredElementId;
  final Rect? selectionRect;

  bool get isEmpty => selectedElementIds.isEmpty && selectedLevelId == null;

  ViewportSelectionState copyWith({
    Set<String>? selectedElementIds,
    String? activeElementId,
    int? selectedLevelId,
    String? hoveredElementId,
    Rect? selectionRect,
    bool clearActive = false,
    bool clearLevel = false,
    bool clearHover = false,
    bool clearRectangle = false,
  }) {
    return ViewportSelectionState(
      selectedElementIds: selectedElementIds ?? this.selectedElementIds,
      activeElementId:
          clearActive ? null : activeElementId ?? this.activeElementId,
      selectedLevelId:
          clearLevel ? null : selectedLevelId ?? this.selectedLevelId,
      hoveredElementId:
          clearHover ? null : hoveredElementId ?? this.hoveredElementId,
      selectionRect:
          clearRectangle ? null : selectionRect ?? this.selectionRect,
    );
  }
}

enum ViewportDragIntent { idle, objectDrag, rectangleSelect, gizmoDrag }

@immutable
class ViewportSelectionModifiers {
  const ViewportSelectionModifiers(
      {this.additive = false, this.toggle = false});

  final bool additive;
  final bool toggle;

  static ViewportSelectionModifiers fromKeyboard({
    required bool control,
    required bool shift,
  }) {
    return ViewportSelectionModifiers(additive: shift, toggle: control);
  }
}

/// Pure interaction policy. Rendering and engine mutations intentionally stay
/// outside this class so input behavior remains identical across backends.
class ViewportInteractionController {
  static const double dragThreshold = 8;

  Offset? _down;
  String? _downElementId;
  ViewportSelectionModifiers _modifiers = const ViewportSelectionModifiers();
  ViewportDragIntent _intent = ViewportDragIntent.idle;
  bool _crossing = false;

  ViewportDragIntent get intent => _intent;
  bool get isCrossingSelection => _crossing;

  void begin({
    required Offset position,
    required String? elementId,
    required ViewportSelectionModifiers modifiers,
    required bool allowObjectDrag,
    bool requireRectangleArm = false,
  }) {
    _down = position;
    _downElementId = elementId;
    _modifiers = modifiers;
    _intent = allowObjectDrag && elementId != null
        ? ViewportDragIntent.objectDrag
        : elementId == null && !requireRectangleArm
            ? ViewportDragIntent.rectangleSelect
            : ViewportDragIntent.idle;
  }

  /// Touch uses a hold before beginning a selection window so a normal
  /// one-finger drag is still free for camera navigation.
  void armRectangleSelect() {
    if (_downElementId == null) {
      _intent = ViewportDragIntent.rectangleSelect;
    }
  }

  Rect? update(Offset position) {
    final down = _down;
    if (down == null || (position - down).distance < dragThreshold) {
      return null;
    }
    if (_downElementId == null &&
        _intent == ViewportDragIntent.rectangleSelect) {
      _crossing = position.dx < down.dx;
      return Rect.fromPoints(down, position);
    }
    return null;
  }

  Set<String> resolveClick({
    required ViewportSelectionState current,
    required String? elementId,
  }) {
    if (elementId == null) {
      return const <String>{};
    }
    final next = Set<String>.from(current.selectedElementIds);
    if (_modifiers.toggle && next.contains(elementId)) {
      next.remove(elementId);
    } else if (_modifiers.additive || _modifiers.toggle) {
      next.add(elementId);
    } else {
      next
        ..clear()
        ..add(elementId);
    }
    return next;
  }

  Set<String> resolveRectangle({
    required ViewportSelectionState current,
    required Iterable<MapEntry<String, Rect>> candidates,
    required Rect rect,
  }) {
    final matched = <String>{
      for (final candidate in candidates)
        if (_crossing
            ? candidate.value.overlaps(rect)
            : rect.contains(candidate.value.topLeft) &&
                rect.contains(candidate.value.bottomRight))
          candidate.key,
    };
    if (_modifiers.additive || _modifiers.toggle) {
      final next = Set<String>.from(current.selectedElementIds);
      for (final id in matched) {
        if (_modifiers.toggle && next.contains(id)) {
          next.remove(id);
        } else {
          next.add(id);
        }
      }
      return next;
    }
    return matched;
  }

  void reset() {
    _down = null;
    _downElementId = null;
    _intent = ViewportDragIntent.idle;
    _crossing = false;
    _modifiers = const ViewportSelectionModifiers();
  }
}
