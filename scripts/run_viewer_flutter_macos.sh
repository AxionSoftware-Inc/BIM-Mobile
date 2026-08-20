#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/viewer_flutter"

cd "$APP_DIR"

echo "Starting viewer_flutter on macOS..."
echo "Use:"
echo "  r  -> hot reload"
echo "  R  -> hot restart"
echo "  q  -> quit"
echo

flutter run -d macos
