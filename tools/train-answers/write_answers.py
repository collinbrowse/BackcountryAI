"""Has Claude write the answer Scout should have given for each check-answers record (the app's exact instructions
as the system prompt, the exact prompt the app built as the user message), optionally grades each one with the
answer grader and drops weak ones, then writes mlx-lm chat-format training data:

  <out>/train.jsonl, valid.jsonl   {"messages": [system = instructions, user = prompt, assistant = answer]}
  <out>/test.jsonl                 held-out questions in the same format (reference answers, for test loss)
  <out>/test-records.json          the same held-out records without answers, for the base-vs-tuned eval
  <out>/report.json                counts and spend

The held-out test set is whole conversations (all turns of one conversation stay on the same side), and no
question in it appears in train or valid. Answers are cached in <out>/answers.jsonl so reruns only pay for new ones.

Usage: .venv/bin/python -I tools/train-answers/write_answers.py RECORDS.json [...] [--out-dir build/train-answers/data]
         [--check] [--test 100] [--valid-share 0.05] [--concurrency 6] [--effort medium] [--limit N] [--dry-run]
"""
from __future__ import annotations

import argparse
import asyncio
import json
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/grade-answers"))
import claude_jobs as cj  # noqa: E402
import grade  # noqa: E402

WRITER = """\
You are writing reference answers for Scout, an offline field-guide app. A small on-device model (Qwen 3.5 4B) \
will be fine-tuned to imitate exactly what you write, so write the answer that model should have given. The \
app's instructions to that model follow; obey them to the letter, as if you were Scout. The user message is the \
exact prompt the app built: the person's question, sometimes earlier turns, and library search results.

What matters most, because the small model gets these wrong:
- Answer the latest question only, using every detail the person gave. In a follow-up, don't repeat or reword \
earlier answers.
- Never suggest something they said they don't have, can't do, or already tried. Work with what they have.
- Excerpts are search results, often about a different situation. Never treat excerpt content as facts about \
the person (don't invent their gear, vehicle, symptoms or place). Use only excerpt facts that fit, and cite \
those inline like [2]; cite nothing else. If no excerpt helped, begin with "Not from the library:".
- Troubleshooting: order checks cheapest and most likely first, skipping what they already checked.
- 911, SOS or a satellite messenger only when someone is hurt, sick or in danger right now, and then first.
- Format: one opening sentence that answers; then, only if there is something to do, numbered steps written \
as "1. ...", one sentence each, at most five, usually two to four; nothing after the last step. Plain text: no \
headers, bold, bullets or sub-points.
- Be concrete and correct (amounts, times, sizes, what to look for). You know more than the excerpts; use \
standard, safe field knowledge, but if a specific fact can't be known (this model's oil type, a dose for an \
unnamed drug), say so in one sentence instead of guessing.
- If the prompt adds its own shape (a troubleshooting prompt asks to end with an "Ask:" line and options in \
square brackets), follow it exactly.
- Be as short as the situation allows. The small model learns its length from you.

Reply with the answer text only: no preamble, no notes to me."""


def norm(q: str) -> str:
    return " ".join(re.sub(r"[^a-z0-9 ]", " ", q.lower()).split())


def format_problem(answer: str, prompt: str = "") -> str | None:
    """Mechanical checks on the app's answer format. Returns what's wrong, or None."""
    lines = [l.strip() for l in answer.strip().splitlines() if l.strip()]
    if '"Ask:"' in prompt:  # troubleshooting: the prompt asks for a closing question with tap-to-answer options
        if not lines or not re.match(r"^Ask: .+\[[^\]|]+(\|[^\]|]+){1,2}\]$", lines[-1]):
            return "missing or malformed Ask: line"
        lines = lines[:-1]
    if not lines:
        return "empty"
    if re.search(r"^\s*(#|[-*•] )|\*\*|<think>|</think>", answer, re.M):
        return "markdown or thinking tags"
    if re.match(r"^\d+\.", lines[0]):
        return "no opening sentence"
    steps = [l for l in lines if re.match(r"^\d+\.\s", l)]
    if len(steps) > 5:
        return "more than five steps"
    if [int(re.match(r"^(\d+)", x).group(1)) for x in steps] != list(range(1, len(steps) + 1)):
        return "steps not numbered 1..n"
    if steps and not re.match(r"^\d+\.\s", lines[-1]):
        return "text after the last step"
    if answer.rstrip().endswith("Not from the library:"):
        return "ends with 'Not from the library:'"
    return None


def keep_after_check(g: dict) -> bool:
    """Self-check rule: drop anything the grader wouldn't ship."""
    scored = [g[k] for k, _, _ in grade.CRITERIA if g[k]]
    return g["overall"] >= 4 and g["safety"] >= 4 and min(scored) >= 3


def drop_reason(entry: dict | None, prompt: str, check: bool) -> str | None:
    if not entry or not entry.get("answer"):
        return "no answer"
    if problem := format_problem(entry["answer"], prompt):
        return problem
    if check and "check" not in entry:
        return "self-check failed to run"
    if check and not keep_after_check(entry["check"]):
        return "self-check"
    return None


def group_of(r: dict) -> str:
    """Records of one conversation share their first question; all its turns go to the same split."""
    first = (r.get("history") or [{"question": r["question"]}])[0]["question"]
    return norm(first)


def chat(r: dict, answer: str) -> dict:
    return {"messages": [{"role": "system", "content": r["instructions"]}, {"role": "user", "content": r["prompt"]},
                         {"role": "assistant", "content": answer}]}


def fake_answer(kwargs: dict) -> str:
    if kwargs["system"][0]["text"] == grade.RUBRIC:  # a self-check request
        return grade.fake_grade(kwargs)
    prompt = kwargs["messages"][0]["content"][0]["text"]
    rnd = random.Random(prompt)
    if rnd.random() < 0.03:
        return "Here's a closing note too.\n1. Step.\n2. Step.\nHope this helps!"  # exercises the format filter
    n = rnd.choice([0, 2, 3, 4])
    cite = " [1]" if "[1] " in prompt else ""
    head = "" if cite else "Not from the library: "
    ask = "\nAsk: Does it crank? [Yes | No]" if '"Ask:"' in prompt else ""
    return (head + f"Do the obvious safe thing first{cite}." + "".join(f"\n{i}. Fake step {i}." for i in range(1, n + 1))
            + ask)


async def main_async(args):
    out = Path(args.out_dir)
    if args.dry_run:
        out = out / "dry-run" if out.name != "dry-run" else out
    out.mkdir(parents=True, exist_ok=True)
    records = []
    for path in args.records:
        records += json.loads(Path(path).read_text())
    if args.limit:
        records = records[: args.limit]

    # Dedupe: the same prompt twice (a question asked in two lists) is one example.
    seen, unique = set(), []
    for r in records:
        k = cj.key(r["instructions"], r["prompt"])
        if k not in seen and r.get("prompt"):
            seen.add(k)
            unique.append(r)
    print(f"{len(records)} records, {len(unique)} unique prompts")

    cache = {e["key"]: e for e in cj.load_jsonl(out / "answers.jsonl")}
    client = cj.make_client(args.dry_run, fake_answer)
    spend = cj.Spend()
    todo = [r for r in unique if cj.key(r["instructions"], r["prompt"]) not in cache
            or (args.check and "check" not in cache[cj.key(r["instructions"], r["prompt"])])]
    print(f"{len(todo)} to write or check ({len(unique) - len(todo)} cached)")

    with (out / "answers.jsonl").open("a") as cache_file:
        async def work(r):
            k = cj.key(r["instructions"], r["prompt"])
            entry = cache.get(k) or {"key": k}
            if "answer" not in entry:
                entry["answer"] = await cj.ask(client, spend, system=[cj.cached(WRITER), cj.cached(r["instructions"])],
                                               content=[{"type": "text", "text": r["prompt"]}], effort=args.effort)
            if args.check and "check" not in entry and not format_problem(entry["answer"], r["prompt"]):
                entry["check"] = await grade.grade_record(client, spend, {**r, "answer": entry["answer"]}, args.effort)
            cache[k] = entry
            cache_file.write(json.dumps(entry) + "\n")
            cache_file.flush()
        results = await cj.run_all(todo, work, args.concurrency, "answers")
    spend.failed = sum(1 for x in results if isinstance(x, Exception))

    # Keep the good ones.
    kept, drops = [], {}
    for r in unique:
        e = cache.get(cj.key(r["instructions"], r["prompt"]))
        why = drop_reason(e, r["prompt"], args.check)
        if why:
            drops[why] = drops.get(why, 0) + 1
        else:
            kept.append((r, e["answer"]))
    print(f"kept {len(kept)}; dropped {sum(drops.values())}: {drops}")

    # Split by conversation: held-out test groups first, then validation, the rest train.
    groups = {}
    for r, a in kept:
        groups.setdefault(group_of(r), []).append((r, a))
    order = sorted(groups, key=lambda g: cj.key(args.seed, g))
    test, valid, train = [], [], []
    for g in order:
        if len(test) < args.test:
            test += groups[g]
        elif len(valid) < max(10, round(len(kept) * args.valid_share)):
            valid += groups[g]
        else:
            train += groups[g]
    held_out = {norm(r["question"]) for r, _ in test}
    leaked = [x for x in train + valid if norm(x[0]["question"]) in held_out]
    train = [x for x in train if norm(x[0]["question"]) not in held_out]
    valid = [x for x in valid if norm(x[0]["question"]) not in held_out]

    for name, items in (("train", train), ("valid", valid), ("test", test)):
        with (out / f"{name}.jsonl").open("w") as f:
            for r, a in items:
                f.write(json.dumps(chat(r, a)) + "\n")
    test_records = [{**r, "answer": "", "reference": a} for r, a in test]
    (out / "test-records.json").write_text(json.dumps(test_records, indent=1))
    report = {"records": len(records), "unique": len(unique), "kept": len(kept), "dropped": drops,
              "train": len(train), "valid": len(valid), "test": len(test), "removed_as_test_duplicates": len(leaked),
              "self_check": bool(args.check), "spend": spend.as_dict()}
    (out / "report.json").write_text(json.dumps(report, indent=1))
    print(f"train {len(train)}, valid {len(valid)}, test {len(test)} -> {out}")
    print(spend.line())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("records", nargs="+", help="record JSON files from check-answers --json")
    ap.add_argument("--out-dir", default="build/train-answers/data")
    ap.add_argument("--check", action="store_true", help="grade each answer and drop weak ones (about doubles the cost)")
    ap.add_argument("--test", type=int, default=100, help="held-out test records (whole conversations)")
    ap.add_argument("--valid-share", type=float, default=0.05)
    ap.add_argument("--concurrency", type=int, default=6)
    ap.add_argument("--effort", default="medium", choices=["low", "medium", "high", "xhigh", "max"])
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--limit", type=int, help="use only the first N records (to try it out)")
    ap.add_argument("--dry-run", action="store_true", help="fake answers and checks, no network")
    asyncio.run(main_async(ap.parse_args()))


if __name__ == "__main__":
    main()
