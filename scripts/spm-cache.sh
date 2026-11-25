#!/bin/bash
# Swift package checkouts shared by every worktree on this Mac, so a new worktree doesn't clone and resolve MLX and
# the other packages again: ~/Library/Caches/BackcountryAI/SourcePackages/<hash of Package.resolved>. Each version of
# Package.resolved gets its own folder, so worktrees on different package versions never share one.
#
# Usage: scripts/spm-cache.sh --xcode-flags
#   Resolves the packages into the shared folder (one checkout at a time, under an exclusive lock), then prints the
#   flags that make xcodebuild use it without resolving again:
#     -clonedSourcePackagesDirPath <folder> -disableAutomaticPackageResolution
#   Prints nothing on CI (it caches build/DerivedData/SourcePackages itself, see .github/actions/setup) or on a Mac
#   without the job queue (~/.claude/bin/slot); xcodebuild then resolves into its derived data as usual.
#   e.g. xcodebuild ... -derivedDataPath build/DerivedData $(scripts/spm-cache.sh --xcode-flags) test
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ "${1:-}" = "--xcode-flags" ] || { sed -n '2,12p' "$0" >&2; exit 2; }
[ -z "${CI:-}" ] && [ -x "${SLOT_BIN:-$HOME/.claude/bin/slot}" ] || exit 0

RESOLVED="$ROOT/BackcountryAI.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
[ -f "$RESOLVED" ] || { echo "spm-cache.sh: no $RESOLVED (run xcodegen generate, or restore it from git)" >&2; exit 1; }
HASH="$(shasum -a 256 "$RESOLVED" | cut -c1-12)"
BASE="$HOME/Library/Caches/BackcountryAI/SourcePackages"
DIR="$BASE/$HASH"
mkdir -p "$BASE"

# The slot lock shows up in the queue; lockf also holds when this runs inside another slot job (where slot doesn't
# queue nested commands, locks included). Resolving an already-resolved folder takes a few seconds.
"$ROOT/scripts/queue.sh" --credits 1 --lock "spm-backcountryai-$HASH" --label "BackcountryAI resolve packages" -- \
  /usr/bin/lockf -k "$DIR.lock" \
  xcodebuild -resolvePackageDependencies -project "$ROOT/BackcountryAI.xcodeproj" -scheme BackcountryAI \
    -clonedSourcePackagesDirPath "$DIR" -skipPackagePluginValidation -skipMacroValidation -quiet >&2

echo "-clonedSourcePackagesDirPath $DIR -disableAutomaticPackageResolution"
