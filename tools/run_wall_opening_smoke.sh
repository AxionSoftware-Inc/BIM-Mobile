#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -z "${TBE_CAPI_PATH:-}" ]]; then
  for candidate in \
    "$repo_root/build/dev/src/api/libtbe_capi.dylib" \
    "$repo_root/build/dev/src/api/libtbe_capi.so" \
    "$repo_root/build/ci/src/api/libtbe_capi.dylib" \
    "$repo_root/build/ci/src/api/libtbe_capi.so"; do
    if [[ -f "$candidate" ]]; then
      export TBE_CAPI_PATH="$candidate"
      break
    fi
  done
fi

if [[ -z "${TBE_CAPI_PATH:-}" ]]; then
  echo "TBE_CAPI_PATH is not set and no local C API library was found." >&2
  exit 1
fi

cd "$repo_root/apps/viewer_flutter"

# The golden scenario uses the same C ABI as the mobile app: create two walls,
# cut door/window voids into one host, atomically edit an opening, undo/redo,
# and assert that the unrelated wall is unchanged.
flutter test test/widget_test.dart --name 'golden wall-opening workflow'
