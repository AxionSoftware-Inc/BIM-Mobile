#!/usr/bin/env bash
set -euo pipefail

brew install cmake opencascade

echo "Toolchain is ready."
echo "Next:"
echo "  cmake --preset dev"
echo "  cmake --build --preset dev"
echo "  ctest --preset dev"

