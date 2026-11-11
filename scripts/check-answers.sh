#!/bin/bash
# Checks retrieval quality with the app's own search code and Apple's on-device model (needs a Mac with
# Apple Intelligence on). Usage: scripts/check-answers.sh <library-folder> [--answers] [--no-library] [--only TEXT]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/check-answers"
mkdir -p "$ROOT/build"
swiftc -O -parse-as-library -enable-bare-slash-regex -lsqlite3 -o "$BIN" \
  "$ROOT/Sources/Library.swift" "$ROOT/Sources/Retrieval.swift" "$ROOT/tools/check-answers/main.swift"
LIB="$1"; shift
"$BIN" "$LIB" "$ROOT/library/questions.tsv" "$@"
