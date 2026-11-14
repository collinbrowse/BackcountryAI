"""Checks a training data folder before mlx_lm.lora sees it: every line is {"messages": [system, user, assistant]}
with non-empty text, answers pass the app's format checks, no held-out question leaks into train or valid, and no
example is likely to be cut off at --max-seq tokens. Exits non-zero if anything is wrong.

With --template MODEL_DIR it also renders one example with the model's real chat template (needs mlx-lm's
dependencies, so not in --dry-run) and checks that the assistant turn the model trains on is exactly what it is
asked for at answer time: the app renders the prompt with enable_thinking=false, which ends in an empty
<think></think> block, and Qwen's template renders a final assistant message with that same empty block.

Usage: .venv/bin/python -I tools/train-answers/check_data.py <data-folder> [--max-seq 4096] [--template MODEL_DIR]
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from write_answers import format_problem, norm  # noqa: E402

CHARS_PER_TOKEN = 3.2  # conservative for English with Qwen's tokenizer; real counts are usually lower


def load(path: Path) -> list:
    rows = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if line.strip():
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as e:
                rows.append({"_error": f"line {n}: {e}"})
    return rows


def check(data: Path, max_seq: int) -> list:
    errors = []
    splits = {name: load(data / f"{name}.jsonl") for name in ("train", "valid", "test")}
    for name in ("train", "valid"):
        if not splits[name]:
            errors.append(f"{name}.jsonl is missing or empty")
    questions, prompts = {}, []
    for name, rows in splits.items():
        long = 0
        for i, row in enumerate(rows, 1):
            where = f"{name}.jsonl:{i}"
            if "_error" in row:
                errors.append(f"{where}: not JSON ({row['_error']})")
                continue
            msgs = row.get("messages")
            if not isinstance(msgs, list) or [m.get("role") for m in msgs] != ["system", "user", "assistant"]:
                errors.append(f"{where}: messages must be system, user, assistant")
                continue
            if set(row) != {"messages"} or any(set(m) != {"role", "content"} for m in msgs):
                errors.append(f"{where}: unexpected keys")
            if any(not isinstance(m["content"], str) or not m["content"].strip() for m in msgs):
                errors.append(f"{where}: empty content")
                continue
            if problem := format_problem(msgs[2]["content"], msgs[1]["content"]):
                errors.append(f"{where}: answer format: {problem}")
            if sum(len(m["content"]) for m in msgs) / CHARS_PER_TOKEN > max_seq:
                long += 1
            prompts.append(msgs[1]["content"])
            q = msgs[1]["content"].rsplit("Now answer their question:", 1)[-1]
            questions.setdefault(name, set()).add(norm(q))
        if long:
            errors.append(f"{name}: {long} examples may be longer than {max_seq} tokens and would be cut off")
        lens = sorted(len(r["messages"][-1]["content"]) for r in rows if len(r.get("messages") or []) == 3)
        if lens:
            print(f"{name}: {len(rows)} examples; answer length median {lens[len(lens) // 2]} chars, "
                  f"max {lens[-1]}")
    test_q = questions.get("test", set())
    for name in ("train", "valid"):
        if leaked := questions.get(name, set()) & test_q:
            errors.append(f"{len(leaked)} test questions also appear in {name}")
    if len(prompts) != len(set(prompts)):
        errors.append(f"{len(prompts) - len(set(prompts))} duplicate prompts across the splits")
    return errors


def check_template(model_dir: str, data: Path) -> list:
    from transformers import AutoTokenizer  # installed with mlx-lm

    tok = AutoTokenizer.from_pretrained(model_dir)
    row = load(data / "train.jsonl")[0]
    msgs = row["messages"]
    trained = tok.apply_chat_template(msgs, tokenize=False)  # what mlx-lm's ChatDataset renders
    asked = tok.apply_chat_template(msgs[:2], tokenize=False, add_generation_prompt=True, enable_thinking=False)
    want = asked + msgs[2]["content"] + "<|im_end|>\n"
    if trained != want:
        return ["chat template: the training text doesn't match the app's prompt + answer.\n"
                f"  trained ends: {trained[-200:]!r}\n  app would see: {want[-200:]!r}"]
    print("chat template: training text = app prompt (enable_thinking=false) + answer + <|im_end|>")
    return []


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("data")
    ap.add_argument("--max-seq", type=int, default=4096)
    ap.add_argument("--template", help="model folder whose chat template to check against")
    args = ap.parse_args()
    data = Path(args.data)
    errors = check(data, args.max_seq)
    if args.template and not errors:
        errors += check_template(args.template, data)
    for e in errors[:30]:
        print("ERROR " + e, file=sys.stderr)
    if errors:
        sys.exit(f"{len(errors)} problems in {data}")
    print(f"{data}: OK")


if __name__ == "__main__":
    main()
