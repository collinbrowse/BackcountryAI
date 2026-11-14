#!/bin/bash
# Releases a library as an Apple-hosted asset pack, start to finish:
#   checks (licenses, search, quality audit) -> builds the .aar -> updates PackCatalog in Sources/LibraryStore.swift
#   -> uploads to App Store Connect and waits for Apple to process it -> optionally publishes the text on Hugging Face.
#
# Usage: scripts/release-pack.sh <pack-id> [options]
#   --library DIR      library folder (default: $BACKCOUNTRY_DATA/library-<pack-id>)
#   --rebuild          download sources and rebuild the library first (scripts/build-library.sh)
#   --no-upload        stop after building the pack and updating PackCatalog
#   --hf REPO          also publish the text to this Hugging Face dataset (user/name)
#   --force            continue even if the search check is below target
#
# Upload needs an App Store Connect API key (Users and Access › Integrations › App Store Connect API, role App
# Manager or higher). Put its .p8 file in ~/private_keys/AuthKey_<KEY_ID>.p8 and the IDs in .asc.env at the
# repository root (see .asc.env.example). .asc.env is git-ignored.
#
# Writes a summary to build/asset-packs/<pack-id>-release.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="$ROOT/.venv/bin/python"
ID="${1:?usage: release-pack.sh <pack-id> [--library DIR] [--rebuild] [--no-upload] [--hf REPO] [--force]}"
shift
export BACKCOUNTRY_DATA="${BACKCOUNTRY_DATA:-$ROOT/library.noindex}"
LIB="$BACKCOUNTRY_DATA/library-$ID"
REBUILD=0 UPLOAD=1 FORCE=0 HF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --library) LIB="$2"; shift ;;
    --rebuild) REBUILD=1 ;;
    --no-upload) UPLOAD=0 ;;
    --hf) HF="$2"; shift ;;
    --force) FORCE=1 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

step() { printf '\n== %s\n' "$*"; }
fail() { echo "STOPPED: $*" >&2; exit 1; }

# Check the upload credentials first, so a long build doesn't end in a missing-key error.
# shellcheck source=scripts/asc.sh
source "$ROOT/scripts/asc.sh"
[ "$UPLOAD" = 1 ] && asc_init "$ROOT"

if [ "$REBUILD" = 1 ]; then
  step "Rebuilding the library (downloads resume; this can take hours)"
  "$ROOT/scripts/build-library.sh"
fi
[ -f "$LIB/index.sqlite" ] || fail "no library at $LIB. Build it (--rebuild) or pass --library."
LIB="$(cd "$LIB" && pwd)"

step "Checking licenses"
"$ROOT/scripts/check-licenses.sh" "$LIB"

step "Checking search"
if ! "$PY" "$ROOT/library/check_search.py" "$LIB"; then
  [ "$FORCE" = 1 ] || fail "search check below target. Fix it, or pass --force to release anyway."
  echo "Continuing anyway (--force)."
fi

step "Auditing content quality"
AUDIT="$LIB-reports/quality-audit.md"
"$PY" "$ROOT/library/audit_library.py" "$LIB" --out "$AUDIT"

step "Building the asset pack"
# Meaning-based search: the embedder, the reranker and one vector per passage ship inside the pack
# (docs/answer-quality.md). Without them the app still works, on keyword search alone.
if [ ! -f "$LIB/vectors.bin" ]; then
  step "Adding the search models and passage vectors (about an hour for Essentials)"
  "$ROOT/scripts/embed-library.sh" "$LIB"
fi
"$ROOT/scripts/build-asset-packs.sh" "$LIB" "$ID"
AAR="$ROOT/build/asset-packs/$ID.aar"

step "Updating PackCatalog"
ARTICLES=$(sqlite3 "file:$LIB/index.sqlite?immutable=1" "SELECT SUM(docs) FROM sources WHERE done=1")
DOWNLOAD=$(stat -f %z "$AAR")
UNPACKED=$(find "$LIB" -type f -print0 | xargs -0 stat -f %z | awk '{s+=$1} END {print s}')
CATALOG_NOTE=""
if ! "$PY" "$ROOT/library/update_catalog.py" "$ROOT/Sources/LibraryStore.swift" "$ID" "$ARTICLES" "$DOWNLOAD" "$UNPACKED"; then
  CATALOG_NOTE="No PackCatalog entry for \"$ID\": add one to Sources/LibraryStore.swift."
  echo "$CATALOG_NOTE"
fi
printf '%s articles, %s download, %s on the phone\n' "$ARTICLES" "$(du -h "$AAR" | cut -f1)" \
  "$(echo "$UNPACKED" | awk '{printf "%.1fG", $1/1e9}')"

STATUS="not uploaded (--no-upload)"
if [ "$UPLOAD" = 1 ]; then
  step "Uploading to App Store Connect and waiting for processing"
  LOG="$ROOT/build/asset-packs/$ID-upload.log"
  asc_upload "$AAR" "$ID" "$LOG"
  STATUS="uploaded; see $LOG"
fi

if [ -n "$HF" ]; then
  step "Publishing the text on Hugging Face"
  "$ROOT/scripts/upload-huggingface.sh" "$LIB" "$HF"
fi

SUMMARY="$ROOT/build/asset-packs/$ID-release.md"
cat > "$SUMMARY" <<MD
# Release of asset pack "$ID" ($(date '+%Y-%m-%d %H:%M'))

- Library: $LIB
- Articles: $ARTICLES
- Download: $DOWNLOAD bytes; on the phone: $UNPACKED bytes
- Pack: $AAR
- Upload: $STATUS
- Hugging Face: ${HF:-not published (pass --hf user/name)}
- Quality audit: $AUDIT
${CATALOG_NOTE:+- $CATALOG_NOTE}

Still to do by hand in App Store Connect: test the pack in TestFlight, then submit it for review with the next build.
MD
step "Done"
cat "$SUMMARY"
