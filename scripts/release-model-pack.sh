#!/bin/bash
# Releases the "Better answers" model (Qwen 3.5 4B, 4-bit MLX) as the Apple-hosted asset pack "answers":
#   downloads the pinned model from Hugging Face -> drops the image weights the app never uses
#   -> builds build/asset-packs/answers.aar -> uploads it to App Store Connect and waits for processing.
#
# Usage: scripts/release-model-pack.sh [--no-upload] [--model-dir DIR]
#   --model-dir packages a local model folder laid out like the download (a fine-tune from
#   scripts/train-answers.sh train: build/train-answers/model) instead of downloading the pinned revision.
#
# Upload credentials: see scripts/asc.sh. After the upload, test the pack in TestFlight, then submit it for review
# with the next build, as with the library.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ID="answers"                                   # must match BetterModel.assetPackID
MODEL="mlx-community/Qwen3.5-4B-MLX-4bit"      # must match BetterModel.modelID
REVISION="32f3e8ecf65426fc3306969496342d504bfa13f3"   # the revision benchmarked on iPhone, 2026-11-12
FILES=(config.json chat_template.jinja tokenizer.json tokenizer_config.json vocab.json README.md
       model.safetensors model.safetensors.index.json)
UPLOAD=1
MODEL_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-upload) UPLOAD=0 ;;
    --model-dir) MODEL_DIR="$(cd "$2" && pwd)"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

step() { printf '\n== %s\n' "$*"; }
# shellcheck source=scripts/asc.sh
source "$ROOT/scripts/asc.sh"
[ "$UPLOAD" = 1 ] && asc_init "$ROOT"

WORK="$ROOT/build/model-pack"
SRC="$WORK/download"
OUT="$ROOT/build/asset-packs"
mkdir -p "$SRC" "$OUT"

if [ -n "$MODEL_DIR" ]; then
  step "Using the local model in $MODEL_DIR"
  SRC="$MODEL_DIR"
else
step "Getting $MODEL at $REVISION"
CACHED="$HOME/.cache/huggingface/hub/models--${MODEL//\//--}/snapshots/$REVISION"
for f in "${FILES[@]}"; do
  if [ -f "$CACHED/$f" ]; then
    cp -L "$CACHED/$f" "$SRC/$f"
  elif [ ! -s "$SRC/$f" ]; then
    curl -fL --retry 3 -C - -o "$SRC/$f.part" "https://huggingface.co/$MODEL/resolve/$REVISION/$f"
    mv "$SRC/$f.part" "$SRC/$f"
  fi
done
fi

step "Dropping the image weights"
rm -rf "$WORK/$ID"
python3 -I "$ROOT/tools/strip_vision_weights.py" "$SRC" "$WORK/$ID"
curl -fsSL "https://www.apache.org/licenses/LICENSE-2.0.txt" -o "$WORK/$ID/LICENSE" \
  || echo "Couldn't fetch the Apache 2.0 text; add it as $WORK/$ID/LICENSE before uploading." >&2

step "Building the asset pack"
MANIFEST="$OUT/$ID-manifest.json"
# Files land under answers/ in the app's asset-pack namespace (the app reads "answers/config.json").
cat > "$MANIFEST" <<JSON
{
  "assetPackID": "$ID",
  "downloadPolicy": { "onDemand": {} },
  "fileSelectors": [
    { "directorySource": "$ID", "directoryDestination": "$ID" }
  ],
  "platforms": ["iOS"]
}
JSON
cd "$WORK"
xcrun ba-package evaluate "$MANIFEST" >/dev/null 2>&1 || true
rm -f "$OUT/$ID.aar"   # ba-package will not overwrite an existing archive
xcrun ba-package package "$MANIFEST" --output-path "$OUT/$ID.aar"
BYTES=$(stat -f %z "$OUT/$ID.aar")
echo "Built $OUT/$ID.aar ($(du -h "$OUT/$ID.aar" | cut -f1)). If the size changed, update BetterModel.downloadBytes ($BYTES)."

if [ "$UPLOAD" = 1 ]; then
  step "Uploading to App Store Connect and waiting for processing"
  asc_upload "$OUT/$ID.aar" "$ID" "$OUT/$ID-upload.log"
fi
step "Done"
