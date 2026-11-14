"""Answers check-answers records with a Qwen model through MLX on this Mac, the way the app's BetterModel does
(system = instructions, user = prompt, thinking off, temperature 0.3, top-p 0.95, at most 700 tokens), and writes
them back as records the grader reads. Used to compare the base model with the fine-tuned one.

Usage: .venv/bin/python -I tools/train-answers/answer_mlx.py <model-dir-or-id> <records.json> <out.json> [--dry-run]
--dry-run writes canned answers without loading MLX.
"""
import json
import sys
import time
from pathlib import Path


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 3:
        sys.exit(__doc__)
    model_path, src, out = args
    records = json.loads(Path(src).read_text())
    if "--dry-run" in sys.argv:
        answer = lambda r: f"Fake answer from {Path(model_path).name} [1].\n1. Fake step."  # noqa: E731
    else:
        from mlx_lm import load, generate
        from mlx_lm.sample_utils import make_sampler

        model, tok = load(model_path)
        sampler = make_sampler(temp=0.3, top_p=0.95)  # BetterModel's GenerateParameters

        def answer(r):
            messages = [{"role": "system", "content": r["instructions"]}, {"role": "user", "content": r["prompt"]}]
            text = tok.apply_chat_template(messages, add_generation_prompt=True, tokenize=False, enable_thinking=False)
            return generate(model, tok, text, max_tokens=700, sampler=sampler).strip()

    results = []
    for i, r in enumerate(records, 1):
        t0 = time.time()
        a = answer(r)
        results.append({**r, "answer": a, "engine": "qwen", "model": model_path, "seconds": time.time() - t0})
        print(f"{i}/{len(records)} {time.time() - t0:5.1f}s  {r['question'][:70]}", flush=True)
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out).write_text(json.dumps(results, indent=1))
    print(f"Wrote {len(results)} answers to {out}")


if __name__ == "__main__":
    main()
