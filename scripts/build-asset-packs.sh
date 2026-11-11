#!/bin/bash
# Packages a library folder (index.sqlite + text/) into an Apple-hosted asset pack for App Store Connect.
#
# Usage: scripts/build-asset-packs.sh <library-folder> <pack-id> [--allow-noncommercial]
#   pack-id is "lite" (Essentials, the only library the app offers); it must match PackCatalog in Sources/LibraryStore.swift.
#   --allow-noncommercial skips the license check. Only for local testing with ba-serve; never upload that pack.
#
# Output: build/asset-packs/<pack-id>.aar. Upload it with the Transporter app (or altool) to the app's
# record in App Store Connect, then submit it for review with the next TestFlight or App Store build.
set -euo pipefail
LIB="${1:?usage: build-asset-packs.sh <library-folder> <pack-id> [--allow-noncommercial]}"
ID="${2:?usage: build-asset-packs.sh <library-folder> <pack-id> [--allow-noncommercial]}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$(cd "$LIB" && pwd)"

if [ "${3:-}" != "--allow-noncommercial" ]; then
  "$ROOT/scripts/check-licenses.sh" "$LIB"
fi

OUT="$ROOT/build/asset-packs"
mkdir -p "$OUT"
MANIFEST="$OUT/$ID-manifest.json"
# Files land under <pack-id>/ in the app's asset-pack namespace (the app reads "<pack-id>/index.sqlite").
cat > "$MANIFEST" <<JSON
{
  "assetPackID": "$ID",
  "downloadPolicy": { "onDemand": {} },
  "fileSelectors": [
    { "directorySource": "$(basename "$LIB")", "directoryDestination": "$ID" }
  ],
  "platforms": ["iOS"]
}
JSON

cd "$(dirname "$LIB")"
xcrun ba-package evaluate "$MANIFEST" >/dev/null 2>&1 || true
rm -f "$OUT/$ID.aar"   # ba-package will not overwrite an existing archive
xcrun ba-package package "$MANIFEST" --output-path "$OUT/$ID.aar"
echo "Built $OUT/$ID.aar ($(du -h "$OUT/$ID.aar" | cut -f1))"
