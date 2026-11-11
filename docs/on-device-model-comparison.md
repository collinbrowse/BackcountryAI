# Would a bigger on-device model be worth it?

Tested 2026-11-11 on a Mac (M1 Max, 64 GB). Every model got the same prompts, with the same library excerpts and
the same instructions (`Retrieval.instructions`), for the 16 questions in `library/answer-questions.tsv`. The
excerpts came from the app's retrieval, run with Apple's model (`check-answers.sh --json`). The open models ran
through MLX (`tools/model-eval/run_mlx.py`), 4-bit, with thinking turned off. No cloud models.

## Results

| Model | Answer quality (of 32) | Weights in memory | Peak memory | Mac: words/s* | Phone estimate per answer** | License |
|---|---|---|---|---|---|---|
| Apple Foundation Model (built in) | **9** | 0 (part of iOS) | n/a | n/a | ~4–6 s | Apple |
| Qwen 3.5 2B | not usable (dangerous mistakes) | 1.06 GB | 2.2 GB | 170 | ~10 s | Apache 2.0 |
| Gemma 4 E2B | 18 | 2.60 GB | 3.5 GB | 103 | ~10 s | Gemma terms |
| Qwen 3 4B (2507) | 20 | 2.26 GB | 3.2 GB | 96 | ~20 s | Apache 2.0 |
| Gemma 4 E4B | 22 | 4.20 GB | 5.1 GB | 70 | ~15 s | Gemma terms |
| **Qwen 3.5 4B** | **23** | **2.37 GB** | **3.8 GB** | 93 | **~20–25 s** | Apache 2.0 |
| Qwen 3.5 9B | 25 | 5.04 GB | 6.4 GB | 57 | ~40–50 s | Apache 2.0 |

\* Tokens per second while writing, measured on the Mac.
\*\* Estimated: the Mac speeds scaled down by the iPhone's lower memory bandwidth (about 60–77 GB/s, against the
M1 Max's 400 GB/s), for a ~950-token prompt and the model's typical answer length. Measure on a real iPhone
before deciding.

**How quality was scored:** each answer got 0 (wrong or unsafe), 1 (partly right or vague) or 2 (right, specific
and on the question), across 16 questions, by one reviewer. Treat the gaps as rough, not exact.

## What the answers showed

- **Apple's model** follows the excerpts even when they're about something else, and it fills gaps with confident,
  made-up specifics:
  - the snowmobile answer gave a dipstick and 10W-30;
  - lightning above treeline: "move to a hard-top vehicle";
  - one answer to the mushroom question was the "Not from the library:" heading with nothing after it.
- **Qwen 3.5 4B** was the only model that read "Kathryn be free" as the Katadyn BeFree. It gave correct, specific
  steps for hypothermia, bleeding, lightning above treeline, flash floods, being lost and mushrooms.
  - It still gets gear facts wrong: it said the BeFree doesn't remove bacteria, when it does.
  - It assumes every snowmobile is a four-stroke with a dipstick.
- **Qwen 3.5 9B** is a little better again. It knows to ask whether a snowmobile is two-stroke or four-stroke, and
  it says what it doesn't know. It still gets numbers wrong (FRS power).
- **The Gemma 4 models** are careful but short (100–150 words), and they often just restate the excerpts.
- **Qwen 3.5 2B** made dangerous mistakes: "snowmobiles use snow lubrication" and "turn off the stove" for a
  hypothermic friend.
- **With no library at all,** Qwen 3.5 4B is much better organized than Apple's model, but it still invents
  details. It even cited "[1]" when there were no excerpts. The library is still needed.

## Size: what each option costs on the phone

The deciding factor is memory, more than download size.

| | Download | On the phone | Peak memory while answering | Fits which iPhones |
|---|---|---|---|---|
| Today: Essentials only | 0.81 GB | 1.9 GB | Apple's model is shared with iOS | All Apple Intelligence iPhones (8 GB+) |
| + Qwen 3.5 4B | +2.4 GB (3.2 GB total) | +2.4 GB (4.3 GB total) | about 3.8 GB in the app | 12 GB iPhones; on 8 GB iPhones, only with Apple's increased-memory-limit entitlement, if at all. Must test |
| + Qwen 3.5 9B | +5.0 GB (5.8 GB total) | +5.0 GB (6.9 GB total) | about 6.4 GB in the app | Not realistic: iOS stops apps well before this on 8 GB phones, and it's risky even on 12 GB |
| + Gemma 4 E4B | +4.2 GB | +4.2 GB | about 5.1 GB | Same problem as the 9B |

Notes:
- **Text-only size.** The Qwen 3.5 files on Hugging Face include image weights (3.0 GB for the 4B). The app would
  ship only the text model, 2.37 GB. Model weights don't compress, so download size is about the same as the
  size on the phone.
- **Delivery.** The model would ship as a second Apple-hosted asset pack, like the library, so the app itself
  stays small and people choose whether to download it.
- **Speed.** Apple's model answers in a few seconds. Qwen 3.5 4B would take roughly 20–25 seconds on a recent
  iPhone, including about 5 seconds of reading the prompt before the first word appears. It streams, so words
  appear as they're written, but it's still noticeably slower.
- **Battery.** MLX runs on the GPU, while Apple's model uses the more efficient Neural Engine, so expect several
  times the battery cost per answer. Rough guess: about 0.2–0.4% of the battery per answer, against under 0.1%.
  The app's battery meter would show the real number.
- **Software support.** MLX Swift (`mlx-swift-lm`) already supports Qwen 3.5 (`Qwen35.swift`) and Gemma 4, so
  the app could run these models without new low-level code.

## Recommendation

Qwen 3.5 4B is the only option that's both much better and could plausibly fit on a phone. It scored 23 of 32 on
this set against Apple's 9. The 9B is only slightly better and can't fit. The 2B isn't safe.

Ship it, if at all, as an **optional "Better answers" download** (about 2.4 GB) for iPhones with enough memory:

- Apple's model stays the default. It keeps doing the fast steps (planning searches and checking excerpts), so
  only the final answer waits on Qwen.
- Phones without the download, or without enough memory, keep today's behavior.

Before committing, build a small prototype and measure on a real 8 GB iPhone and a 12 GB iPhone:

- time to the first word and the total answer time;
- peak memory (and whether iOS kills the app);
- battery per answer.

Those numbers decide it. The answer quality is already clear.

## Reproduce

```bash
QUESTIONS=library/answer-questions.tsv scripts/check-answers.sh <library> --answers --json build/model-eval/apple.json
.venv/bin/pip install mlx-lm
.venv/bin/python tools/model-eval/run_mlx.py mlx-community/Qwen3.5-4B-MLX-4bit build/model-eval/apple.json build/model-eval/qwen35-4b.json
```

Add `--no-library` to `run_mlx.py` to see what a model knows without excerpts.
