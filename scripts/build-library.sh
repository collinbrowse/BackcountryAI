#!/bin/bash
# Downloads every source and builds both libraries: $BACKCOUNTRY_DATA/library-full and library-lite.
# Re-run any time: downloads resume and finished sources are skipped.
#
# Usage: BACKCOUNTRY_DATA=/path/with/40GB/free scripts/build-library.sh
# Needs: python3.12 venv at .venv with libzim lxml trafilatura (see docs/library-hosting.md), and poppler (pdftotext).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export BACKCOUNTRY_DATA="${BACKCOUNTRY_DATA:-$ROOT/library.noindex}"
PY="$ROOT/.venv/bin/python"
FULL="$BACKCOUNTRY_DATA/library-full"
LITE="$BACKCOUNTRY_DATA/library-lite"

"$PY" "$ROOT/library/fetch_manuals.py"
"$PY" "$ROOT/library/fetch_zims.py"
"$PY" "$ROOT/library/fetch_risk.py"   # needs the Wikipedia ZIM for Essentials' risk articles

mkdir -p "$FULL" "$LITE"
LIBRARY_OUT="$FULL" "$PY" "$ROOT/library/build_library.py"
LIBRARY_OUT="$LITE" REUSE_FROM="$FULL" "$PY" "$ROOT/library/build_library.py" --lite

for LIB in "$FULL" "$LITE"; do
  rm -f "$LIB/.build.lock"
  cp "$ROOT/SOURCES.md" "$LIB/SOURCES.md"   # CC BY-SA asks for the license to travel with every copy
  "$ROOT/scripts/check-licenses.sh" "$LIB"
  "$PY" "$ROOT/library/check_search.py" "$LIB" || echo "WARNING: search check below target for $LIB"
done
echo "Built $FULL and $LITE"
