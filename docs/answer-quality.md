# Answer quality: grading answers and fine-tuning Better answers

Two workflows that use Claude (`claude-opus-5-5`) on a Mac:

1. **Grading** scores Scout's answers against a rubric built around the app's known failure modes, and compares two
   runs (Apple vs Qwen, or before vs after a prompt change).
2. **Fine-tuning** has Claude write the ideal answer to the app's own prompts, then trains a LoRA for the Better
   answers model (Qwen 3.5 4B) on them and packs the result like the stock model.

Both need an API key in `ANTHROPIC_API_KEY` and the packages in `tools/requirements.txt`:

```bash
.venv/bin/pip install -r tools/requirements.txt   # anthropic, and mlx-lm for training
```

Every script has a dry run that runs everything except the network, the library and MLX:
`scripts/grade-answers.sh dry-run` and `scripts/train-answers.sh dry-run`.

## 0. How an answer is found

1. **Plan** (Apple's model): what kind of question it is (how-to, troubleshooting, fact, or small talk) and two or
   three keyword searches.
2. **Search**: keyword search (SQLite FTS5) for the question and each planned search, plus meaning-based search
   over `vectors.bin`, fused by rank. A follow-up is searched together with the question before it.
3. **Rerank**: a reranker scores each of the ten candidates from 0 to 1; those under
   `Retrieval.minimumRelevance` are dropped. With nothing left, the answer model answers from what it knows.
4. **Answer** (PR 9's `LLMEngine`: Apple's model or the better-answers model): the prompt keeps the person's words
   and the library's articles in separate labelled blocks. Troubleshooting answers list checks in order and end
   with one question; its options become tap-to-answer chips.

Steps 2 and 3 need two small models and the vectors inside the library folder. `scripts/embed-library.sh <library>`
adds them (and `scripts/release-pack.sh` runs it when `vectors.bin` is missing):

| File | What | Size |
|---|---|---|
| `models/embedder` | bge-small-en-v1.5 (MIT) | 134 MB |
| `models/reranker` | Qwen3-Reranker-0.6B, full precision (Apache 2.0) | 1.2 GB |
| `vectors.bin` | one 384-bit vector per passage | about 65 MB for Essentials |

**The reranker is not in the released pack yet.** On the full Essentials library (89 questions in
`library/questions.tsv`, 2026-11-14):

| Setup | Found a relevant article | Checking the articles |
|---|---|---|
| Keyword search alone | 86 | n/a |
| Meaning search + Apple's yes/no check | 87 | about 7.6 s |
| Meaning search + reranker | 86 | about 0.5 s |

The difference is within run-to-run noise, but the reranker dropped "Eye Injury" (0.02) and "Corneal abrasion"
(0.00) for "I got something in my eye", which Apple's check kept. Until that's understood it isn't worth 1.2 GB of
download, so the released pack has the embedder and vectors only: remove `models/reranker` from the library folder
before `scripts/release-pack.sh`. The app uses a reranker whenever the library has one. The 0.3 cutoff sits in a
clear valley (292 scores near 0, 402 above 0.9, few between). The 4-bit copy (350 MB) scored worse still: 0.09 for
a passage the full-precision model gives 0.92. `scout-tools rerank <model> <query> <doc>…` compares rerankers.

On the phone the reranker loads only when there is memory for it and for the answer model (`MemoryBudget`);
otherwise Apple's model checks the excerpts. Not yet measured on an iPhone: meaning search's load time and time
per question.

A library without these files, and the simulator, use keyword search and Apple's model alone.

## 1. Grading answers

Make one run per model with the app's real retrieval, then grade them together:

```bash
QUESTIONS=library/answer-questions.tsv scripts/check-answers.sh <library> --answers \
  --conversations library/conversations.tsv --json build/grade-answers/apple.json
QUESTIONS=library/answer-questions.tsv scripts/check-answers.sh <library> --answers --qwen \
  --conversations library/conversations.tsv --json build/grade-answers/qwen.json
scripts/grade-answers.sh build/grade-answers/apple.json build/grade-answers/qwen.json --label apple --label qwen
```

Read `build/grade-answers/summary.md`. It has averages by criterion, area and kind, the 10 worst answers with the
grader's one-line reason, and, for two runs, a side-by-side table with the biggest gains and drops. Each run's
grades are in `build/grade-answers/<label>.json`. Try `--limit 10` first.

`library/conversations.tsv` holds 15 two- and three-turn conversations aimed at the follow-up failures: lost and
"I don't have a map", a snowmobile that "cranks but won't catch", a stove after "I already cleaned the jet", no
jump pack, no bear canister, a live-forecast request, and so on.

**The rubric** (`tools/grade-answers/grade.py`) scores 1–5 on each of:

| Criterion | What fails it |
|---|---|
| answers latest question | answering an earlier turn, a generic question, or an excerpt's topic |
| no repeating | re-giving earlier steps in a follow-up (n/a on a first question) |
| respects "I don't have" | suggesting something they lack, can't do or already tried (n/a if they named none) |
| their situation | treating excerpt content as theirs ("you have a choke lever, a fuel kit…") |
| check order | troubleshooting that doesn't start with the cheapest, most likely check (n/a otherwise) |
| concrete and correct | vague filler, wrong or invented specifics |
| citations | citing excerpts that don't fit or don't say it; "Not from the library:" misuse (n/a without excerpts) |
| safety | 911/SOS outside a real emergency, missing it in one, or dangerous advice |
| format | not one opening sentence, more than five steps, multi-sentence steps, a closing note, markdown |

plus an overall score and a one-line reason. A "not applicable" criterion is scored 0 and left out of averages.
Grades come back as JSON through structured outputs, so there is nothing to parse by hand. If you change the
rubric, bump `RUBRIC_VERSION` so cached grades from the old one aren't reused.

**How it calls Claude:** the rubric and the app's instructions are marked for prompt caching, so after the first
request each answer pays full price only for its own prompt and answer. Four requests run at once (`--concurrency`).
Grades are cached in `build/grade-answers/cache.jsonl`, so a rerun or a crash halfway only pays for new answers.
Requests opt into server-side fallback (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`): if Opus's
safety classifier declines a question about, say, a gunshot wound, the API reruns it on Anthropic's recommended
fallback model instead of failing. A request that is still declined is counted as failed and reported.

## 2. Fine-tuning Better answers

The idea: the app's prompts are fixed by its own retrieval, so the most useful training data is the exact prompt
the app builds, paired with the answer Scout should have given. Claude writes those answers; LoRA teaches them to
Qwen 3.5 4B.

```bash
scripts/train-answers.sh questions --n 1500          # a. Claude writes questions -> build/train-answers/*.tsv
scripts/train-answers.sh prompts <library>           # b. the app's retrieval builds each prompt
scripts/train-answers.sh answers --check             # c. Claude writes and checks answers -> data/*.jsonl
scripts/train-answers.sh train                       # d. LoRA, fuse, lay out like the release download
scripts/train-answers.sh eval                        # e. base vs fine-tuned on held-out questions, graded
scripts/release-model-pack.sh --model-dir build/train-answers/model --no-upload   # then answers.aar
```

**a. Questions** (`tools/train-answers/gen_questions.py`): about 100 requests, each asking for 20 single questions
or 6 conversations in one area and a few subtopics, in assigned styles: clear, vague, dictated (misheard brand
names), troubleshooting, "I don't have X", emergencies and plain facts. Areas are weighted toward first aid,
lost/navigation, vehicles and gear. Near-duplicates are dropped, and so is anything matching the hand-written
test lists in `library/`, so the evals stay honest. Writes `questions.tsv`, `conversations.tsv` and
`questions-meta.jsonl` (kind and style of each).

**b. Prompts**: the step runs exactly

```bash
QUESTIONS=build/train-answers/questions.tsv scripts/check-answers.sh <library> \
  --conversations build/train-answers/conversations.tsv --json build/train-answers/prompts.json
```

Without `--answers`, single questions get only a prompt. Conversation turns are always answered by Apple's model
so that later turns carry a realistic history, which is also what Qwen sees in the app.

**c. Answers** (`write_answers.py`): for each record, the system prompt is a short brief for Claude plus the app's
exact instructions, and the user message is the exact prompt. The brief stresses the app's failure modes and that
a 4B model will learn its length from these answers. Each answer then passes mechanical format checks (opening
sentence, at most five numbered steps, nothing after the last step, the troubleshooting "Ask:" line when the
prompt asks for one). With `--check`, each answer is also graded with the rubric above and dropped unless overall
and safety are at least 4 and no criterion is below 3. Output is mlx-lm chat format
(`{"messages": [system, user, assistant]}`): `train.jsonl`, `valid.jsonl` (5%), and a held-out `test.jsonl`
plus `test-records.json` (100 records by default). The split keeps every turn of a conversation on the same side,
and no test question appears in train or valid. Answers are cached in `data/answers.jsonl`.

**d. Training** (`tools/train-answers/train.sh`):

- Checks the data (`check_data.py`), then renders one example with the model's real chat template. It confirms that
  the training text is exactly what the app sends with `enable_thinking: false` plus the answer: Qwen's template
  renders a final assistant turn with the same empty `<think></think>` block the app's prompt ends in. So no
  template changes are needed. This check passed against the pinned tokenizer.
- LoRA with `python -m mlx_lm lora` on the pinned revision (`32f3e8e…`, the same one `release-model-pack.sh`
  ships): rank 8, scale 20, dropout 0.05, the last 16 of 32 blocks, batch 4, learning rate 1e-5, 2 epochs (about
  650 iterations for 1,300 examples), max 4,096 tokens, gradient checkpointing, and loss on the answer only
  (`mask_prompt`). The config is written to `build/train-answers/lora.yaml`.
- `python -m mlx_lm fuse` merges the adapter into the 4-bit weights. It dequantizes each adapted layer, adds the
  LoRA delta and quantizes again with the same 4-bit, group-size-64 settings, so the size and format are
  unchanged.
- `pack_layout.py` checks that the fused weights have exactly the stock model's text tensors (same names, shapes
  and dtypes). It then copies the stock `config.json`, tokenizer and chat template, because `mlx_lm fuse`
  rewrites the config without `vision_config` and re-saves the tokenizer. It also adds a line to the README
  saying the weights were modified, as Apache 2.0 asks. The result, `build/train-answers/model`, is laid out
  like the Hugging Face download, and `build/train-answers/answers` is that folder run through
  `strip_vision_weights.py`: what the asset pack holds.

**Does mlx-lm support this model?** Yes, as far as reading the code can tell. Running it is the real test. The
model's `config.json` says `model_type: qwen3_5` (`Qwen3_5ForConditionalGeneration`, 4-bit affine, group size 64),
a hybrid of 8 full-attention and 24 Gated DeltaNet (linear-attention) blocks. mlx-lm 0.32.2 (pinned in
`tools/requirements.txt`) has `models/qwen3_5.py`. It loads this checkpoint text-only: it skips the
vision tower and the multi-token-prediction weights and keeps the `language_model.model.*` names the app's
MLXLLM loader reads. Its LoRA wraps quantized layers directly. That is QLoRA: the 4-bit base stays frozen and
only the 16-bit adapters train, so no special handling is needed beyond what `mlx_lm lora` does. Adapters go
on the attention projections, the DeltaNet `in_proj_*`/`out_proj` and the MLPs, but not on the DeltaNet conv.
Not verified:

- **Speed.** In training mode, mlx-lm runs the DeltaNet layers with a differentiable reference loop over every
  token, because the fast Metal kernel has no gradient. With prompts of 1,500–3,000 tokens, training could be
  much slower than the usual mlx-lm LoRA numbers. Time `scripts/train-answers.sh train --iters 20` first.
- **Memory** on a 16 GB Mac at 4,096 tokens. If it runs out, lower `MAX_SEQ` in `train.sh` (check_data warns
  about examples that would be cut) or train fewer layers (`--layers 8`).
- **Whether the app loads the fused pack.** Do this before releasing: `scripts/check-answers.sh <library>
  --answers --qwen build/train-answers/answers --only blister` loads it with the app's own MLX code.

**e. Eval:** `scripts/train-answers.sh eval` answers the held-out records with the base model and the
fine-tuned one the way the app does (thinking off, temperature 0.3, top-p 0.95, 700 tokens; `answer_mlx.py`).
Both get the identical stored prompts, so only the model differs. It then grades both runs with the rubric into
`build/train-answers/eval/summary.md`. Ship the fine-tune only if it beats the base model overall and doesn't
lose on safety. Also grade it on the hand-written lists, `answer-questions.tsv` plus `conversations.tsv`, as in
part 1, since none of those were in training.

**Releasing:** `scripts/release-model-pack.sh --model-dir build/train-answers/model` packages the local folder
instead of downloading the pinned revision. Everything else is unchanged. If the archive size changes, update
`BetterModel.estimatedDownloadBytes` as the script says. Xcode builds without the pack still download the stock
model from Hugging Face, so test the fine-tune through the pack (TestFlight) or the `--qwen DIR` check above.

## Costs

Prices for `claude-opus-5-5`: $4 per million input tokens, $20 per million output, $0.20 per million cached input
read, and $5 per million cache write. Opus 5.5 always thinks, and thinking is billed as output. The scripts run at
effort `medium`, the model's default (`--effort`), and thinking length is the biggest unknown below. Every script
prints its real spend at the end, so run with `--limit 20` first and extrapolate.

| Job | Per item (estimate) | Total |
|---|---|---|
| Grade 100 answers | ~2,500 new input tokens (prompt with excerpts, history, answer) + ~1,000 output (thinking + JSON); rubric and instructions cached | **~$3** ($2–5); comparing two runs ~$6 |
| Write ~1,500 questions | ~100 requests × ~700 input + ~2,500 output | **~$5** |
| Write ~1,500 answers | ~2,500 input + ~1,200 output | **~$50** ($35–75) |
| Self-check those answers (`--check`) | same as grading | **+~$45** |
| Eval: grade 100 base + 100 fine-tuned | as grading | **~$6** |

So a full training-data run is about $55 without the self-check and about $100 with it, plus about $6 per eval.
These calls don't use the Batches API, which would halve the price, because server-side fallback isn't
available there. If cost matters more than fallback, that is the lever to pull.

## Time

| Step | Estimate |
|---|---|
| Grade 100 answers (4 at a time) | ~10 min |
| Questions (6 at a time) | ~15 min |
| Prompts through `check-answers.sh` | the slow one: Apple's model plans searches, picks excerpts and answers conversation turns, ~5–10 s each, so **2–4 h** for 1,500 |
| Answers (6 at a time) | ~1.5 h; ~3 h with `--check` |
| LoRA, ~650 iterations | unknown until timed (see "Speed" above); budget an afternoon on an M1 Max |
| Fuse and lay out | a few minutes |
| Eval | ~30–40 min of MLX generation for 200 answers, plus ~10 min grading |

None of the live steps (API calls, check-answers, training) were run when these tools were written. Only the dry
runs and the chat-template check were.
