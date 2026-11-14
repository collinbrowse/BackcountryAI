#!/bin/bash
# Checks retrieval and answer quality with the app's own search code and Apple's on-device model (needs a Mac with
# Apple Intelligence on). Builds the ScoutTools target, then runs `scout-tools check`.
# Usage: scripts/check-answers.sh <library-folder> [--answers] [--no-library] [--only TEXT] [--json FILE]
#        [--conversations FILE] [--qwen [DIR]] [--no-rerank] [--no-dense]
#   QUESTIONS=library/answer-questions.tsv to judge answers; QUESTIONS=- to run only --conversations.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$("$ROOT/scripts/build-scout-tools.sh")"
LIB="$1"; shift
"$BIN" check "$LIB" "${QUESTIONS:-$ROOT/library/questions.tsv}" "$@"
