#!/usr/bin/env bash
set -euo pipefail

# Runs the real Android/Kotlin/Filament path locally. This avoids manually
# copying every debug APK to a physical tablet while preserving the same ABI,
# platform-view and GPU renderer integration.
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AVD_NAME="${1:-Medium_Tablet}"
SDK_DIR="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"

if [[ -z "$SDK_DIR" ]]; then
  echo "ANDROID_SDK_ROOT or ANDROID_HOME must point to the Android SDK." >&2
  exit 1
fi

EMULATOR_BIN="$SDK_DIR/emulator/emulator"
ADB_BIN="$SDK_DIR/platform-tools/adb"
if [[ ! -x "$EMULATOR_BIN" || ! -x "$ADB_BIN" ]]; then
  echo "Android emulator or adb was not found under: $SDK_DIR" >&2
  exit 1
fi

if ! "$ADB_BIN" devices | awk 'NR > 1 && $2 == "device" { found = 1 } END { exit found ? 0 : 1 }'; then
  echo "Starting Android emulator: $AVD_NAME"
  "$EMULATOR_BIN" -avd "$AVD_NAME" -gpu host -no-snapshot-save >/tmp/tablet_bim_emulator.log 2>&1 &
  "$ADB_BIN" wait-for-device
  until [[ "$("$ADB_BIN" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
    sleep 2
  done
fi

DEVICE_ID="$("$ADB_BIN" devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
if [[ -z "$DEVICE_ID" ]]; then
  echo "No running Android emulator/device found." >&2
  exit 1
fi

cd "$APP_DIR"
echo "Running Tablet BIM on Android device: $DEVICE_ID"
echo "Flutter terminal: r = hot reload, R = hot restart, q = quit"
flutter run -d "$DEVICE_ID"
