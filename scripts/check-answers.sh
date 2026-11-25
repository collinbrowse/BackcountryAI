#!/bin/bash
# Checks retrieval and answer quality with the app's own search code and Apple's on-device model (needs a Mac with
# Apple Intelligence on). Builds the ScoutTools target, then runs `scout-tools check` as an MLX job in this Mac's queue
# (scripts/queue.sh): never beside another MLX job, whose memory makes Apple's model fail every request.
# Usage: scripts/check-answers.sh <library-folder> [--answers] [--no-library] [--only TEXT] [--json FILE]
#        [--conversations FILE] [--qwen [DIR]] [--no-rerank] [--no-dense]
#   QUESTIONS=library/answer-questions.tsv to judge answers; QUESTIONS=- to run only --conversations.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$("$ROOT/scripts/build-scout-tools.sh")"
LIB="$1"; shift
exec "$ROOT/scripts/queue.sh" --credits 4 --lock mlx --label "BackcountryAI check answers" -- \
  "$BIN" check "$LIB" "${QUESTIONS:-$ROOT/library/questions.tsv}" "$@"
