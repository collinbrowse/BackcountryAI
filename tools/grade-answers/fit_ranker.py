"""Fits the weights of Retrieval.Ranker: a weighted sum of what search knows about a candidate (Retrieval.Signals)
that predicts the excerpt judge's score for it, so the excerpts most likely to answer the question come first.

Input is one or more pools from `scout-tools pool` (each candidate carries its signals, computed by the app's own
code). Every candidate is judged (judge_passages.py; cached), then ridge regression is fitted on one pool and
tested on the others, so no question is ranked by weights it helped fit. With one pool it is tested by 10-fold
cross-validation over questions. The weights printed at the end are fitted on everything: paste them into
Retrieval.Ranker.

Usage: .venv/bin/python -I tools/grade-answers/fit_ranker.py POOL.json [POOL2.json ...] [--out DIR] [--top 20]
         [--keep 4] [--no-judge] [--alpha 1.0]
"""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I leaves the script's folder off sys.path
import claude_jobs as cj  # noqa: E402
import judge_passages as jp  # noqa: E402
import pool_eval as pe  # noqa: E402


def rows_of(pool: pe.Pool, top: int, cache: dict):
    """(question index, signals, judge's score, place in fusion order) for every judged candidate."""
    X, y, q, place = [], [], [], []
    for qi, r in enumerate(pool.records):
        shape = pe.judge_shape(r)
        for i, c in enumerate(r["app"][:top]):
            if c["id"] not in pool.passages:
                continue
            e = {"id": c["id"], **pool.shown(c["id"]), "text": c["text"]}
            s = cache.get(jp.excerpt_key(shape, e), {}).get("score")
            if s is None:
                continue
            X.append(c["signals"]); y.append(s); q.append(qi); place.append(i)
    return np.array(X, dtype=float), np.array(y, dtype=float), np.array(q), np.array(place)


def ridge(X, y, alpha):
    """Weights and constant for score = constant + weights·signals (fitted on standardized signals)."""
    mu, sd = X.mean(0), X.std(0) + 1e-9
    Z = np.hstack([(X - mu) / sd, np.ones((len(X), 1))])
    A = Z.T @ Z + alpha * np.eye(Z.shape[1])
    A[-1, -1] -= alpha
    w = np.linalg.solve(A, Z.T @ y)
    weights = w[:-1] / sd
    return weights, float(w[-1] - (weights * mu).sum())


def kept(score, y, q, keep, among=None, cutoff=None):
    """How the `keep` best-scored candidates of each question do. `among`: only the first so many in fusion order."""
    a3 = a2 = noise = shown = empty = 0
    questions = sorted(set(q))
    for qi in questions:
        idx = np.where(q == qi)[0]
        if among is not None:
            idx = idx[:among]
        top = idx[np.argsort(-score[idx], kind="stable")][:keep]
        if cutoff is not None:
            top = top[score[top] >= cutoff]
        labels = y[top]
        a3 += (labels == 3).any(); a2 += (labels >= 2).any(); noise += (labels <= 1).sum()
        shown += len(labels); empty += len(labels) == 0
    n = len(questions)
    return (f"{a3} ({a3 / n:.0%}) | {a2} ({a2 / n:.0%}) | {noise / max(shown, 1):.0%} | {shown / n:.1f}"
            + (f" (none for {empty})" if empty else ""))


async def judge(pools, top, out, concurrency, effort, cache):
    todo = []
    for pool in pools:
        for r in pool.records:
            shape = pe.judge_shape(r)
            need = []
            for c in r["app"][:top]:
                if c["id"] in pool.passages:
                    e = {"id": c["id"], **pool.shown(c["id"]), "text": c["text"]}
                    if jp.excerpt_key(shape, e) not in cache:
                        need.append(e)
            todo += [(shape, need[i:i + 10]) for i in range(0, len(need), 10)]
    print(f"{sum(len(n) for _, n in todo)} candidates to judge in {len(todo)} requests")
    if not todo:
        return
    client, spend = cj.make_client(False, jp.fake_scores), cj.Spend()
    with (out / "cache.jsonl").open("a") as cache_file:
        async def work(item):
            shape, es = item
            for e, s in zip(es, await jp.judge_record(client, spend, shape, es, effort)):
                cache[jp.excerpt_key(shape, e)] = s
                cache_file.write(json.dumps({"key": jp.excerpt_key(shape, e), "score": s}) + "\n")
            cache_file.flush()
        results = await cj.run_all(todo, work, concurrency, "candidates")
    failed = sum(1 for x in results if isinstance(x, Exception))
    print(f"judged: {spend.line()}" + (f"; {failed} requests failed" if failed else ""))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pools", nargs="+", help="pools from scout-tools pool --json")
    ap.add_argument("--out", default="build/judge-passages", help="folder with the judge's cache.jsonl")
    ap.add_argument("--top", type=int, default=20, help="how many of each question's candidates to judge and rank")
    ap.add_argument("--keep", type=int, default=4, help="how many excerpts an answer is written from")
    ap.add_argument("--alpha", type=float, default=1.0, help="ridge penalty")
    ap.add_argument("--no-judge", action="store_true", help="fit from the cache only")
    ap.add_argument("--concurrency", type=int, default=6)
    ap.add_argument("--effort", default="low", choices=["low", "medium", "high", "xhigh", "max"])
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    pools = [pe.Pool(p) for p in args.pools]
    names = pools[0].records[0]["signal_names"]
    cache = {e["key"]: e["score"] for e in cj.load_jsonl(out / "cache.jsonl")}
    if not args.no_judge:
        asyncio.run(judge(pools, args.top, out, args.concurrency, args.effort, cache))
    data = [rows_of(p, args.top, cache) for p in pools]

    lines = ["| tested on | order | answers it | helps | noise | excerpts a question |", "|---|---|---|---|---|---|"]
    def report(label, X, y, q, place, predict):
        lines.append(f"| {label} | rank fusion, first {args.keep} of 10 | {kept(-place.astype(float), y, q, args.keep, among=10)} |")
        lines.append(f"| | rank fusion, first {args.keep} of {args.top} | {kept(-place.astype(float), y, q, args.keep)} |")
        lines.append(f"| | ranker, best {args.keep} of 10 | {kept(predict, y, q, args.keep, among=10)} |")
        lines.append(f"| | **ranker, best {args.keep} of {args.top}** | {kept(predict, y, q, args.keep)} |")
        for cutoff in (1.0, 1.25, 1.5):
            lines.append(f"| | ranker, up to {args.keep} scoring {cutoff} or more | {kept(predict, y, q, args.keep, cutoff=cutoff)} |")
        lines.append(f"| | the best {args.keep} there are in {args.top} | {kept(y, y, q, args.keep)} |")
    if len(pools) > 1:
        for i, (X, y, q, place) in enumerate(data):
            rest = [d for j, d in enumerate(data) if j != i]
            w, b = ridge(np.vstack([d[0] for d in rest]), np.concatenate([d[1] for d in rest]), args.alpha)
            report(f"{Path(args.pools[i]).stem} ({len(set(q))} questions), fitted on the rest", X, y, q, place, X @ w + b)
    else:
        X, y, q, place = data[0]
        rng, questions, predict = np.random.default_rng(0), np.array(sorted(set(q))), np.zeros(len(y))
        for fold in np.array_split(rng.permutation(questions), 10):
            test = np.isin(q, fold)
            w, b = ridge(X[~test], y[~test], args.alpha)
            predict[test] = X[test] @ w + b
        report(f"{Path(args.pools[0]).stem} ({len(questions)} questions), 10-fold", X, y, q, place, predict)
    w, b = ridge(np.vstack([d[0] for d in data]), np.concatenate([d[1] for d in data]), args.alpha)
    text = "\n".join(lines) + "\n\nFitted on all " + str(sum(len(d[1]) for d in data)) + " judged candidates:\n\n" \
        + "\n".join(f"- {n}: {v:+.3f}" for n, v in zip(names, w)) + f"\n- constant: {b:+.3f}\n\n" \
        + "static let weights: [Double]? = [" + ", ".join(f"{v:.3f}" for v in w) + "]\n" \
        + f"static let constant = {b:.3f}\n"
    (out / "ranker.md").write_text(text)
    print(text)


if __name__ == "__main__":
    main()
