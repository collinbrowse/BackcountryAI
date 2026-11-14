"""Dry-run only: turns question TSVs into made-up check-answers records, so the rest of the pipeline can be tested
on a machine without the library, Apple Intelligence or an API key. Prompts are built like Retrieval.prompt with
the app's real instructions (read from Sources/Retrieval.swift), but the excerpts are fake.

Usage: python3 -I tools/train-answers/fake_records.py <out.json> <questions.tsv|conversations.tsv> ... [--answers]
         [--qwen]
--answers fills in a canned answer for every record (for testing the grader); --qwen marks them as Qwen's and
words them differently, so two fake runs can be compared.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def swift_string(name: str) -> str:
    """A `static let <name> = \"\"\"...\"\"\"` multi-line string from Sources/Retrieval.swift, with Swift's rules: the
    closing delimiter's indent is stripped and a trailing backslash joins two lines."""
    src = (ROOT / "Sources/Retrieval.swift").read_text()
    m = re.search(rf'static let {name} = """\n(.*?)\n( *)"""', src, re.S)
    if not m:
        sys.exit(f"Couldn't find Retrieval.{name} in Sources/Retrieval.swift")
    indent = len(m.group(2))
    out = ""
    for line in m.group(1).split("\n"):
        line = line[indent:]
        out += line[:-1] if line.endswith("\\") else line + "\n"
    return out.rstrip("\n")


def prompt(question: str, sources: list, history: list, kind: str, troubleshoot_shape: str) -> str:
    """A rough port of Retrieval.prompt as of 2026-11 (only used for fakes; the real prompts come from
    check-answers, so this doesn't need to track every wording change)."""
    p = "WHAT THEY TOLD YOU (only this describes their situation):\n"
    if history:
        for i, t in enumerate(history):
            room = 500 if i == len(history) - 1 else 240
            p += f"Earlier they asked: {t['question']}\nYou answered (shortened): {t['answer'][:room]}\n"
        p += "This is a follow-up. Answer the new question; don't repeat what you already said.\n"
    p += f"Their question: {question}\n\n"
    if not sources:
        p += "LIBRARY ARTICLES: none matched this question.\n\n"
    else:
        p += "LIBRARY ARTICLES (about other people's situations; use only what fits theirs):\n"
        for i, s in enumerate(sources, 1):
            p += f"[{i}] {s['title']} ({s['source']})\n{s['text']}\n\n"
    if kind == "troubleshoot" and troubleshoot_shape:
        p += troubleshoot_shape + "\n\n"
    return p + f"Now answer their question: {question}"


def guess_kind(q: str) -> str:
    q = q.lower()
    if re.search(r"bleed|not breathing|unconscious|chest pain|stroke|anaphyla|can't breathe|hypotherm", q):
        return "emergency"
    if re.search(r"won't|wont|doesn't|isn't|not working|keeps|stalls|dies|won t", q):
        return "troubleshoot"
    if re.search(r"^how (do|can|should)|what should i do|^can i", q):
        return "howto"
    return "fact"


def fake_sources(about: str, n: int) -> list:
    words = [w for w in re.split(r"[|()\\.*?+]", about) if len(w) > 2][:3] or ["field"]
    return [{"title": f"{w.title()} basics", "source": "Fake Guide",
             "text": f"Made-up excerpt about {w}. " * 30} for w in words[:n]]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) < 2:
        sys.exit(__doc__)
    answers = "--answers" in sys.argv
    engine = "qwen" if "--qwen" in sys.argv else "apple"
    instructions = swift_string("instructions")
    try:
        shape = swift_string("troubleshootShape")
    except SystemExit:
        shape = ""
    records = []
    for tsv in args[1:]:
        rows = [line.split("\t") for line in Path(tsv).read_text().splitlines()[1:] if line.strip()]
        convo = Path(tsv).read_text().startswith("id\t")
        history, last_id = [], None
        for i, row in enumerate(rows):
            if convo:
                cid, area, q, about = row[:4]
                if cid != last_id:
                    history, last_id = [], cid
            else:
                area, q, about = row[:3]
                history = []
            sources = fake_sources(about, 0 if i % 7 == 6 else 3)  # every seventh question finds nothing
            answer = (f"Here is the short {engine} answer about {area} [1].\n1. Do the first thing.\n2. Then this."
                      if answers else "")
            kind = guess_kind(q)
            records.append({"area": area, "question": q, "kind": kind, "history": list(history),
                            "instructions": instructions, "prompt": prompt(q, sources, history, kind, shape),
                            "sources": sources, "answer": answer, "engine": engine, "seconds": 1.0})
            if convo:  # the next turn sees this one as history, answered
                history.append({"question": q, "answer": answer or f"Fake earlier answer to: {q}"})
    Path(args[0]).parent.mkdir(parents=True, exist_ok=True)
    Path(args[0]).write_text(json.dumps(records, indent=1))
    print(f"Wrote {len(records)} fake records to {args[0]}")


if __name__ == "__main__":
    main()
