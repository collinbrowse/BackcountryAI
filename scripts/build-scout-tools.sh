#!/bin/bash
# Builds the ScoutTools Mac target (MLX's GPU code needs xcodebuild, not swiftc) and prints the binary's path.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/scout-tools"
xcodebuild -project "$ROOT/BackcountryAI.xcodeproj" -scheme ScoutTools -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DD" build -quiet >&2
echo "$DD/Build/Products/Release/scout-tools"
