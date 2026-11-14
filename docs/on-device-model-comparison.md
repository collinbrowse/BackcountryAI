# Would a bigger on-device model be worth it?

**Decision:** ship Qwen 3.5 4B as an optional "Better answers" download (2.3 GB). It scored 23 of 32 against
Apple's 9, and it passed on an 8 GB iPhone (see "On a real iPhone" below).

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

## On a real iPhone

Measured 2026-11-12 on an 8 GB iPhone with the app's benchmark, after the answer prompt was tightened. Medians over
the 16 questions:

| | Apple's model | Qwen 3.5 4B |
|---|---|---|
| First words | 1.6 s | 3.3 s |
| Full answer | 3.5 s | 9.9 s (worst 14.9 s) |
| Answer length | 114 tokens | 131 tokens |
| Writing speed | 60 tokens/s | 19 tokens/s |
| Peak app memory | 2.72 GB | 3.52 GB |
| Lowest free memory | 3.72 GB | 2.93 GB |

It passed all three ship criteria: free memory stayed far above ~0.5 GB, the first word came within ~5 s, and a full
answer took under ~30 s. Heat reached "serious" by the end of the 16-answer run, so it's worth re-checking during long
sessions.

## The engine, measured again

Measured 2026-11-13 on an iPhone 17 (8 GB, iOS 27.2.1) after the answers moved behind `LLMEngine` (MLX Swift through
mlx-swift-lm 3.32.3). The numbers come from `ShippedModelBenchmark`: six questions, each with four 700-character
excerpts, which is the size of prompt Scout sends.

**What iOS allows the app:** the phone reports 7,672 MiB of memory and, with the Increased Memory Limit
entitlement, lets the app hold 6,144 MiB. The app logs this at every launch (`memory at launch`).

| Qwen 3.5 4B, 4-bit, MLX | iPhone 17 |
|---|---|
| Load and warm-up | 3.1 s |
| First token (1,206-token prompt) | 3.0–3.6 s |
| Reading the prompt | about 410 tokens/s |
| Writing speed | 22.2 tokens/s |
| Full answer (100–117 tokens) | 8.0–9.1 s (worst 10.7 s) |
| Peak app memory | 3.48–3.65 GB |
| Lowest free memory | 2.79 GB |
| Heat after six answers | nominal to fair |

The ranges are the medians of two runs. The higher memory figure is from a run that had also loaded the 335 MB
test model.

**What that means for model size on an 8 GB iPhone:** a model may use about 6.1 GB less what the rest of the
app needs. Qwen 3.5 4B leaves 2.8 GB free. A 9B model at 4 bits (about 5 GB of text weights plus working
memory) does not fit. 12 GB iPhones are untested.

**How the app stays inside the limit:**

- Before loading, `MemoryBudget` checks that the weights, 900 MB of working room and a 300 MB reserve fit in what
  iOS says is free. If they don't, Apple's model answers and the next question tries again.
- `GenerationConfig.contextTokens` (4,096) caps both the prompt and the key-value cache.
- The model unloads, stopping any answer first, when the app leaves the foreground, on a memory warning and when
  the phone is critically hot. At a "serious" thermal state answers are capped at 400 tokens.
- MLX holds the weights in memory whole; it does not memory-map them.

**Tests:** `MLXEngineDeviceTests` runs the real engine with Qwen3 0.6B (335 MB) and `ShippedModelBenchmark`
measures the shipped model. Both need a connected iPhone and are skipped in the simulator and CI:

```bash
xcodebuild test -project BackcountryAI.xcodeproj -scheme BackcountryAI -destination "platform=iOS,name=<your iPhone>" -skipMacroValidation -only-testing:BackcountryAITests/MLXEngineDeviceTests -only-testing:BackcountryAITests/ShippedModelBenchmark
```

Debug builds print the `[llm]` log lines; in other builds they are in Console under the `llm` category.

## In the app: Better answers

**Library › Better answers** offers it as an optional download on iPhones with 8 GB or more:

- **Download better answers** gets the `answers` asset pack (2.3 GB). Then a **Faster / Better** switch chooses
  which model writes Scout's answers; Better is on once the download finishes.
- **How it works** holds the technical details: how the two models split the work, the measurements above, the
  model and its Apache 2.0 license, this iPhone's memory, and the benchmark (both models answer the 16 questions
  and the results export as CSV and text).
- Once the library is in, the Scout home screen shows a "Want more accurate answers?" tip until the model is
  downloaded or the tip is dismissed.
- The model loads when Scout opens and unloads when the app goes to the background or memory runs low. If it can't
  load, Apple's model answers instead. Answers it wrote show a sparkle by the battery figure.

**Delivery:** `scripts/release-model-pack.sh` downloads the pinned Hugging Face revision, drops the image weights
(`tools/strip_vision_weights.py`; MLXLLM ignores them anyway), and builds and uploads `answers.aar`. See
`docs/library-hosting.md`. Until that pack is on App Store Connect, Xcode builds download the same model from
Hugging Face instead; TestFlight and App Store builds say it isn't available yet.

## Reproduce the Mac comparison

```bash
QUESTIONS=library/answer-questions.tsv scripts/check-answers.sh <library> --answers --json build/model-eval/apple.json
.venv/bin/pip install mlx-lm
.venv/bin/python tools/model-eval/run_mlx.py mlx-community/Qwen3.5-4B-MLX-4bit build/model-eval/apple.json build/model-eval/qwen35-4b.json
```

Add `--no-library` to `run_mlx.py` to see what a model knows without excerpts.
