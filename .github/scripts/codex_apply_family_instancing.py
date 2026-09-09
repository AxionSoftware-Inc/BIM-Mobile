from pathlib import Path

HOST = Path(
    "apps/viewer_flutter/android/app/src/main/kotlin/"
    "com/example/viewer_flutter/RenderSceneFilamentHostView.kt"
)

OLD = '''  private fun isInstanceCandidate(objectData: SceneObject): Boolean {
    if (clipVolume.active || !instanceGroupingEnabled) return false
    return normalizeKind(objectData.kind) in setOf("door", "window", "column")
  }
'''

NEW = '''  private fun isInstanceCandidate(objectData: SceneObject): Boolean {
    return NativeFamilyInstancingPolicy.isCandidate(
      normalizedKind = normalizeKind(objectData.kind),
      metadata = objectData.metadata,
      groupingEnabled = instanceGroupingEnabled,
      clipActive = clipVolume.active,
    )
  }
'''

MARKER = "NativeFamilyInstancingPolicy.isCandidate("


def main() -> None:
    source = HOST.read_text(encoding="utf-8")
    if MARKER in source:
        print("Native family instancing policy is already wired into the host.")
        return

    occurrences = source.count(OLD)
    if occurrences != 1:
        raise SystemExit(
            "Guard failed: expected exactly one legacy isInstanceCandidate "
            f"block, found {occurrences}. Host left unchanged."
        )

    patched = source.replace(OLD, NEW, 1)
    if patched.count(MARKER) != 1:
        raise SystemExit("Guard failed: patched host does not contain one policy call.")

    HOST.write_text(patched, encoding="utf-8")
    print("Wired NativeFamilyInstancingPolicy into RenderSceneFilamentHostView.")


if __name__ == "__main__":
    main()
