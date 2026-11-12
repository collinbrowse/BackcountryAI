# Would a bigger on-device model be worth it?

**Recommendation:** Qwen 3.5 4B, as an optional "Better answers" download of about 2.4 GB. It scored 23 of 32
against Apple's 9. Ship it only if it passes on a real iPhone (see "Prototype" below).

## Results

**Setup:** tested 2026-11-11 on an M1 Max Mac. Every model got the same 16 questions
(`library/answer-questions.tsv`), with the same library excerpts and instructions. The open models ran 4-bit
through MLX, with thinking off.

**Scoring:** each answer got 0 (wrong or unsafe), 1 (vague) or 2 (right and specific), from one reviewer.

| Model | Quality (of 32) | Weights | Peak memory | Phone estimate per answer* | License |
|---|---|---|---|---|---|
| Apple Foundation Model | 9 | part of iOS | n/a | ~4–6 s | Apple |
| Qwen 3.5 2B | unsafe | 1.06 GB | 2.2 GB | ~10 s | Apache 2.0 |
| Gemma 4 E2B | 18 | 2.60 GB | 3.5 GB | ~10 s | Gemma terms |
| Qwen 3 4B (2507) | 20 | 2.26 GB | 3.2 GB | ~20 s | Apache 2.0 |
| Gemma 4 E4B | 22 | 4.20 GB | 5.1 GB | ~15 s | Gemma terms |
| **Qwen 3.5 4B** | **23** | **2.37 GB** | **3.8 GB** | **~20–25 s** | Apache 2.0 |
| Qwen 3.5 9B | 25 | 5.04 GB | 6.4 GB | ~40–50 s | Apache 2.0 |

\* Estimated by scaling the Mac speeds down to the iPhone's memory bandwidth. The prototype measures the real figure.

**What the answers showed:**

- **Apple's model** follows the excerpts even when they're off-topic, and it invents specifics. For example, it
  gave a dipstick and 10W-30 oil for a snowmobile.
- **Qwen 3.5 4B** was the only model that read "Kathryn be free" as the Katadyn BeFree water filter. Its steps for
  hypothermia, bleeding, lightning, flash floods, being lost and mushrooms were right. It still gets some gear
  facts wrong.
- **Qwen 3.5 9B** is a little better, but it can't fit on a phone.
- **Qwen 3.5 2B** made dangerous mistakes.
- **Without the library,** every model invents details. The library is still needed.

## Size on the phone

The deciding factor is memory, not download size.

| Option | Extra download and storage | Peak memory in the app | Fits |
|---|---|---|---|
| Today: Apple's model only | none | shared with iOS | every Apple Intelligence iPhone |
| + Qwen 3.5 4B | +2.4 GB | ~3.8 GB | 12 GB iPhones; 8 GB iPhones only with the Increased Memory Limit entitlement, if at all |
| + Qwen 3.5 9B or Gemma 4 E4B | +4–5 GB | 5–6.4 GB | not realistic |

**Notes:**

- **Size:** weights don't compress, so the download is about the size on the phone.
- **Delivery:** a shipped model would be a second Apple-hosted asset pack, released like the library, with only
  the text weights. The prototype's Hugging Face download is about 3 GB because it includes image weights.
- **Battery:** MLX runs on the GPU, so expect several times the battery per answer that Apple's model uses.
- **How it would work:** Apple's model keeps planning the searches and checking the excerpts. Only the final
  answer waits on Qwen.

## Prototype: measure it on a real iPhone

**Library › Lab: better answers (prototype)** does three things:

- downloads Qwen 3.5 4B from Hugging Face. This works in Xcode builds.
- can let Qwen write Scout's answers. Each answer's battery popover then shows its speed and memory use.
- runs a **benchmark**: both models answer the 16 questions. It records time to the first word, total time,
  words per second, peak and free memory, battery and heat, and exports a CSV.

**To run it:**

1. In Xcode, check that Signing & Capabilities has **Increased Memory Limit**, then build to a real iPhone. MLX
   doesn't run in the simulator.
2. Copy the library to the phone (see `docs/library-hosting.md`, "Testing on a phone").
3. In the app, open Lab and tap Download and load, on Wi-Fi.
4. Unplug the phone and tap **Run benchmark**. It takes 5–15 minutes; keep the screen on.
5. Share the CSV. Repeat on an 8 GB iPhone if you can.

**Ship it if:**

- free memory stays above ~0.5 GB, and iOS never stops the app;
- the first word appears within ~5 s;
- a full answer takes under ~30 s.

## Reproduce the Mac comparison

```bash
QUESTIONS=library/answer-questions.tsv scripts/check-answers.sh <library> --answers --json build/model-eval/apple.json
.venv/bin/pip install mlx-lm
.venv/bin/python tools/model-eval/run_mlx.py mlx-community/Qwen3.5-4B-MLX-4bit build/model-eval/apple.json build/model-eval/qwen35-4b.json
```

Add `--no-library` to `run_mlx.py` to see what a model knows without excerpts.
