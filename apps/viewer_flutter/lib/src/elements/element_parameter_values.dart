import '../render_scene_models.dart';

int? elementParameterInt(RenderSceneObject object, String key) {
  final value = object.metadata[key];
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  return int.tryParse(value?.toString().trim() ?? '');
}

double? elementParameterDouble(RenderSceneObject object, String key) {
  final value = object.metadata[key];
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().trim() ?? '');
  return parsed != null && parsed.isFinite ? parsed : null;
}

bool elementParameterBool(RenderSceneObject object, String key,
    {bool fallback = false}) {
  final value = object.metadata[key];
  if (value is bool) return value;
  if (value == null) return fallback;
  switch (value.toString().trim().toLowerCase()) {
    case 'true':
      return true;
    case 'false':
      return false;
    default:
      return fallback;
  }
}

String? elementParameterText(RenderSceneObject object, String key) {
  final value = object.metadata[key]?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}
