#!/bin/bash
# Adds meaning-based search to a library folder: copies the embedder and reranker into models/ and writes
# vectors.bin (one vector per passage). Run after building a library, before scripts/release-pack.sh packages it.
# About 1.3 million passages for Essentials: expect roughly an hour on an M-series Mac (it prints its rate).
# Usage: scripts/embed-library.sh <library-folder> [--limit N]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$("$ROOT/scripts/build-scout-tools.sh")"
"$BIN" embed "$@"
