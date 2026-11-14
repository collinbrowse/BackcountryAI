#!/bin/bash
# Distils Claude's answers into the "Better answers" model (Qwen 3.5 4B) with LoRA, one step at a time. Everything
# lands in build/train-answers. See docs/answer-quality.md for costs and timings.
#
# Usage: scripts/train-answers.sh questions [--n 1500]        Claude writes questions and follow-up conversations
#        scripts/train-answers.sh prompts <library-folder>    the app's retrieval builds a prompt for each (Mac, Apple
#                                                             Intelligence on; slow: Apple's model plans every search)
#        scripts/train-answers.sh answers [--check]           Claude writes the ideal answers -> train/valid/test data
#        scripts/train-answers.sh train [train.sh options]    LoRA on this Mac -> fused model laid out for the pack
#        scripts/train-answers.sh eval                        base vs fine-tuned on the held-out questions, graded
#        scripts/train-answers.sh dry-run                     every step on fake data: no API key, library or MLX
# The Claude steps need ANTHROPIC_API_KEY and `.venv/bin/pip install -r tools/requirements.txt`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="${PY:-$ROOT/.venv/bin/python}"
TOOLS="$ROOT/tools/train-answers"
OUT="$ROOT/build/train-answers"
BASE_ID="mlx-community/Qwen3.5-4B-MLX-4bit"
REVISION="32f3e8ecf65426fc3306969496342d504bfa13f3"   # as tools/train-answers/train.sh
step() { printf '\n== %s\n' "$*"; }

cmd="${1:-}"; shift || true
case "$cmd" in
  questions)
    "$PY" -I "$TOOLS/gen_questions.py" --out-dir "$OUT" "$@" ;;

  prompts)
    [ $# -ge 1 ] || { echo "Usage: scripts/train-answers.sh prompts <library-folder>" >&2; exit 2; }
    # One run covers both lists. Without --answers the single questions get no answer; conversation turns are
    # always answered by Apple's model, so later turns carry a realistic history.
    QUESTIONS="$OUT/questions.tsv" "$ROOT/scripts/check-answers.sh" "$1" \
      --conversations "$OUT/conversations.tsv" --json "$OUT/prompts.json" ;;

  answers)
    "$PY" -I "$TOOLS/write_answers.py" "$OUT/prompts.json" --out-dir "$OUT/data" "$@" ;;

  train)
    "$TOOLS/train.sh" --data "$OUT/data" --out "$OUT" "$@" ;;

  eval)
    # Same prompts for both models (the held-out records), answered as the app answers, then graded side by side.
    BASE=$("$PY" -I -c "from huggingface_hub import snapshot_download as d; print(d('$BASE_ID', revision='$REVISION'))")
    step "Answering the held-out questions with the base model"
    "$PY" -I "$TOOLS/answer_mlx.py" "$BASE" "$OUT/data/test-records.json" "$OUT/eval/base.json"
    step "Answering them with the fine-tuned model"
    "$PY" -I "$TOOLS/answer_mlx.py" "$OUT/answers" "$OUT/data/test-records.json" "$OUT/eval/tuned.json"
    step "Grading"
    "$PY" -I "$ROOT/tools/grade-answers/grade.py" "$OUT/eval/base.json" "$OUT/eval/tuned.json" \
      --label base --label tuned --out "$OUT/eval" "$@"
    echo "Read $OUT/eval/summary.md" ;;

  dry-run)
    D="$ROOT/build/train-answers-dry-run"
    rm -rf "$D"
    step "questions (fake Claude)"
    "$PY" -I "$TOOLS/gen_questions.py" --out-dir "$D" --n 300 --dry-run | grep -v '^  questions:'
    step "prompts (fake records; the real ones come from scripts/check-answers.sh)"
    "$PY" -I "$TOOLS/fake_records.py" "$D/prompts.json" "$D/questions.tsv" "$D/conversations.tsv"
    step "answers (fake Claude, with the self-check)"
    "$PY" -I "$TOOLS/write_answers.py" "$D/prompts.json" --out-dir "$D/data" --check --test 30 --dry-run \
      | grep -v '^  answers:'
    step "train (data and layout checks only)"
    "$TOOLS/train.sh" --data "$D/data/dry-run" --out "$D" --dry-run
    step "eval (fake answers, fake grades)"
    "$PY" -I "$TOOLS/answer_mlx.py" base "$D/data/dry-run/test-records.json" "$D/eval/base.json" --dry-run | tail -1
    "$PY" -I "$TOOLS/answer_mlx.py" tuned "$D/data/dry-run/test-records.json" "$D/eval/tuned.json" --dry-run | tail -1
    "$PY" -I "$ROOT/tools/grade-answers/grade.py" "$D/eval/base.json" "$D/eval/tuned.json" \
      --label base --label tuned --out "$D/eval" --dry-run | grep -v '^  \(base\|tuned\):'
    step "Dry run passed" ;;

  *)
    sed -n '2,12p' "$0" >&2; exit 2 ;;
esac
