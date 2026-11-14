#!/bin/bash
# Grades Scout's answers with Claude (tools/grade-answers/grade.py) and, given two runs, compares them side by side.
# Make the runs with scripts/check-answers.sh, e.g. Apple's model vs the better-answers model on the same lists:
#   QUESTIONS=library/answer-questions.tsv scripts/check-answers.sh <library> --answers \
#     --conversations library/conversations.tsv --json build/grade-answers/apple.json
#   (the same with --qwen, into build/grade-answers/qwen.json)
#
# Usage: scripts/grade-answers.sh RUN.json [RUN2.json] [--label NAME ...] [--limit N] [--concurrency 4]
#        scripts/grade-answers.sh dry-run       fake records and grades: no API key or network
# Writes build/grade-answers/summary.md and one JSON report per run. Needs ANTHROPIC_API_KEY and
# `.venv/bin/pip install -r tools/requirements.txt`. About $0.03 an answer (docs/answer-quality.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PY:-$ROOT/.venv/bin/python}"
if [ "${1:-}" = "dry-run" ]; then
  D="$ROOT/build/grade-answers-dry-run"
  "$PY" -I "$ROOT/tools/train-answers/fake_records.py" "$D/apple.json" "$ROOT/library/answer-questions.tsv" \
    "$ROOT/library/conversations.tsv" --answers
  "$PY" -I "$ROOT/tools/train-answers/fake_records.py" "$D/qwen.json" "$ROOT/library/answer-questions.tsv" \
    "$ROOT/library/conversations.tsv" --answers --qwen
  "$PY" -I "$ROOT/tools/grade-answers/grade.py" "$D/apple.json" "$D/qwen.json" --out "$D" --dry-run
  exit 0
fi
[ $# -ge 1 ] || { sed -n '2,11p' "$0" >&2; exit 2; }
"$PY" -I "$ROOT/tools/grade-answers/grade.py" "$@"
