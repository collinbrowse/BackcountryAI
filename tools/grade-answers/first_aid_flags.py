"""Screens answers to library/first-aid-questions.tsv for the mistakes that matter most on a first-aid card: the one
thing the answer must say, and the things it must not. No model and no network: each question carries its own
patterns in the file. A flag is a reason to read the answer, not a verdict; an answer with no flag can still be poor.

  scout-tools check <library> library/first-aid-questions.tsv --answers [--qwen DIR] --json RUN.json
  python3 -I tools/grade-answers/first_aid_flags.py RUN.json [RUN2.json ...] [--show]

Columns of the question file: area, question, a relevant title matches, card, a right answer, and three patterns:
must say, must not advise, must not appear. "Must not advise" is tried on each line of the answer, and a line
doesn't count when a negation comes before the end of the match ("Do not give her food" is fine; "Give him hot
chocolate, but don't let him walk" is not). "Must not appear" has no such let-out.
The questions are aimed at what a small model gets wrong with a card: copying the first steps whatever the stage,
dropping "not" from a warning, and leaving out when to get help. Run it after changing a first-aid card, more than
once per model: answers vary from run to run (docs/field-cards.md). A run may hold only some of the questions.
"""
from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QUESTIONS = ROOT / "library/first-aid-questions.tsv"
NEGATION = re.compile(r"\b(not|never|no|nothing|avoid|without|unless|stop)\b|n't", re.I)


def checks() -> dict[str, dict]:
    rows = list(csv.reader(QUESTIONS.open(encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE))
    return {r[1]: {"card": r[3], "right": r[4], "must": r[5], "advise": r[6], "appear": r[7]} for r in rows[1:]}


def flags(check: dict, record: dict) -> list[str]:
    answer = (record.get("answer") or "").replace("\u2019", "'")
    out = []
    # A card quoted word for word (Retrieval.quoting) is an answer; "I won't state a dose" is not.
    if record.get("declined") and "field card, word for word" not in answer:
        out.append("declined in fixed words")
    if check["card"] not in (record.get("cards") or []):
        out.append(f"card not attached (got {', '.join(record.get('cards') or []) or 'none'})")
    if check["must"] and not re.search(check["must"], answer, re.I | re.M):
        out.append("doesn't say what it must")
    for line in (l.strip() for l in answer.splitlines()):
        m = re.search(check["advise"], line, re.I) if check["advise"] else None
        if m and not NEGATION.search(line[: m.end()]):
            out.append("advises: " + line[:110])
            break
    if check["appear"] and (m := re.search(check["appear"], answer, re.I | re.M)):
        out.append("contains: " + answer[max(0, m.start() - 30): m.end() + 30].replace("\n", " "))
    return out


def main():
    files = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not files:
        sys.exit(__doc__)
    show = "--show" in sys.argv
    by_question = checks()
    runs = [{r["question"]: r for r in json.loads(Path(f).read_text())} for f in files]
    names = [Path(f).stem for f in files]
    flagged = [0] * len(runs)
    for number, (question, check) in enumerate(by_question.items(), 1):
        found = []
        for i, run in enumerate(runs):
            if (record := run.get(question)) is None:
                continue   # a run may hold only some of the questions
            f = flags(check, record)
            flagged[i] += bool(f)
            if f:
                found.append((names[i], f, record))
        if found:
            print(f"#{number} [{check['card']}] {question}")
            print(f"    right: {check['right']}")
            for name, f, record in found:
                print(f"    {name}: {'; '.join(f)}")
                if show and record:
                    print("        " + (record.get("answer") or "").strip().replace("\n", "\n        "))
    print()
    for name, n, run in zip(names, flagged, runs):
        print(f"{name}: {n} of {sum(q in run for q in by_question)} answers flagged")


if __name__ == "__main__":
    main()
