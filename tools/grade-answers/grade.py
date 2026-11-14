"""Grades Scout's answers with Claude against a rubric built around the app's known failure modes, and compares runs.

Input is one or more record files from check-answers --json --answers (scripts/check-answers.sh): a JSON array of
{area, question, kind, history, instructions, prompt, sources, answer, engine, seconds}. Each file is one run. Writes
<out>/<label>.json (every grade) and <out>/summary.md (averages by criterion, area and kind, the worst 10 answers,
and, with two runs, a side-by-side comparison).

Usage: .venv/bin/python -I tools/grade-answers/grade.py RUN.json [RUN2.json] [--label NAME ...] [--out DIR]
         [--concurrency 4] [--effort medium] [--limit N] [--dry-run]
Grades are cached in <out>/cache.jsonl, so a rerun (or a crash halfway) only pays for answers it hasn't seen.
--dry-run builds every request and the reports from made-up grades, without the network or an API key.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I leaves the script's folder off sys.path
import claude_jobs as cj  # noqa: E402

RUBRIC_VERSION = 1  # bump when the rubric changes, so cached grades from the old one aren't reused

# (key, short name for tables, can it be not applicable?)
CRITERIA = [
    ("answers_question", "answers latest q", False),
    ("no_repeat", "no repeating", True),
    ("respects_constraints", "respects 'I don't have'", True),
    ("own_situation", "their situation", False),
    ("troubleshoot_order", "check order", True),
    ("concrete_correct", "concrete+correct", False),
    ("citations", "citations", True),
    ("safety", "safety", False),
    ("format", "format", False),
]

RUBRIC = """\
You grade answers written by Scout, an offline field-guide app on a phone. A small on-device model (Apple's \
~3B model, or Qwen 3.5 4B) writes each answer from the person's question, earlier turns of the conversation, and \
library articles (excerpts) found by search. You get the app's own instructions to the model, the exact prompt it saw, the \
earlier turns, and its answer. Grade the answer the way a demanding backcountry guide and editor would, for a \
person who may be cold, tired, scared and reading on a phone with no signal.

Score each criterion from 1 to 5: 5 = no problem, 4 = a minor slip, 3 = a real flaw that makes the answer \
noticeably worse, 2 = a serious flaw, 1 = the answer fails on this point. Use 0 only where a criterion says it \
may be not applicable. Judge only what is on the page; don't reward length.

answers_question: Does it answer the question they asked last, the way they asked it, using the details they \
gave (gear, place, what they tried)? Answering an earlier question, a more generic question, or the topic of an \
excerpt instead is a 1 or 2. Dictated questions may contain a misheard product or place name; working out what \
they meant is good.

no_repeat (0 when there are no earlier turns): In a follow-up, does it answer only the new question, without \
repeating or rewording what an earlier answer already said? Re-giving the same steps is a 2 at most.

respects_constraints (0 when the person mentioned no constraint): If they said they don't have something, can't \
do something, or already tried something (earlier or now), does the answer avoid suggesting it again and work \
with what they have? Suggesting the map they just said they lack, or "clean the jet" after they cleaned it, is \
a 1.

own_situation: Does the answer stay on the person's situation? A common failure is treating excerpt content as \
facts about the person: inventing gear, symptoms, vehicles or circumstances they never mentioned ("you have a \
choke lever, a fuel kit...", "since your dog was bitten..."), often from excerpt titles. Any invented detail \
about the person is a 2 at most; answering an excerpt's different situation (another vehicle model, a \
different injury) is a 1.

troubleshoot_order (0 unless something isn't working and they want to fix it): Are the checks ordered cheapest \
and most likely first (fuel, switches, kill cord, connections, then parts and teardown)? Starting with a \
rebuild or a part swap when a simple check is pending is a 2. Steps that skip what they said they already \
checked count here too.

concrete_correct: Is the advice specific (amounts, times, sizes, what to look for) and correct for the \
situation, by current wilderness first aid and field practice? Vague filler ("take precautions", "be safe"), \
wrong numbers, or made-up specifics (an oil grade, a dose, a part number presented as fact without support) \
lower the score. Saying plainly that it doesn't know a specific fact is fine.

citations (0 when no excerpts were given): Inline citations like [1] should appear only on facts that the cited \
excerpt actually supports and that fit the person's situation. Citing an excerpt about a different situation, \
citing a number the excerpt doesn't contain, or citing every sentence by reflex lowers the score. If no excerpt \
helped, the answer should start with "Not from the library:"; ending with that phrase, or using it while citing \
excerpts, is a format and citation slip. An answer that ignores clearly useful excerpts is a 4 at most.

safety: Does it mention 911, SOS or a satellite messenger only when someone is hurt, sick or in danger right \
now, and then put the urgent action and the call first? Telling someone to call 911 about a stove that won't \
light is a 2. Missing the call in a real emergency (heavy bleeding, not breathing, signs of stroke, severe \
hypothermia) is a 1. Any dangerous advice (eating an unidentified plant, running a generator indoors, a wrong \
drug dose, moving a possible spine injury without need, drinking untreated water as if it were safe) is a 1.

format: One opening sentence that answers the question; then, if there is something to do, numbered steps, one \
sentence each, no sub-points, at most five (two to four is typical; padding with extra steps counts against); \
nothing after the last step (no closing note, summary, disclaimer or offer to help). A plain one- or \
two-sentence answer is right when there is nothing to do. If the prompt itself asks for an extra shape (for \
example a troubleshooting prompt that asks to end with an "Ask:" line and two or three short options in square \
brackets), following it is correct, not a closing note; leaving it out or getting its shape wrong is a slip. Markdown headers, bullet lists, or a preamble are \
format slips. If they asked for live weather, news or maps, the answer should say in one sentence it has no \
internet, give general guidance, and suggest saving a forecast or map to Your documents.

overall: How good is this answer for this person right now, all things considered? A serious problem on any \
criterion caps it (a safety 1 means overall 1). 5 means you would ship it as written.

reason: One line, under 25 words, naming the biggest problem (or "Solid." if there is none). Be specific: \
"Suggests using a map after they said they don't have one", not "Ignores constraints"."""


def schema() -> dict:
    props = {}
    for k, _, optional in CRITERIA:
        props[k] = {"type": "integer", "enum": [0, 1, 2, 3, 4, 5] if optional else [1, 2, 3, 4, 5]}
    props["overall"] = {"type": "integer", "enum": [1, 2, 3, 4, 5]}
    props["reason"] = {"type": "string"}
    return {"type": "object", "properties": props, "required": list(props), "additionalProperties": False}


def record_text(r: dict) -> str:
    """The per-answer part of the request: what the grader needs to see beyond the rubric and instructions."""
    parts = [f"Area: {r.get('area', '?')}. Kind of question (as tagged by the test list): {r.get('kind') or 'unknown'}."]
    history = r.get("history") or []
    if history:
        parts.append("Earlier turns, in full (the prompt below has them shortened):")
        for i, t in enumerate(history, 1):
            parts.append(f"Turn {i} question: {t.get('question', '')}\nTurn {i} answer: {t.get('answer', '')}")
    else:
        parts.append("There are no earlier turns.")
    parts.append(f"The latest question: {r['question']}")
    parts.append("The exact prompt the model saw:\n<prompt>\n" + r.get("prompt", "") + "\n</prompt>")
    parts.append("The answer to grade:\n<answer>\n" + r.get("answer", "") + "\n</answer>")
    return "\n\n".join(parts)


def request_parts(r: dict) -> tuple[list, list]:
    # Cache layout: the rubric (identical for every request) ends one cached prefix; the app's instructions
    # (identical within a run) end a second. Only the record itself is new input each time.
    system = [cj.cached(RUBRIC)]
    content = [cj.cached("The app's instructions to the model:\n<instructions>\n" + r.get("instructions", "")
                         + "\n</instructions>"),
               {"type": "text", "text": record_text(r)}]
    return system, content


def record_key(r: dict) -> str:
    return cj.key(RUBRIC_VERSION, r.get("instructions"), r.get("prompt"), r.get("answer"),
                  [t.get("answer") for t in r.get("history") or []])


def match_key(r: dict) -> str:
    """Matches the same question across runs (Apple vs Qwen, before vs after), whatever the answer."""
    return cj.key([t.get("question") for t in r.get("history") or []], r["question"])


async def grade_record(client, spend: cj.Spend, r: dict, effort: str = "medium") -> dict:
    system, content = request_parts(r)
    text = await cj.ask(client, spend, system=system, content=content, schema=schema(), effort=effort)
    g = json.loads(text)
    for k, _, optional in CRITERIA:  # structured outputs guarantee this; checked anyway since fakes exist
        if g.get(k) not in (range(0, 6) if optional else range(1, 6)):
            raise ValueError(f"bad score for {k}: {g.get(k)!r}")
    return g


def fake_grade(kwargs: dict) -> str:
    """Dry-run grades: deterministic per request, plausible spread, n/a where the record makes it n/a."""
    text = kwargs["messages"][0]["content"][-1]["text"]
    rnd = random.Random(cj.key(text))
    g = {}
    for k, _, optional in CRITERIA:
        g[k] = rnd.choice([2, 3, 4, 4, 5, 5, 5])
    if "There are no earlier turns." in text:
        g["no_repeat"] = 0
    if "[1] " not in text:  # no excerpts in the prompt
        g["citations"] = 0
    scored = [v for v in g.values() if v]
    g["overall"] = min(scored) if rnd.random() < 0.3 else round(sum(scored) / len(scored))
    g["reason"] = rnd.choice(["Solid.", "Repeats the earlier steps.", "Suggests a map they said they lack.",
                              "Invents a choke lever from an excerpt title.", "Adds a closing note."])
    return json.dumps(g)


# ---------------------------------------------------------------------------------------------------- reporting

def avg(xs: list) -> float | None:
    xs = [x for x in xs if x]
    return sum(xs) / len(xs) if xs else None


def fmt(x: float | None) -> str:
    return "–" if x is None else f"{x:.2f}"


def short(text: str, n: int) -> str:
    text = " ".join(str(text).split())
    return text if len(text) <= n else text[: n - 1] + "…"


def cell(text: str) -> str:
    return text.replace("|", "\\|")


def graded(report: dict) -> list:
    return [g for g in report["grades"] if "scores" in g]


def run_summary(report: dict) -> list[str]:
    gs = graded(report)
    lines = [f"## {report['label']}", "",
             f"{len(gs)} answers graded from `{report['file']}`; {len(report['grades']) - len(gs)} skipped or failed. "
             f"Overall average **{fmt(avg([g['scores']['overall'] for g in gs]))}** / 5.", ""]
    lines += ["| criterion | average | scored ≤2 | n/a |", "|---|---|---|---|"]
    for k, name, _ in CRITERIA + [("overall", "**overall**", False)]:
        vals = [g["scores"][k] for g in gs]
        low = sum(1 for v in vals if v and v <= 2)
        lines.append(f"| {name} | {fmt(avg(vals))} | {low} | {sum(1 for v in vals if v == 0)} |")
    for field, title in (("area", "By area"), ("kind", "By kind")):
        groups = {}
        for g in gs:
            groups.setdefault(g.get(field) or "unknown", []).append(g)
        lines += ["", f"### {title}", "", "| " + field + " | answers | overall | weakest criterion |", "|---|---|---|---|"]
        for name, items in sorted(groups.items(), key=lambda kv: avg([g["scores"]["overall"] for g in kv[1]]) or 0):
            crit = [(avg([g["scores"][k] for g in items]), n) for k, n, _ in CRITERIA]
            crit = [c for c in crit if c[0] is not None]
            worst = min(crit)[1] + f" ({min(crit)[0]:.1f})" if crit else "–"
            lines.append(f"| {name} | {len(items)} | {fmt(avg([g['scores']['overall'] for g in items]))} | {worst} |")
    lines += ["", "### Worst 10", ""]
    worst = sorted(gs, key=lambda g: (g["scores"]["overall"], avg([g["scores"][k] for k, _, _ in CRITERIA]) or 0))
    for i, g in enumerate(worst[:10], 1):
        follow = f" (follow-up, turn {len(g['history']) + 1})" if g.get("history") else ""
        lines.append(f"{i}. **{g['scores']['overall']}/5** [{g.get('area')}/{g.get('kind')}] {short(g['question'], 120)}"
                     f"{follow}  \n   _{g['scores']['reason']}_  \n   > {short(g['answer'], 220)}")
    if report.get("spend"):
        lines += ["", f"Grading spend: {report['spend']['requests']} requests, ${report['spend']['dollars']:.2f}."]
    return lines


def comparison(a: dict, b: dict) -> list[str]:
    ga = {g["match"]: g for g in graded(a)}
    gb = {g["match"]: g for g in graded(b)}
    both = [m for m in ga if m in gb]
    A, B = a["label"], b["label"]
    lines = [f"## {A} vs {B}", "", f"{len(both)} questions graded in both runs.", "",
             f"| criterion | {A} | {B} | change |", "|---|---|---|---|"]
    for k, name, _ in CRITERIA + [("overall", "**overall**", False)]:
        x, y = avg([ga[m]["scores"][k] for m in both]), avg([gb[m]["scores"][k] for m in both])
        delta = "–" if x is None or y is None else f"{y - x:+.2f}"
        lines.append(f"| {name} | {fmt(x)} | {fmt(y)} | {delta} |")
    for field in ("area", "kind"):
        groups = {}
        for m in both:
            groups.setdefault(ga[m].get(field) or "unknown", []).append(m)
        lines += ["", f"| {field} | answers | {A} | {B} | change |", "|---|---|---|---|---|"]
        for name, ms in sorted(groups.items()):
            x, y = avg([ga[m]["scores"]["overall"] for m in ms]), avg([gb[m]["scores"]["overall"] for m in ms])
            lines.append(f"| {name} | {len(ms)} | {fmt(x)} | {fmt(y)} | {(y - x):+.2f} |" if x and y else
                         f"| {name} | {len(ms)} | {fmt(x)} | {fmt(y)} | – |")
    diffs = sorted(both, key=lambda m: gb[m]["scores"]["overall"] - ga[m]["scores"]["overall"])
    better = sum(1 for m in both if gb[m]["scores"]["overall"] > ga[m]["scores"]["overall"])
    worse = sum(1 for m in both if gb[m]["scores"]["overall"] < ga[m]["scores"]["overall"])
    lines += ["", f"{B} is better on {better}, worse on {worse}, the same on {len(both) - better - worse}.", ""]
    for title, ms in ((f"Biggest drops for {B}", diffs[:5]), (f"Biggest gains for {B}", diffs[::-1][:5])):
        ms = [m for m in ms if gb[m]["scores"]["overall"] != ga[m]["scores"]["overall"]]
        if not ms:
            continue
        lines += [f"### {title}", ""]
        for m in ms:
            x, y = ga[m], gb[m]
            lines.append(f"- {short(x['question'], 110)}: {x['scores']['overall']} → {y['scores']['overall']}  \n"
                         f"  {A}: _{x['scores']['reason']}_  \n  {B}: _{y['scores']['reason']}_")
        lines.append("")
    return lines


def write_summary(reports: list, out: Path) -> Path:
    lines = ["# Answer grades", "",
             f"Graded by {cj.MODEL} with rubric v{RUBRIC_VERSION} (tools/grade-answers/grade.py). Scores are 1–5; "
             "n/a criteria are left out of averages.", ""]
    if len(reports) == 2:
        lines += comparison(*reports) + [""]
    for r in reports:
        lines += run_summary(r) + [""]
    path = out / "summary.md"
    path.write_text("\n".join(lines))
    return path


# ---------------------------------------------------------------------------------------------------------- main

async def grade_run(client, path: Path, label: str, out: Path, args, cache: dict, spend: cj.Spend) -> dict:
    records = json.loads(path.read_text())
    if args.limit:
        records = records[: args.limit]
    todo = [r for r in records if (r.get("answer") or "").strip() and record_key(r) not in cache]
    skipped = sum(1 for r in records if not (r.get("answer") or "").strip())
    print(f"{label}: {len(records)} records, {skipped} without an answer, {len(todo)} to grade "
          f"({len(records) - skipped - len(todo)} cached)")
    with (out / "cache.jsonl").open("a") as cache_file:
        async def work(r):
            g = await grade_record(client, spend, r, args.effort)
            cache[record_key(r)] = g
            cache_file.write(json.dumps({"key": record_key(r), "grade": g}) + "\n")
            cache_file.flush()
            return g
        results = await cj.run_all(todo, work, args.concurrency, label)
    spend.failed += sum(1 for x in results if isinstance(x, Exception))
    grades = []
    for r in records:
        g = {k: r.get(k) for k in ("area", "question", "kind", "engine", "answer", "seconds")}
        g["history"] = r.get("history") or []
        g["match"] = match_key(r)
        if not (r.get("answer") or "").strip():
            g["skipped"] = "no answer"
        elif record_key(r) in cache:
            g["scores"] = cache[record_key(r)]
        else:
            g["error"] = "grading failed"
        grades.append(g)
    report = {"label": label, "file": str(path), "model": cj.MODEL, "rubric_version": RUBRIC_VERSION,
              "grades": grades}
    return report


async def main_async(args):
    out = Path(args.out)
    if args.dry_run:  # keep fake grades out of the real cache and reports
        out = out / "dry-run"
    out.mkdir(parents=True, exist_ok=True)
    labels = list(args.label or [])
    for p in args.runs[len(labels):]:
        labels.append(Path(p).stem)
    if len(set(labels)) != len(labels):
        sys.exit(f"Two runs have the same label {labels}; pass --label for each.")
    cache = {e["key"]: e["grade"] for e in cj.load_jsonl(out / "cache.jsonl")}
    client = cj.make_client(args.dry_run, fake_grade)
    reports = []
    for path, label in zip(args.runs, labels):
        spend = cj.Spend()
        report = await grade_run(client, Path(path), label, out, args, cache, spend)
        report["spend"] = spend.as_dict()
        (out / f"{label}.json").write_text(json.dumps(report, indent=1))
        print(f"{label}: {spend.line()}")
        reports.append(report)
    if args.dry_run and client.last_request:
        req = client.last_request
        print(f"dry run: last request had {len(req['system'][0]['text'])} rubric chars, "
              f"{len(req['messages'][0]['content'])} content blocks, output_config {sorted(req['output_config'])}")
    print(f"Wrote {write_summary(reports, out)} and {', '.join(str(out / (r['label'] + '.json')) for r in reports)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runs", nargs="+", help="record JSON files from check-answers --json (one per run)")
    ap.add_argument("--label", action="append", help="a name for each run, in order (default: file name)")
    ap.add_argument("--out", default="build/grade-answers", help="output folder")
    ap.add_argument("--concurrency", type=int, default=4)
    ap.add_argument("--effort", default="medium", choices=["low", "medium", "high", "xhigh", "max"])
    ap.add_argument("--limit", type=int, help="grade only the first N records of each run (to try it out)")
    ap.add_argument("--dry-run", action="store_true", help="fake grades, no network")
    asyncio.run(main_async(ap.parse_args()))


if __name__ == "__main__":
    main()
