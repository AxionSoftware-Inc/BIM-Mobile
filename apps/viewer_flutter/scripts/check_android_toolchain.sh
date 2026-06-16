#!/usr/bin/env bash
set -euo pipefail

echo "Flutter:"
flutter --version || true

echo
echo "Flutter doctor:"
flutter doctor -v || true

echo
echo "Connected devices:"
flutter devices || true

echo
echo "Android environment:"
echo "ANDROID_HOME=${ANDROID_HOME:-<unset>}"
echo "ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-<unset>}"
echo "ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-<unset>}"

for path in \
  "${ANDROID_HOME:-}" \
  "${ANDROID_SDK_ROOT:-}" \
  "${HOME}/Library/Android/sdk"
do
  if [[ -n "${path}" && -d "${path}" ]]; then
    echo "Found SDK path: ${path}"
    ls "${path}" | sed -n '1,40p'
  fi
done

if [[ -x "./android/gradlew" ]]; then
  echo
  echo "Gradle tasks:"
  ./android/gradlew -p android tasks --all | sed -n '1,40p' || true
fi

echo
echo "If Flutter reports a missing Android SDK, install Android Studio and"
echo "then point Flutter at the SDK with:"
echo "  flutter config --android-sdk /path/to/Android/Sdk"
