#!/bin/bash
# Publishes a library's text on Hugging Face, so the CC BY-SA text is shared under the same license.
#
# Usage: scripts/upload-huggingface.sh <library-folder> <user-or-org/dataset-name>
# Needs: pip install -U huggingface_hub, then `hf auth login` with a write token.
# Refuses to upload a library that has any non-commercial or no-derivatives source.
set -euo pipefail
LIB="${1:?usage: upload-huggingface.sh <library-folder> <repo-id>}"
REPO="${2:?usage: upload-huggingface.sh <library-folder> <repo-id>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$ROOT/.venv/bin:$PATH"   # hf from the project venv
command -v hf >/dev/null || { echo "Install the Hugging Face CLI: pip install -U huggingface_hub" >&2; exit 1; }

"$ROOT/scripts/check-licenses.sh" "$LIB"

CARD="$(mktemp -d)/README.md"
{
  sed "s|{{REPO}}|$REPO|g" "$ROOT/docs/huggingface-dataset-card.md"
  echo
  echo "| Source | License | Articles |"
  echo "|---|---|---|"
  sqlite3 -separator ' | ' "file:$LIB/index.sqlite?immutable=1" \
    "SELECT '| ' || label, COALESCE(license,''), docs || ' |' FROM sources WHERE done=1 ORDER BY docs DESC"
} > "$CARD"

hf repos create "$REPO" --repo-type dataset --exist-ok
hf upload "$REPO" "$LIB" . --repo-type dataset --commit-message "Library text"
hf upload "$REPO" "$CARD" README.md --repo-type dataset
echo "Published https://huggingface.co/datasets/$REPO"
