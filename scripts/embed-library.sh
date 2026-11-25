#!/bin/bash
# Adds meaning-based search to a library folder: copies the embedder and reranker into models/ and writes
# vectors.bin (one vector per passage). Run after building a library, before scripts/release-pack.sh packages it.
# About 1.3 million passages for Essentials: expect roughly an hour on an M-series Mac (it prints its rate).
# Runs as an MLX job in this Mac's queue (scripts/queue.sh): it waits while another MLX job runs.
# Usage: scripts/embed-library.sh <library-folder> [--limit N]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$("$ROOT/scripts/build-scout-tools.sh")"
exec "$ROOT/scripts/queue.sh" --credits 4 --lock mlx --label "BackcountryAI embed library" -- "$BIN" embed "$@"
