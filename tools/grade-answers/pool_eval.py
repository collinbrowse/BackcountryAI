"""Tries retrieval rules offline and scores them with the excerpt judge (judge_passages.py).

`scout-tools pool` saves, for every test question, everything the app's searches matched before its rules for
choosing among the hits (one passage per article, six per search, ten candidates) and what those rules chose. This
script applies other rules to the same hits (how many passages one article may contribute, whether a forum
thread is shown by its best answer or by the passage that matched, how sources are weighted), has Claude judge
every excerpt a rule would put in front of the picker, and reports for each rule how often a question gets an
excerpt that answers it.

Usage: .venv/bin/python -I tools/grade-answers/pool_eval.py POOL.json [--rules NAME,NAME] [--top 10]
         [--out DIR] [--no-judge] [--concurrency 6] [--show RULE]
Rules are defined in RULES below; `app` is the app's own choice as recorded in the pool (so a pool made by an
older build carries that build's rule as its baseline). Scores come from and go to
<out>/cache.jsonl, the cache judge_passages.py uses, so nothing is judged twice.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I leaves the script's folder off sys.path
import claude_jobs as cj  # noqa: E402
import judge_passages as jp  # noqa: E402

# Sources by how close they are to what Scout is for: field and emergency guidance first, forums about houses last.
FIELD = {"survival-manuals", "military-medicine", "gov-guides", "ready-gov", "cdc-travel", "medlineplus", "risk",
         "se-outdoors", "usda-canning", "nhs-medicines"}
HOUSEHOLD = {"se-diy", "se-cooking", "se-gardening", "se-lifehacks", "se-sustainability", "se-pets"}

# name: (description, settings). Settings not given keep DEFAULT's, which are Retrieval.candidates' own.
DEFAULT = dict(per_list=6, list_cap=2, dense_n=8, k=8, per_doc=2, doc_bonus=0.5, later=0.6, limit=10,
               se_answer=True, field=1.0, household=1.0, chars=1500)
RULES = {
    "whole": ("the app's old rule, whole passages", dict(per_doc=1, list_cap=1, doc_bonus=1.0, later=1.0, se_answer=False)),
    "answers": ("+ a forum thread is shown by its best answer", dict(per_doc=1, list_cap=1, doc_bonus=1.0, later=1.0)),
    "two": ("+ an article may give two passages", dict(later=1.0)),
    "two-later": ("+ the second at 0.6 of its score (Retrieval.candidates today)", {}),
    "three": ("three passages an article", dict(per_doc=3, list_cap=3, later=1.0)),
    "two-own": ("two passages, each ranked by its own hits alone", dict(doc_bonus=0.0)),
    "field": ("two-later + field sources weighted up", dict(field=1.25)),
    "field-house": ("two-later + field sources up, household forums down", dict(field=1.25, household=0.8)),
    "deep": ("two-later + eight hits per search and twelve from meaning", dict(per_list=8, dense_n=12)),
}

TRANSLATION = re.compile(r"/[a-z]{2,3}(-[a-z]+)?$")


def cut(text: str, chars: int) -> str:
    """The passage up to about `chars`, ending on a sentence."""
    if len(text) <= chars:
        return text
    end = max(text.rfind(". ", chars // 2, chars), text.rfind("? ", chars // 2, chars))
    return text[: end + 1 if end > 0 else chars].rstrip() + " …"


class Pool:
    def __init__(self, path: str):
        data = json.loads(Path(path).read_text())
        self.records = [r for r in data["records"] if not r.get("skipped")]
        self.skipped = len(data["records"]) - len(self.records)
        self.passages = {int(k): v for k, v in data["passages"].items()}
        by_doc = defaultdict(list)
        for pid, p in self.passages.items():
            by_doc[p["doc"]].append(pid)
        self.by_doc = {d: sorted(ids) for d, ids in by_doc.items()}

    def usable(self, pid: int) -> bool:
        p = self.passages.get(pid)
        return bool(p) and not (p["key"] in ("appropedia", "energypedia") and TRANSLATION.search(p["title"]))

    def best_answer(self, pid: int) -> int:
        """For a passage of a forum thread: the passage to show. A passage that is (part of) an answer stays; the
        question is replaced by the accepted answer's first passage, or the first answer's (they are stored best
        first)."""
        p = self.passages[pid]
        if not p["key"].startswith("se-"):
            return pid
        if re.search(r"\bAnswer( by [^()]{1,60})? \(score -?\d+", p["text"]):
            return pid  # a short question and the start of its first answer in one passage
        thread = self.by_doc[p["doc"]]
        starts = [i for i in thread if re.match(r"Answer\b", self.passages[i]["text"])]
        if not starts or pid >= starts[0]:
            return pid
        accepted = [i for i in starts if re.match(r"Answer[^:]{0,60}accepted", self.passages[i]["text"][:120])]
        return (accepted or starts)[0]

    def candidates(self, r: dict, s: dict) -> list[int]:
        """Reciprocal rank fusion of the keyword lists and the meaning list, as Retrieval.candidates does it, with
        the rule's settings."""
        own = defaultdict(float)
        lists = [[h[0] for h in lst["hits"]] for lst in r["lists"]]
        sizes = [s["per_list"]] * len(lists) + [s["dense_n"]]
        for ids, size in zip(lists + [[h[0] for h in r["dense"]]], sizes):
            taken, per_doc = 0, Counter()
            for pid in ids:
                if not self.usable(pid):
                    continue
                doc = self.passages[pid]["doc"]
                if per_doc[doc] >= s["list_cap"]:
                    continue
                per_doc[doc] += 1
                own[pid] += 1 / (s["k"] + taken)
                taken += 1
                if taken >= size:
                    break
        doc_total = defaultdict(float)
        for pid, v in own.items():
            doc_total[self.passages[pid]["doc"]] += v
        def score(pid):
            p = self.passages[pid]
            w = s["field"] if p["key"] in FIELD else s["household"] if p["key"] in HOUSEHOLD else 1.0
            return w * (own[pid] + s["doc_bonus"] * (doc_total[p["doc"]] - own[pid]))
        # An article's second and third passages come after its first and keep `later` of their score.
        final, nth = {}, Counter()
        for pid in sorted(own, key=lambda i: (-score(i), -own[i], i)):
            doc = self.passages[pid]["doc"]
            final[pid] = score(pid) * (s["later"] if nth[doc] else 1.0)
            nth[doc] += 1
        out, per_doc, shown = [], Counter(), set()
        for pid in sorted(own, key=lambda i: (-final[i], -own[i], i)):
            doc = self.passages[pid]["doc"]
            show = self.best_answer(pid) if s["se_answer"] else pid
            if per_doc[doc] >= s["per_doc"] or show in shown:
                continue
            per_doc[doc] += 1
            shown.add(show)
            out.append(show)
            if len(out) >= s["limit"]:
                break
        return out

    def excerpts(self, r: dict, rule: str) -> list[dict]:
        if rule == "app":
            return [{"id": c["id"], **self.shown(c["id"]), "text": c["text"]} for c in r["app"] if c["id"] in self.passages]
        s = {**DEFAULT, **RULES[rule][1]}
        return [{"id": pid, **self.shown(pid), "text": cut(self.passages[pid]["text"], s["chars"])}
                for pid in self.candidates(r, s)]

    def shown(self, pid: int) -> dict:
        p = self.passages[pid]
        return {"title": p["title"], "source": p["source"], "key": p["key"]}


def same_articles(pool: Pool) -> str:
    """How closely this script's port of the app's rule (DEFAULT) picks the articles the app picked."""
    same = shared = total = 0
    for r in pool.records:
        app = [pool.passages[c["id"]]["doc"] for c in r["app"] if c["id"] in pool.passages]
        port = [pool.passages[i]["doc"] for i in pool.candidates(r, DEFAULT)]
        same += app == port
        shared += len(set(app) & set(port))
        total += len(app)
    return (f"Port check: this script's copy of the app's rule picks the app's articles in the app's order for {same} of "
            f"{len(pool.records)} questions, and {shared} of the app's {total} articles in all.")


def judge_shape(r: dict) -> dict:
    return {"question": r["question"], "history": [{"question": q} for q in r.get("history") or []]}


async def judge(pool: Pool, rules: list[str], top: int, out: Path, concurrency: int, effort: str) -> dict:
    cache = {e["key"]: e["score"] for e in cj.load_jsonl(out / "cache.jsonl")}
    todo = []
    for r in pool.records:
        shape, need, seen = judge_shape(r), [], set()
        for rule in rules:
            for e in pool.excerpts(r, rule)[:top]:
                k = jp.excerpt_key(shape, e)
                if k not in cache and k not in seen:
                    seen.add(k)
                    need.append(e)
        todo += [(shape, need[i:i + 10]) for i in range(0, len(need), 10)]
    print(f"{sum(len(n) for _, n in todo)} excerpts to judge in {len(todo)} requests")
    if not todo:
        return cache
    client, spend = cj.make_client(False, jp.fake_scores), cj.Spend()
    with (out / "cache.jsonl").open("a") as cache_file:
        async def work(item):
            shape, es = item
            for e, s in zip(es, await jp.judge_record(client, spend, shape, es, effort)):
                cache[jp.excerpt_key(shape, e)] = s
                cache_file.write(json.dumps({"key": jp.excerpt_key(shape, e), "score": s}) + "\n")
            cache_file.flush()
        results = await cj.run_all(todo, work, concurrency, "pool")
    failed = sum(1 for x in results if isinstance(x, Exception))
    print(f"judged: {spend.line()}" + (f"; {failed} requests failed" if failed else ""))
    return cache


def report(pool: Pool, rules: list[str], top: int, cache: dict) -> str:
    lines = [f"{len(pool.records)} questions ({pool.skipped} skipped: small talk or about the last answer). "
             f"Each rule's first {top} excerpts, and its first 4.", "",
             f"| rule | answers it in {top} | in 4 | helps in 4 | mean best in 4 | noise in 4 | forum share | not judged |",
             "|---|---|---|---|---|---|---|---|"]
    areas = sorted({r["area"] for r in pool.records})
    by_area = {rule: Counter() for rule in rules}
    for rule in rules:
        any3_top = any3_4 = any2_4 = unjudged = 0
        best4, noise, shown4, forum, first4 = [], 0, 0, 0, 0
        for r in pool.records:
            shape = judge_shape(r)
            es = pool.excerpts(r, rule)[:top]
            scores = [cache.get(jp.excerpt_key(shape, e), {}).get("score") for e in es]
            unjudged += sum(1 for x in scores if x is None)
            got = [x for x in scores if x is not None]
            four = [x for x in scores[:4] if x is not None]
            any3_top += any(x == 3 for x in got)
            any3_4 += any(x == 3 for x in four)
            any2_4 += any(x >= 2 for x in four)
            by_area[rule][r["area"]] += any(x == 3 for x in four)
            best4.append(max(four, default=0))
            noise += sum(1 for x in four if x <= 1)
            shown4 += len(four)
            forum += sum(1 for e in es[:4] if e["key"].startswith("se-"))
            first4 += len(es[:4])
        n = len(pool.records)
        name = "what the app chose when the pool was made" if rule == "app" else RULES[rule][0]
        lines.append(f"| `{rule}`: {name} | {any3_top} ({any3_top / n:.0%}) | {any3_4} ({any3_4 / n:.0%}) | "
                     f"{any2_4} ({any2_4 / n:.0%}) | {sum(best4) / n:.2f} | {noise / max(shown4, 1):.0%} | "
                     f"{forum / max(first4, 1):.0%} | {unjudged} |")
    lines += ["", "Questions with an answering excerpt in the first 4, by area:", "",
              "| area | questions | " + " | ".join(f"`{r}`" for r in rules) + " |", "|---|---|" + "---|" * len(rules)]
    for a in areas:
        n = sum(1 for r in pool.records if r["area"] == a)
        lines.append(f"| {a} | {n} | " + " | ".join(str(by_area[rule][a]) for rule in rules) + " |")
    return "\n".join(lines)


def show(pool: Pool, rule: str, top: int, cache: dict) -> None:
    for r in pool.records:
        shape = judge_shape(r)
        print(f"\n### {r['question']}" + (f"   (after: {' / '.join(r['history'])})" if r.get("history") else ""))
        for e in pool.excerpts(r, rule)[:top]:
            s = cache.get(jp.excerpt_key(shape, e), {})
            print(f"  {s.get('score', '?')}  [{e['key']}] {e['title'][:70]} :: {s.get('why', '')}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pool", help="a pool from scout-tools pool --json")
    ap.add_argument("--rules", default="app," + ",".join(RULES), help="rules to compare, in order")
    ap.add_argument("--top", type=int, default=10, help="how many of each rule's excerpts to judge")
    ap.add_argument("--out", default="build/judge-passages", help="folder with the judge's cache.jsonl")
    ap.add_argument("--no-judge", action="store_true", help="report from the cache only")
    ap.add_argument("--concurrency", type=int, default=6)
    ap.add_argument("--effort", default="low", choices=["low", "medium", "high", "xhigh", "max"])
    ap.add_argument("--show", help="print this rule's excerpts and scores for every question")
    args = ap.parse_args()
    pool, rules = Pool(args.pool), args.rules.split(",")
    for rule in rules:
        if rule != "app" and rule not in RULES:
            sys.exit(f"No rule named {rule}: {', '.join(RULES)}")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    if args.no_judge:
        cache = {e["key"]: e["score"] for e in cj.load_jsonl(out / "cache.jsonl")}
    else:
        cache = asyncio.run(judge(pool, rules, args.top, out, args.concurrency, args.effort))
    text = report(pool, rules, args.top, cache) + "\n\n" + same_articles(pool)
    (out / "pool.md").write_text(text + "\n")
    print(text)
    if args.show:
        show(pool, args.show, args.top, cache)


if __name__ == "__main__":
    main()
