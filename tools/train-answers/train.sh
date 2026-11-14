#!/bin/bash
# Fine-tunes the "Better answers" model (Qwen 3.5 4B, 4-bit MLX, the revision the app ships) on the reference answers
# from write_answers.py with LoRA on this Mac, fuses the adapter into the 4-bit weights, and lays the result out like
# the Hugging Face download scripts/release-model-pack.sh packages:
#   check data -> LoRA (mlx_lm lora) -> fuse (mlx_lm fuse) -> <out>/model (release input) -> <out>/answers (stripped)
#
# Usage: tools/train-answers/train.sh [--data DIR] [--out DIR] [--epochs 2] [--iters N] [--lr 1e-5] [--layers 16]
#                                     [--rank 8] [--dry-run]
# --iters overrides the epoch count: `--iters 20` is a cheap timing run before committing to the full one.
# Needs mlx-lm in the project venv (.venv/bin/pip install -r tools/requirements.txt) and an Apple-silicon Mac with
# about 16 GB of free memory. --dry-run only checks the data and the pack layout code, without mlx-lm.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PY="${PY:-$ROOT/.venv/bin/python}"
MODEL="mlx-community/Qwen3.5-4B-MLX-4bit"                # must match BetterModel.modelID
REVISION="32f3e8ecf65426fc3306969496342d504bfa13f3"      # must match scripts/release-model-pack.sh
DATA="$ROOT/build/train-answers/data"
OUT="$ROOT/build/train-answers"
EPOCHS=2 ITERS="" LR=1e-5 LAYERS=16 RANK=8 BATCH=4 MAX_SEQ=4096 DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --data) DATA="$2"; shift ;;
    --out) OUT="$2"; shift ;;
    --epochs) EPOCHS="$2"; shift ;;
    --iters) ITERS="$2"; shift ;;
    --lr) LR="$2"; shift ;;
    --layers) LAYERS="$2"; shift ;;
    --rank) RANK="$2"; shift ;;
    --dry-run) DRY=1 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
step() { printf '\n== %s\n' "$*"; }

step "Checking the training data in $DATA"
"$PY" -I "$ROOT/tools/train-answers/check_data.py" "$DATA" --max-seq "$MAX_SEQ"
TRAIN=$(grep -c . "$DATA/train.jsonl")
if [ -z "$ITERS" ]; then
  ITERS=$(( (TRAIN * EPOCHS + BATCH - 1) / BATCH ))
  echo "$TRAIN training examples x $EPOCHS epochs / batch $BATCH = $ITERS iterations"
fi

# Small-data defaults: LoRA rank 8 on the last 16 of 32 blocks (mlx-lm picks every linear layer in them: attention,
# the Gated DeltaNet projections and the MLP), mlx-lm's default learning rate, a little dropout, and loss on the
# answers only (mask_prompt), since the prompts are long and the model should learn to answer, not to echo them.
# Gradient checkpointing keeps long prompts (library excerpts) inside a 16-24 GB Mac's memory.
mkdir -p "$OUT"
CONFIG="$OUT/lora.yaml"
cat > "$CONFIG" <<YAML
model: "BASE_DIR"
train: true
test: true
data: "$DATA"
adapter_path: "$OUT/adapters"
fine_tune_type: lora
num_layers: $LAYERS
batch_size: $BATCH
iters: $ITERS
learning_rate: $LR
val_batches: -1
test_batches: -1
steps_per_report: 10
steps_per_eval: 50
save_every: 100
max_seq_length: $MAX_SEQ
grad_checkpoint: true
mask_prompt: true
seed: 0
lora_parameters:
  rank: $RANK
  scale: 20.0
  dropout: 0.05
YAML

if [ "$DRY" = 1 ]; then
  step "Dry run: checking the pack layout code"
  "$PY" -I "$ROOT/tools/train-answers/pack_layout.py" --self-test
  echo "Would train with $CONFIG:"
  sed 's/^/    /' "$CONFIG"
  echo "then: mlx_lm fuse -> pack_layout.py -> strip_vision_weights.py -> $OUT/model and $OUT/answers"
  exit 0
fi

"$PY" -I -c "import mlx_lm" 2>/dev/null || { echo "mlx-lm isn't installed: .venv/bin/pip install -r tools/requirements.txt" >&2; exit 1; }

step "Getting $MODEL at $REVISION"
# mlx-lm loads this 4-bit checkpoint as text-only (it drops the vision tower and keeps the quantized layers), and
# LoRA on quantized layers is QLoRA: the 4-bit weights stay frozen and the adapters train in 16-bit.
BASE=$("$PY" -I -c "from huggingface_hub import snapshot_download as d; print(d('$MODEL', revision='$REVISION'))")
sed -i '' "s#BASE_DIR#$BASE#" "$CONFIG"

step "Checking the chat template"
# The app asks with enable_thinking=false; training must see the same tokens before the answer.
"$PY" -I "$ROOT/tools/train-answers/check_data.py" "$DATA" --max-seq "$MAX_SEQ" --template "$BASE"

step "Training the LoRA adapter ($ITERS iterations)"
# In training mode mlx-lm runs Qwen 3.5's 24 Gated DeltaNet layers with its differentiable reference code, a loop
# over every token (the fast Metal kernel has no gradient), so expect this to be much slower per token than
# generation. Time a short run with --iters 20 first.
"$PY" -I -m mlx_lm lora -c "$CONFIG" 2>&1 | tee "$OUT/train.log"

step "Fusing the adapter into the 4-bit weights"
# Fusing dequantizes each adapted layer, adds the LoRA delta and quantizes it again (4-bit, group size 64), so the
# fused model is the same size and format as the one the app ships.
rm -rf "$OUT/fused"
"$PY" -I -m mlx_lm fuse --model "$BASE" --adapter-path "$OUT/adapters" --save-path "$OUT/fused"

step "Laying it out like the release download"
"$PY" -I "$ROOT/tools/train-answers/pack_layout.py" "$OUT/fused" "$BASE" "$OUT/model"
rm -rf "$OUT/answers"
"$PY" -I "$ROOT/tools/strip_vision_weights.py" "$OUT/model" "$OUT/answers"

step "Done"
echo "Fine-tuned model: $OUT/answers (what the asset pack holds). Next:"
echo "  scripts/train-answers.sh eval                      # grade base vs fine-tuned on the held-out questions"
echo "  scripts/release-model-pack.sh --model-dir $OUT/model --no-upload   # build answers.aar from it"
