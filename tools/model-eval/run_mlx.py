"""Answer the same prompts Apple's model got (from check-answers --json) with an open model through MLX, and record
speed and memory. Used to decide whether shipping a bigger on-device model is worth its size.

Usage: .venv/bin/python tools/model-eval/run_mlx.py <hf-model-id> <apple-answers.json> <out.json> [--no-library]
--no-library rebuilds each prompt without excerpts, to see what the model knows on its own.
"""
import json
import sys
import time

import mlx.core as mx
from mlx_lm import load, stream_generate
from mlx_lm.sample_utils import make_sampler

model_id, src, out = sys.argv[1:4]
no_library = "--no-library" in sys.argv
records = json.load(open(src))

start = time.time()
model, tok = load(model_id)
load_s = time.time() - start
weights = sum(v.nbytes for _, v in __import__("mlx.utils", fromlist=["tree_flatten"]).tree_flatten(model.parameters()))
sampler = make_sampler(temp=0.3)
results = []
for r in records:
    q = r["question"]
    prompt = (f"Their question: {q}\n\nNo library excerpts matched this question.\n\nNow answer their question: {q}"
              if no_library else r["prompt"])
    messages = [{"role": "system", "content": r["instructions"]}, {"role": "user", "content": prompt}]
    try:  # Qwen 3.x thinks out loud unless told not to; the app wants the answer straight away
        text = tok.apply_chat_template(messages, add_generation_prompt=True, tokenize=False, enable_thinking=False)
    except TypeError:
        text = tok.apply_chat_template(messages, add_generation_prompt=True, tokenize=False)
    mx.reset_peak_memory()
    t0 = time.time()
    first, answer, last = None, "", None
    for resp in stream_generate(model, tok, text, max_tokens=700, sampler=sampler):
        if first is None:
            first = time.time() - t0
        answer += resp.text
        last = resp
    results.append({"question": q, "answer": answer.strip(), "sources": [] if no_library else r["sources"],
                    "first_token_s": first, "total_s": time.time() - t0,
                    "prompt_tokens": last.prompt_tokens, "prompt_tps": last.prompt_tps,
                    "gen_tokens": last.generation_tokens, "gen_tps": last.generation_tps,
                    "peak_gb": mx.get_peak_memory() / 1e9})
    print(f"{q[:60]:60s} {last.generation_tps:5.1f} tok/s  peak {mx.get_peak_memory() / 1e9:.1f} GB", flush=True)
json.dump({"model": model_id, "weights_gb": weights / 1e9, "load_s": load_s, "results": results},
          open(out, "w"), indent=1)
print(f"weights in memory {weights / 1e9:.2f} GB, loaded in {load_s:.0f}s")
