#!/bin/bash
# Builds the ScoutTools Mac target (MLX's GPU code needs xcodebuild, not swiftc) and prints the binary's path.
# Goes through this Mac's job queue (scripts/queue.sh) and shares Swift package checkouts with the other worktrees
# (scripts/spm-cache.sh); where neither applies it's a plain xcodebuild.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/scout-tools"
read -r -a SPM <<< "$("$ROOT/scripts/spm-cache.sh" --xcode-flags)"
JOBS=()
[ -x "${SLOT_BIN:-$HOME/.claude/bin/slot}" ] && JOBS=(-jobs "${SLOT_XCODE_JOBS:-4}")
"$ROOT/scripts/queue.sh" --credits 4 --label "BackcountryAI build scout-tools" -- \
  xcodebuild -project "$ROOT/BackcountryAI.xcodeproj" -scheme ScoutTools -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DD" ${SPM[@]+"${SPM[@]}"} ${JOBS[@]+"${JOBS[@]}"} build -quiet >&2
echo "$DD/Build/Products/Release/scout-tools"
