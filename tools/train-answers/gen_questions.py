"""Has Claude write realistic questions for training the "better answers" model: single questions and 2-3 turn
follow-up conversations across Scout's areas, in the voices people actually use (vague, dictated, troubleshooting,
"I don't have X"). Writes them in the formats scripts/check-answers.sh reads, so the app's real retrieval can build
the prompts:
  <out>/questions.tsv       area, question, about-regex
  <out>/conversations.tsv   id, area, question, about-regex (rows sharing an id are consecutive turns)
  <out>/questions-meta.jsonl  kind and style of each question, for reports

Questions that duplicate the hand-written test lists in library/ are dropped, so evals stay honest.

Usage: .venv/bin/python -I tools/train-answers/gen_questions.py [--n 1500] [--out-dir build/train-answers]
         [--conversation-share 0.25] [--concurrency 6] [--seed 1] [--dry-run]
"""
from __future__ import annotations

import argparse
import asyncio
import json
import math
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/grade-answers"))
import claude_jobs as cj  # noqa: E402

# Area -> (share of questions, subtopics to spread them over). Areas match library/questions.tsv.
AREAS = {
    "medical": (0.22, ["bleeding and wounds", "burns and scalds", "sprains, strains and fractures", "blisters and feet",
                       "hypothermia and frostbite", "heat exhaustion and heat stroke", "allergic reactions and stings",
                       "head injuries", "altitude sickness", "dehydration and stomach illness", "eye injuries",
                       "dental pain", "splinting and improvised gear", "medication on the trail", "chest pain or stroke signs",
                       "children and elderly on trips", "snakebite and spider bites", "ticks and tick-borne illness"]),
    "survival": (0.15, ["lost on a trail", "navigating without a map or compass", "using a compass and map",
                        "signaling for rescue", "unplanned night out", "building a fire in bad conditions",
                        "emergency shelter", "phone battery and offline maps", "river crossings",
                        "getting benighted on a climb", "group separated", "deciding to stay or move"]),
    "water": (0.09, ["filters and purifiers", "boiling and altitude", "chemical treatment doses", "finding water",
                     "frozen or broken filters", "questionable sources (cattle, mines, algae)", "storing water at home"]),
    "weather": (0.08, ["lightning and thunderstorms", "reading clouds and wind", "cold snaps and wind chill",
                       "heat waves", "flash floods", "avalanche conditions", "asking for a live forecast",
                       "fog and whiteout"]),
    "gear": (0.12, ["backpacking stoves that won't light", "tents and poles breaking", "sleeping bags and staying warm",
                    "headlamps and batteries", "water filters and pumps", "repairs with duct tape and cord",
                    "packing and weight", "boots and socks", "satellite messengers and PLBs", "solar chargers",
                    "camp lanterns and fuel", "trekking poles and snowshoes"]),
    "wildlife": (0.08, ["bears and food storage", "moose, elk and bison", "mountain lions", "snakes", "ticks and insects",
                        "rodents in camp", "dogs meeting wildlife", "identifying tracks and scat", "rabid animals"]),
    "vehicle": (0.14, ["truck won't start", "flat tires and jacks", "stuck in mud, sand or snow", "snowmobiles",
                       "ATVs and side-by-sides", "outboard motors and small boats", "chainsaws and small engines",
                       "dead batteries and jump starts", "overheating", "fuel problems and bad gas",
                       "dashboard warning lights", "trailers and hitches", "generators"]),
    "food": (0.06, ["food safety without a fridge", "foraging and edible plants", "fishing and cleaning fish",
                    "cooking at camp", "rationing on a long trip", "power outages and freezers"]),
    "home": (0.03, ["power outages", "carbon monoxide", "frozen pipes", "wood stoves"]),
    "disaster": (0.02, ["wildfire evacuation", "earthquake", "flooding at home"]),
    "radio": (0.01, ["handheld radios and repeaters", "GMRS and FRS", "satellite messengers"]),
}

STYLES = {
    "clear": "a clear, specific question with the useful details",
    "vague": "short and vague, the way people type when stressed (\"my leg hurts what do i do\")",
    "dictated": "dictated by voice: run-on, little punctuation, a brand or place name misheard (\"kathryn be free "
                "filter\" for Katadyn BeFree)",
    "troubleshoot": "something isn't working; they say what it does and often what they already tried",
    "constraint": "they say what they don't have or can't do (\"I don't have a map\", \"no cell signal\", "
                  "\"I can't move my arm\")",
    "emergency": "someone is hurt or in danger right now",
    "fact": "a plain fact lookup (how long, how much, is it safe)",
}
KINDS = ["howto", "troubleshoot", "fact", "emergency"]
ABOUT_OK = re.compile(r"^[a-z0-9' -]+(\|[a-z0-9' -]+)*$")

GUIDE = """\
You write realistic questions that people type or dictate into Scout, an offline field-guide app on their phone, \
during backcountry trips, outdoor work, vehicle trouble and emergencies. The questions will be used to train and \
test a small on-device model, so they must sound like real people, not like a textbook or a quiz.

Make them varied: different people (hunters, hikers, ranch hands, parents, snowmobilers, boaters, people at home \
in a storm), places, gear and brands, levels of panic, and lengths (from four words to three sentences). Put the \
details a real person would give: what they have with them, what they tried, where they are, how long ago. \
Don't invent questions that need live data unless asked for that style (the app has no internet). Don't number \
them, don't add answers, and don't make two questions that are the same situation reworded.

For each question also give:
- kind: howto (how to do something), troubleshoot (something isn't working), fact (a lookup), or emergency \
(someone hurt or in danger now).
- about: three to five lowercase keywords that would appear in the title of a helpful guide article, joined by \
"|", e.g. "burn|scald|blister" or "snowmobile|carburet|fuel". Plain words or word stems only."""

FOLLOW_UPS = """\
Follow-ups should be what people really say next: "I don't have that", "I already tried that and it didn't \
work", a detail that changes the picture ("it's electric start and it cranks"), a narrower question about one \
step, a related next problem, or a request for something the app can't do offline (a forecast, a map). The \
first turn must stand on its own; later turns may lean on it ("what about the blisters?")."""


def single_schema() -> dict:
    q = {"type": "object", "properties": {"question": {"type": "string"}, "kind": {"type": "string", "enum": KINDS},
                                          "about": {"type": "string"}},
         "required": ["question", "kind", "about"], "additionalProperties": False}
    return {"type": "object", "properties": {"questions": {"type": "array", "items": q}},
            "required": ["questions"], "additionalProperties": False}


def convo_schema() -> dict:
    t = {"type": "object", "properties": {"question": {"type": "string"}, "about": {"type": "string"}},
         "required": ["question", "about"], "additionalProperties": False}
    c = {"type": "object", "properties": {"kind": {"type": "string", "enum": KINDS},
                                          "turns": {"type": "array", "items": t}},
         "required": ["kind", "turns"], "additionalProperties": False}
    return {"type": "object", "properties": {"conversations": {"type": "array", "items": c}},
            "required": ["conversations"], "additionalProperties": False}


def plan(n: int, convo_share: float, rnd: random.Random) -> list:
    """Splits the work into requests: each names one area, a few subtopics and the styles to use."""
    jobs = []
    for area, (share, topics) in AREAS.items():
        want = max(4, round(n * share * 1.1))  # 10% extra: duplicates get dropped
        convo_turns = round(want * convo_share)
        singles = want - convo_turns
        for i in range(math.ceil(singles / 20)):
            count = min(20, singles - i * 20)
            styles = rnd.sample(list(STYLES), 4)
            jobs.append({"type": "single", "area": area, "count": count, "topics": rnd.sample(topics, min(3, len(topics))),
                         "styles": styles})
        convos = max(1, round(convo_turns / 2.5))
        for i in range(math.ceil(convos / 6)):
            count = min(6, convos - i * 6)
            jobs.append({"type": "convo", "area": area, "count": count,
                         "topics": rnd.sample(topics, min(3, len(topics))), "styles": rnd.sample(list(STYLES), 3)})
    return jobs


def job_text(job: dict) -> str:
    styles = "\n".join(f"- {s}: {STYLES[s]}" for s in job["styles"])
    if job["type"] == "single":
        return (f"Write {job['count']} questions in the area \"{job['area']}\", mostly about: "
                f"{', '.join(job['topics'])} (others in the area are fine too). Spread them across these styles, "
                f"roughly evenly:\n{styles}")
    return (f"Write {job['count']} short conversations in the area \"{job['area']}\", mostly about: "
            f"{', '.join(job['topics'])}. Each has 2 or 3 turns (mix both), from the same person, each turn "
            f"a new message after Scout answered the last one. Use these styles for the first turns:\n{styles}\n\n"
            + FOLLOW_UPS)


def norm(q: str) -> str:
    return " ".join(re.sub(r"[^a-z0-9 ]", " ", q.lower()).split())


def similar(a: set, b: set) -> bool:
    return len(a & b) / max(1, len(a | b)) >= 0.75


def clean_about(about: str, question: str) -> str:
    about = about.strip().lower().replace(", ", "|").replace(" | ", "|")
    if ABOUT_OK.match(about):
        return about
    words = [w for w in norm(question).split() if len(w) > 4][:4]  # a rough fallback; only used for reporting
    return "|".join(words) or "guide"


def fake_reply(kwargs: dict) -> str:
    text = kwargs["messages"][0]["content"][-1]["text"]
    m = re.search(r"Write (\d+) (questions|short conversations) in the area \"(\w+)\"", text)
    count, what, area = int(m.group(1)), m.group(2), m.group(3)
    rnd = random.Random(text)
    vocab = "stove truck filter bear creek ankle burn radio tent fire map dog snow rain knee boat saw tick moose".split()

    def fake_q():  # random words, so the near-duplicate filter keeps most of them
        return f"Fake {area} question: " + " ".join(rnd.sample(vocab, 6)) + "?"
    if what == "questions":
        return json.dumps({"questions": [{"question": fake_q(), "kind": rnd.choice(KINDS), "about": "stove|fuel"}
                                         for _ in range(count)]})
    return json.dumps({"conversations": [{"kind": "troubleshoot", "turns": [
        {"question": fake_q(), "about": "Fuel, Engine"} for _ in range(rnd.choice([2, 3]))]} for _ in range(count)]})


def existing_questions() -> set:
    """The hand-written test lists, so generated training data never contains an eval question."""
    out = set()
    for name in ("questions.tsv", "answer-questions.tsv", "conversations.tsv"):
        path = ROOT / "library" / name
        if path.exists():
            for line in path.read_text().splitlines()[1:]:
                cols = line.split("\t")
                if len(cols) >= 3:
                    out.add(norm(cols[2] if name == "conversations.tsv" else cols[1]))
    return out


async def main_async(args):
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    rnd = random.Random(args.seed)
    jobs = plan(args.n, args.conversation_share, rnd)
    print(f"{len(jobs)} requests for about {args.n} questions")
    client = cj.make_client(args.dry_run, fake_reply)
    spend = cj.Spend()

    async def work(job):
        text = await cj.ask(client, spend, system=[cj.cached(GUIDE)], content=[{"type": "text", "text": job_text(job)}],
                            schema=single_schema() if job["type"] == "single" else convo_schema(),
                            effort=args.effort)
        return json.loads(text)

    results = await cj.run_all(jobs, work, args.concurrency, "questions")
    spend.failed = sum(1 for r in results if isinstance(r, Exception))

    taken = existing_questions()
    seen_words: dict[str, list] = {}
    dropped = 0

    def fresh(area: str, q: str) -> bool:
        nonlocal dropped
        n = norm(q)
        words = set(n.split())
        if not n or n in taken or any(similar(words, w) for w in seen_words.get(area, [])):
            dropped += 1
            return False
        taken.add(n)
        seen_words.setdefault(area, []).append(words)
        return True

    singles, convos, meta = [], [], []
    for job, r in zip(jobs, results):
        if isinstance(r, Exception):
            continue
        area = job["area"]
        if job["type"] == "single":
            for q in r["questions"]:
                text = " ".join(q["question"].split())
                if fresh(area, text):
                    singles.append((area, text, clean_about(q["about"], text)))
                    meta.append({"area": area, "question": text, "kind": q["kind"], "styles": job["styles"]})
        else:
            for c in r["conversations"]:
                turns = [(" ".join(t["question"].split()), t["about"]) for t in c["turns"]]
                if not 2 <= len(turns) <= 3 or not fresh(area, turns[0][0]):
                    dropped += 1
                    continue
                cid = f"{area}-{len(convos) + 1:04d}"
                convos.append([(cid, area, q, clean_about(a, q)) for q, a in turns])
                for i, (q, _) in enumerate(turns):
                    meta.append({"area": area, "question": q, "kind": c["kind"], "styles": job["styles"],
                                 "conversation": cid, "turn": i + 1})

    with (out / "questions.tsv").open("w") as f:
        f.write("area\tquestion\tabout-regex\n")
        for row in singles:
            f.write("\t".join(row) + "\n")
    with (out / "conversations.tsv").open("w") as f:
        f.write("id\tarea\tquestion\tabout-regex\n")
        for convo in convos:
            for row in convo:
                f.write("\t".join(row) + "\n")
    with (out / "questions-meta.jsonl").open("w") as f:
        for m in meta:
            f.write(json.dumps(m) + "\n")
    turns = sum(len(c) for c in convos)
    print(f"Wrote {len(singles)} questions and {len(convos)} conversations ({turns} turns) to {out}; "
          f"dropped {dropped} duplicates or malformed")
    print(spend.line())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--n", type=int, default=1500, help="about how many questions (conversation turns count)")
    ap.add_argument("--out-dir", default="build/train-answers")
    ap.add_argument("--conversation-share", type=float, default=0.25, help="share of questions that are follow-up turns")
    ap.add_argument("--concurrency", type=int, default=6)
    ap.add_argument("--effort", default="medium", choices=["low", "medium", "high", "xhigh", "max"])
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--dry-run", action="store_true", help="fake questions, no network")
    asyncio.run(main_async(ap.parse_args()))


if __name__ == "__main__":
    main()
