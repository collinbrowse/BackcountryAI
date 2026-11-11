"""Report on a built library's quality, source by source: how many articles fail library/quality.py's checks and
why, the failures and near-failures to look at, plus duplicate and file-name titles.

Usage: .venv/bin/python library/audit_library.py <library-folder> [--samples N] [--out report.md] [--failing]
--failing lists every article that fails (an existing library built before the filter, or to tune it).
Read the report before each release: anything that looks wrong goes into quality.py or build_library.py's skips.
"""
import collections
import os
import random
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from library.quality import measure, problems  # noqa: E402

FILE_NAME_TITLE = re.compile(r"^[a-z0-9]+([_-][a-z0-9]+){2,}$|\.(pdf|html?)$", re.I)


def articles(lib):
    db = sqlite3.connect(f"file:{os.path.join(lib, 'index.sqlite')}?immutable=1", uri=True)
    rows = db.execute("SELECT s.key, d.title, d.url, f.path, d.offset, d.length FROM docs d "
                      "JOIN sources s ON s.id = d.source_id JOIN files f ON f.id = d.file_id ORDER BY f.path, d.offset")
    rel, fh = None, None
    for key, title, url, path, offset, length in rows:
        if path != rel:
            if fh:
                fh.close()
            rel, fh = path, open(os.path.join(lib, "text", path), "rb")
        fh.seek(offset)
        text = fh.read(length).decode("utf-8", "replace")
        body = text.split("\n\n", 1)[1].rsplit("---", 1)[0] if "\n\n" in text else text
        yield key, title, url, body
    if fh:
        fh.close()


def main():
    args = sys.argv[1:]
    lib = args[0]
    samples = int(args[args.index("--samples") + 1]) if "--samples" in args else 8
    out = args[args.index("--out") + 1] if "--out" in args else None
    rng = random.Random(1)
    total = collections.Counter()
    failed = collections.Counter()
    reasons = collections.defaultdict(collections.Counter)
    fails = collections.defaultdict(list)
    borderline = collections.defaultdict(list)
    titles = collections.defaultdict(list)
    for key, title, url, body in articles(lib):
        total[key] += 1
        titles[(key, title.lower())].append(url)
        why = problems(body)
        if why:
            failed[key] += 1
            for r in why:
                reasons[key][r] += 1
            fails[key].append((title, url, why))
        else:
            m = measure(body)
            if m["prose_chars"] < 600 or m["stopword_share"] < 0.25:
                borderline[key].append((title, url, m))
    lines = [f"# Library quality audit: {os.path.basename(os.path.normpath(lib))}", "",
             f"{sum(total.values()):,} articles, {sum(failed.values()):,} fail the checks in library/quality.py.", "",
             "| Source | Articles | Fail | Share | Why |", "|---|---|---|---|---|"]
    for key in sorted(total, key=lambda k: -failed[k] / total[k]):
        why = ", ".join(f"{r} {n:,}" for r, n in reasons[key].most_common())
        lines.append(f"| {key} | {total[key]:,} | {failed[key]:,} | {failed[key] / total[key]:.0%} | {why} |")
    dupes = [(k, t, urls) for (k, t), urls in titles.items() if len(urls) > 1]
    names = [(k, t) for (k, t) in titles if FILE_NAME_TITLE.search(t)]
    lines += ["", f"Duplicate titles within a source: {len(dupes):,}. Titles that look like file names: {len(names):,}."]
    for key in sorted(total):
        lines += ["", f"## {key}"]
        if fails[key]:
            lines.append(f"Failing ({len(fails[key]):,}), a sample:")
            for title, url, why in (fails[key] if "--failing" in args
                                    else rng.sample(fails[key], min(samples, len(fails[key])))):
                lines.append(f"- {title} ({'; '.join(why)}) {url}")
        if borderline[key]:
            lines.append(f"Passing but thin ({len(borderline[key]):,}), a sample:")
            for title, url, m in rng.sample(borderline[key], min(samples, len(borderline[key]))):
                lines.append(f"- {title} (prose {m['prose_chars']} chars, stopwords {m['stopword_share']:.2f}) {url}")
        for k, t in [n for n in names if n[0] == key][:samples]:
            lines.append(f"- file-name title: {t}")
        for k, t, urls in [d for d in dupes if d[0] == key][:samples]:
            lines.append(f"- duplicate title: {t} ({len(urls)} copies)")
    report = "\n".join(lines) + "\n"
    if out:
        open(out, "w").write(report)
    print(report if not out else "\n".join(lines[:len(total) + 8]))


if __name__ == "__main__":
    main()
