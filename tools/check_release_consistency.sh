#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
pubspec="$repo_root/apps/viewer_flutter/pubspec.yaml"
telemetry="$repo_root/apps/viewer_flutter/lib/src/telemetry_service.dart"
release_doc="$repo_root/docs/release.md"
architecture_doc="$repo_root/docs/v0_1_architecture_boundaries.md"

release_line="$(awk '/^version:[[:space:]]*/ {print $2; exit}' "$pubspec")"
if [[ "$release_line" != *+* ]]; then
  echo "Release consistency error: pubspec version must be name+code (got '$release_line')" >&2
  exit 1
fi

version_name="${release_line%%+*}"
version_code="${release_line##*+}"
expected_release="viewer_flutter@${release_line}"

require_text() {
  local file="$1"
  local text="$2"
  if ! rg -Fq -- "$text" "$file"; then
    echo "Release consistency error: '$text' is missing from $file" >&2
    exit 1
  fi
}

require_text "$telemetry" "defaultValue: '$expected_release'"
require_text "$release_doc" "release line is \`${release_line}\`"
require_text "$release_doc" "-VersionName ${version_name} -VersionCode ${version_code}"
require_text "$architecture_doc" "mobile release version (currently \`${release_line}\`)"

echo "Release metadata consistent: ${release_line}"
