"""Judges the library excerpts Scout's retrieval hands to the answer model: does each one actually help answer this
person's question? This replaces "a picked title matches a keyword" (scripts/check-answers.sh's PASS line), which
counted a Tesla-charger thread as a hit for running a car in a garage.

Input is one or more record files from check-answers --json (scripts/check-answers.sh): each record has the
question, the earlier turns and the excerpts that reached the prompt (and, when the run saved them, every candidate
the search found). Claude scores each excerpt 0 to 3:

  3  answers it: has the steps, facts or numbers this person needs, for their situation
  2  helps: the right subject, and part of the answer
  1  near miss: the same broad topic but another situation, product or question
  0  unrelated

Writes <out>/<label>.json (every score) and <out>/summary.md: how often a prompt held an excerpt that answers the
question, how much of what it held was noise, the same by area, the worst prompts, and, with two runs, a comparison.

Usage: .venv/bin/python -I tools/grade-answers/judge_passages.py RUN.json [RUN2.json] [--label NAME ...]
         [--out DIR] [--candidates] [--concurrency 6] [--effort low] [--limit N] [--dry-run]
--candidates also scores the candidates the picker dropped (records made with check-answers --candidates), which
separates "search never found it" from "the picker threw it away".
Scores are cached in <out>/cache.jsonl by question and excerpt text, so a rerun only pays for excerpts it hasn't seen.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import random
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I leaves the script's folder off sys.path
import claude_jobs as cj  # noqa: E402

RUBRIC_VERSION = 1  # bump when the rubric changes, so cached scores from the old one aren't reused

RUBRIC = """\
You judge search results for Scout, an offline field-guide app on a phone. A person, often in the backcountry \
with no signal, asked a question. Search found excerpts from a library of first-aid and survival manuals, \
government safety guides, Wikipedia's medical articles and Q&A forums. A small on-device model will write its \
answer from these excerpts, and it tends to follow whatever they say, so an excerpt about a different situation \
does harm.

Score each excerpt for how much it helps answer this person's latest question, in their situation:

3 = answers it: the excerpt has the steps, facts or numbers this person needs, and they fit the situation.
2 = helps: the right subject, and part of what they need, but not enough alone.
1 = near miss: the same broad topic but a different situation, product, animal or question (a home furnace for a \
camp stove, a car for a snowmobile, prevention when they asked for treatment), or a forum post that only asks \
the question without answering it. Writing from it would mislead or add nothing.
0 = unrelated.

Judge the excerpt as given, even where it is cut off, not what the full article might say. When the person is \
following up on an earlier turn, judge against the whole situation: "he's stopped shivering" after "my friend \
fell in a creek" is about hypothermia. Don't reward an excerpt for being authoritative or well written; only \
for containing what this person needs.

why: under 15 words, naming what the excerpt is about and why it does or doesn't help."""

OFFICIAL = re.compile(r"government|Ready\.gov|MedlinePlus|CDC|Military|USDA|Medicines A to Z|field card", re.I)


def schema(n: int) -> dict:
    item = {"type": "object", "additionalProperties": False, "required": ["n", "score", "why"],
            "properties": {"n": {"type": "integer"}, "score": {"type": "integer", "enum": [0, 1, 2, 3]},
                           "why": {"type": "string"}}}
    return {"type": "object", "additionalProperties": False, "required": ["scores"],
            "properties": {"scores": {"type": "array", "items": item}}}


def situation(r: dict) -> str:
    parts = []
    for t in r.get("history") or []:
        parts.append(f"Earlier they said: {t.get('question', '')}")
    parts.append(f"Their latest question: {r['question']}")
    return "\n".join(parts)


def excerpt_key(r: dict, e: dict) -> str:
    return cj.key(RUBRIC_VERSION, [t.get("question") for t in r.get("history") or []], r["question"],
                  e.get("title"), e.get("text"))


def excerpts_of(r: dict, candidates: bool) -> list:
    """The excerpts to judge for one record: what reached the prompt, then (with --candidates) what was dropped."""
    out = [{**e, "kept": True} for e in r.get("sources") or []]
    if candidates:
        seen = {(e.get("title"), e.get("text")) for e in out}
        out += [{**e, "kept": False} for e in r.get("candidates") or []
                if (e.get("title"), e.get("text")) not in seen]
    return out


def request_text(r: dict, excerpts: list) -> str:
    parts = [situation(r), "", f"Excerpts ({len(excerpts)}):"]
    for i, e in enumerate(excerpts, 1):
        parts.append(f"[{i}] {e.get('title', '')} ({e.get('source', '')})\n{e.get('text', '')}")
    parts.append(f"Score all {len(excerpts)} excerpts, in order.")
    return "\n\n".join(parts)


async def judge_record(client, spend: cj.Spend, r: dict, excerpts: list, effort: str) -> list:
    """One request for all of a record's excerpts. If the reply skips some (it happens when two excerpts are
    near-copies), those are asked again on their own, so one short reply doesn't lose the record."""
    scored: dict[int, dict] = {}
    for _ in range(3):
        missing = [i for i in range(len(excerpts)) if i not in scored]
        if not missing:
            break
        asked = [excerpts[i] for i in missing]
        text = await cj.ask(client, spend, system=[cj.cached(RUBRIC)],
                            content=[{"type": "text", "text": request_text(r, asked)}],
                            schema=schema(len(asked)), effort=effort)
        for s in json.loads(text)["scores"]:
            if 1 <= s["n"] <= len(asked):
                scored.setdefault(missing[s["n"] - 1], {"score": s["score"], "why": s["why"]})
    if len(scored) != len(excerpts):
        raise ValueError(f"scored {len(scored)} of {len(excerpts)} excerpts")
    return [scored[i] for i in range(len(excerpts))]


def fake_scores(kwargs: dict) -> str:
    """Dry-run scores: deterministic per request, with a plausible spread."""
    text = kwargs["messages"][0]["content"][-1]["text"]
    n = int(re.search(r"Excerpts \((\d+)\):", text).group(1))
    rnd = random.Random(cj.key(text))
    return json.dumps({"scores": [{"n": i, "score": rnd.choice([0, 1, 1, 2, 2, 3]), "why": "fake"}
                                  for i in range(1, n + 1)]})


# ---------------------------------------------------------------------------------------------------- reporting

def pct(a: int, b: int) -> str:
    return "–" if not b else f"{100 * a / b:.0f}%"


def short(text: str, n: int) -> str:
    text = " ".join(str(text).split())
    return text if len(text) <= n else text[: n - 1] + "…"


def stats(rows: list) -> dict:
    """Numbers for a set of judged records. `rows` are the report's per-question entries."""
    kept = [[e for e in r["excerpts"] if e["kept"]] for r in rows]
    flat = [e for es in kept for e in es]
    n = len(rows)
    return {
        "prompts": n,
        "excerpts": len(flat),
        "answered": sum(1 for es in kept if any(e["score"] == 3 for e in es)),
        "helped": sum(1 for es in kept if any(e["score"] >= 2 for e in es)),
        "empty": sum(1 for es in kept if not es),
        "all_noise": sum(1 for es in kept if es and all(e["score"] <= 1 for e in es)),
        "noise": sum(1 for e in flat if e["score"] <= 1),
        "official": sum(1 for e in flat if OFFICIAL.search(e.get("source") or "")),
        "mean": sum(e["score"] for e in flat) / len(flat) if flat else 0.0,
        # The best excerpt search found, kept or not: what a perfect picker could have reached.
        "found_answer": sum(1 for r in rows if any(e["score"] == 3 for e in r["excerpts"])),
        "dropped_answer": sum(1 for r, es in zip(rows, kept)
                              if not any(e["score"] == 3 for e in es) and any(e["score"] == 3 for e in r["excerpts"])),
        "has_candidates": any(not e["kept"] for r in rows for e in r["excerpts"]),
    }


def stat_lines(s: dict) -> list[str]:
    n = s["prompts"]
    lines = [f"| prompts with an excerpt that answers the question (a 3) | {s['answered']} of {n} | {pct(s['answered'], n)} |",
             f"| prompts with an excerpt that at least helps (2 or 3) | {s['helped']} of {n} | {pct(s['helped'], n)} |",
             f"| prompts whose excerpts are all noise (every score 0 or 1) | {s['all_noise']} of {n} | {pct(s['all_noise'], n)} |",
             f"| prompts with no excerpts | {s['empty']} of {n} | {pct(s['empty'], n)} |",
             f"| excerpts that are noise (0 or 1) | {s['noise']} of {s['excerpts']} | {pct(s['noise'], s['excerpts'])} |",
             f"| excerpts from official sources and manuals | {s['official']} of {s['excerpts']} | {pct(s['official'], s['excerpts'])} |",
             f"| mean excerpt score (0 to 3) | {s['mean']:.2f} | |"]
    if s["has_candidates"]:
        lines += [f"| search found an answering excerpt, kept or dropped | {s['found_answer']} of {n} | {pct(s['found_answer'], n)} |",
                  f"| the picker dropped the only answering excerpt | {s['dropped_answer']} of {n} | {pct(s['dropped_answer'], n)} |"]
    return lines


def run_summary(report: dict) -> list[str]:
    rows = [r for r in report["records"] if "excerpts" in r]
    lines = [f"## {report['label']}", "", f"{len(rows)} prompts judged from `{report['file']}`; "
             f"{len(report['records']) - len(rows)} failed.", "", "| | | |", "|---|---|---|"] + stat_lines(stats(rows))
    for field, title in (("area", "By area"), ("turn", "First questions and follow-ups")):
        groups = {}
        for r in rows:
            name = r.get("area") or "unknown" if field == "area" else ("follow-up" if r["history"] else "first question")
            groups.setdefault(name, []).append(r)
        lines += ["", f"### {title}", "", "| | prompts | answered (a 3) | helped (2+) | noise excerpts | mean |", "|---|---|---|---|---|---|"]
        for name, items in sorted(groups.items()):
            s = stats(items)
            lines.append(f"| {name} | {s['prompts']} | {pct(s['answered'], s['prompts'])} | {pct(s['helped'], s['prompts'])} "
                         f"| {pct(s['noise'], s['excerpts'])} | {s['mean']:.2f} |")
    lines += ["", "### Prompts with nothing that helps", ""]
    bad = [r for r in rows if not any(e["kept"] and e["score"] >= 2 for e in r["excerpts"])]
    for r in bad[:25]:
        turn = f" (follow-up, turn {len(r['history']) + 1})" if r["history"] else ""
        lines.append(f"- [{r.get('area')}] {short(r['question'], 110)}{turn}")
        for e in [e for e in r["excerpts"] if e["kept"]][:4]:
            lines.append(f"  - {e['score']} · {short(e['title'], 70)}: _{short(e['why'], 90)}_")
        if not any(e["kept"] for e in r["excerpts"]):
            lines.append("  - (no excerpts)")
    if len(bad) > 25:
        lines.append(f"- … and {len(bad) - 25} more")
    if report.get("spend"):
        lines += ["", f"Judging spend: {report['spend']['requests']} requests, ${report['spend']['dollars']:.2f}"
                  + (" at API prices (run on the subscription)." if report["spend"].get("billed") == "subscription" else ".")]
    return lines


def comparison(a: dict, b: dict) -> list[str]:
    ra = {r["match"]: r for r in a["records"] if "excerpts" in r}
    rb = {r["match"]: r for r in b["records"] if "excerpts" in r}
    both = [m for m in ra if m in rb]
    A, B = a["label"], b["label"]
    sa, sb = stats([ra[m] for m in both]), stats([rb[m] for m in both])
    n = len(both)
    lines = [f"## {A} vs {B}", "", f"{n} prompts judged in both runs.", "", f"| | {A} | {B} |", "|---|---|---|",
             f"| answered (an excerpt scored 3) | {sa['answered']} ({pct(sa['answered'], n)}) | {sb['answered']} ({pct(sb['answered'], n)}) |",
             f"| helped (2 or 3) | {sa['helped']} ({pct(sa['helped'], n)}) | {sb['helped']} ({pct(sb['helped'], n)}) |",
             f"| all noise | {sa['all_noise']} ({pct(sa['all_noise'], n)}) | {sb['all_noise']} ({pct(sb['all_noise'], n)}) |",
             f"| no excerpts | {sa['empty']} | {sb['empty']} |",
             f"| noise excerpts | {pct(sa['noise'], sa['excerpts'])} of {sa['excerpts']} | {pct(sb['noise'], sb['excerpts'])} of {sb['excerpts']} |",
             f"| official excerpts | {pct(sa['official'], sa['excerpts'])} | {pct(sb['official'], sb['excerpts'])} |",
             f"| mean excerpt score | {sa['mean']:.2f} | {sb['mean']:.2f} |"]

    def best(r):
        return max([e["score"] for e in r["excerpts"] if e["kept"]], default=-1)
    up = [m for m in both if best(rb[m]) > best(ra[m])]
    down = [m for m in both if best(rb[m]) < best(ra[m])]
    lines += ["", f"Best excerpt per prompt: {B} is higher on {len(up)}, lower on {len(down)}, the same on {n - len(up) - len(down)}.", ""]
    for title, ms in ((f"Where {B} lost its best excerpt", down), (f"Where {B} found a better one", up)):
        if ms:
            lines += [f"### {title}", ""]
            lines += [f"- {short(ra[m]['question'], 100)}: {best(ra[m])} → {best(rb[m])}" for m in ms[:12]]
            lines.append("")
    return lines


def write_summary(reports: list, out: Path) -> Path:
    lines = ["# Retrieval judged", "",
             f"Each excerpt scored 0 to 3 by {cj.MODEL} (rubric v{RUBRIC_VERSION}, tools/grade-answers/judge_passages.py): "
             "3 answers the question, 2 helps, 1 is a near miss, 0 is unrelated.", ""]
    if len(reports) == 2:
        lines += comparison(*reports) + [""]
    for r in reports:
        lines += run_summary(r) + [""]
    path = out / "summary.md"
    path.write_text("\n".join(lines))
    return path


# ---------------------------------------------------------------------------------------------------------- main

async def judge_run(client, path: Path, label: str, out: Path, args, cache: dict, spend: cj.Spend) -> dict:
    records = json.loads(path.read_text())
    if args.limit:
        records = records[: args.limit]
    todo = []
    for r in records:
        es = excerpts_of(r, args.candidates)
        if es and any(excerpt_key(r, e) not in cache for e in es):
            todo.append((r, es))
    print(f"{label}: {len(records)} records, {len(todo)} to judge ({len(records) - len(todo)} cached or without excerpts)")
    with (out / "cache.jsonl").open("a") as cache_file:
        async def work(item):
            r, es = item
            scores = await judge_record(client, spend, r, es, args.effort)
            for e, s in zip(es, scores):
                cache[excerpt_key(r, e)] = s
                cache_file.write(json.dumps({"key": excerpt_key(r, e), "score": s}) + "\n")
            cache_file.flush()
        results = await cj.run_all(todo, work, args.concurrency, label)
    spend.failed += sum(1 for x in results if isinstance(x, Exception))
    rows = []
    for r in records:
        row = {"area": r.get("area"), "question": r["question"], "history": [t.get("question") for t in r.get("history") or []],
               "match": cj.key([t.get("question") for t in r.get("history") or []], r["question"])}
        es = excerpts_of(r, args.candidates)
        if all(excerpt_key(r, e) in cache for e in es):
            row["excerpts"] = [{"title": e.get("title"), "source": e.get("source"), "kept": e["kept"],
                                **cache[excerpt_key(r, e)]} for e in es]
        else:
            row["error"] = "judging failed"
        rows.append(row)
    return {"label": label, "file": str(path), "model": cj.MODEL, "rubric_version": RUBRIC_VERSION, "records": rows}


async def main_async(args):
    out = Path(args.out)
    if args.dry_run:  # keep fake scores out of the real cache and reports
        out = out / "dry-run"
    out.mkdir(parents=True, exist_ok=True)
    labels = list(args.label or [])
    for p in args.runs[len(labels):]:
        labels.append(Path(p).stem)
    if len(set(labels)) != len(labels):
        sys.exit(f"Two runs have the same label {labels}; pass --label for each.")
    cache = {e["key"]: e["score"] for e in cj.load_jsonl(out / "cache.jsonl")}
    client = cj.make_client(args.dry_run, fake_scores)
    reports = []
    for path, label in zip(args.runs, labels):
        spend = cj.Spend()
        report = await judge_run(client, Path(path), label, out, args, cache, spend)
        report["spend"] = spend.as_dict()
        (out / f"{label}.json").write_text(json.dumps(report, indent=1))
        print(f"{label}: {spend.line()}")
        reports.append(report)
    print(f"Wrote {write_summary(reports, out)} and {', '.join(str(out / (r['label'] + '.json')) for r in reports)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runs", nargs="+", help="record JSON files from check-answers --json (one per run)")
    ap.add_argument("--label", action="append", help="a name for each run, in order (default: file name)")
    ap.add_argument("--out", default="build/judge-passages", help="output folder")
    ap.add_argument("--candidates", action="store_true", help="also judge the candidates the picker dropped")
    ap.add_argument("--concurrency", type=int, default=6)
    ap.add_argument("--effort", default="low", choices=["low", "medium", "high", "xhigh", "max"])
    ap.add_argument("--limit", type=int, help="judge only the first N records of each run (to try it out)")
    ap.add_argument("--dry-run", action="store_true", help="fake scores, no network")
    asyncio.run(main_async(ap.parse_args()))


if __name__ == "__main__":
    main()
