"""Search check: runs real backcountry and emergency questions through the same search the app uses
(Sources/Library.swift) and reports whether a relevant article lands in the top five.

Usage: .venv/bin/python library/check_search.py <library-folder> [--verbose]
Exits non-zero if fewer than 90% of the questions find a relevant article.
The first 22 questions come from Survival LLM's evals/retrieval_eval.py (MIT); the rest are backcountry ones.
"""
import re
import sqlite3
import sys

QUESTIONS = [
    ("The power just went out. How long will the food in my fridge and freezer stay safe?", r"food|outage|refrigerat|freez"),
    ("Can I run my gas generator in the garage if I leave the big door open?", r"generator|carbon monoxide"),
    ("The tap water might be contaminated. How many drops of household bleach per gallon make it safe?",
     r"water|bleach|disinfect|purif"),
    ("How long do I need to boil water to make it safe to drink?", r"water|boil|purif"),
    ("What are the signs of carbon monoxide poisoning and what should I do?", r"carbon monoxide"),
    ("Someone is shivering hard and acting confused after being out in the cold. What do I do?", r"hypotherm|cold"),
    ("Someone cut their arm badly and it is bleeding a lot. What do I do?", r"bleed|wound|first aid|hemorrh"),
    ("I burned my hand on the stove. How should I treat it?", r"burn"),
    ("The power is out. How long can my insulin stay unrefrigerated?", r"insulin|diabet"),
    ("Is it safe to use candles for light during a blackout?", r"candle|outage|fire"),
    ("My phone is at 15% and the power is out. How do I make the battery last?", r"phone|battery|outage"),
    ("Can I charge my phone in my car with the engine running inside the garage?", r"carbon monoxide|car|garage"),
    ("A power line is down in my front yard. What should I do?", r"power line|downed|electric"),
    ("The water is off and the toilet won't flush. What can I do for a toilet?", r"toilet|sanitation|waste"),
    ("How do I keep warm in my house in winter if the power and heat are out?", r"cold|winter|warm|heat"),
    ("There has been a nuclear explosion nearby. What should I do?", r"nuclear|radiation|fallout"),
    ("Is canned food still safe to eat after it sat in floodwater?", r"flood|canned|food"),
    ("Is it safe to take ibuprofen that expired two years ago?", r"expir|ibuprofen|medic"),
    ("How do I make oral rehydration solution at home?", r"rehydrat|diarrh|dehydrat"),
    ("Someone working in the heat is confused, very hot and has stopped sweating. What do I do?", r"heat"),
    ("How can I tell if home-canned food might have botulism?", r"botul|canning|canned"),
    ("How much water should I store per person for an emergency?", r"water|emergency|supply|kit"),
    # Backcountry
    ("How do I treat early frostbite on my toes?", r"frostbite|cold"),
    ("My truck won't start and just clicks. What do I check?", r"start|battery|starter|click"),
    ("How do I start a fire with wet wood?", r"fire|wood|kindling"),
    ("A rattlesnake bit my friend's ankle on the trail. What should we do?", r"snake|bite|envenom"),
    ("My head is pounding and I feel sick after climbing to 11,000 feet. What is happening?", r"altitude|mountain"),
    ("What should I do if I meet a grizzly bear on the trail?", r"bear"),
    ("How do I know if a slope is likely to avalanche?", r"avalanche|snow"),
    ("A thunderstorm is coming and we are above treeline. What do we do?", r"lightning|thunder|storm"),
    ("Is stream water safe to drink if it looks clear, or do I need to filter it?", r"water|giardia|filter|purif"),
    ("I think I sprained my ankle hiking. How do I tell if it is broken and how do I splint it?",
     r"sprain|ankle|fracture|splint"),
    ("How do I treat a blister on my heel so I can keep hiking?", r"blister|foot"),
    ("How do I patch a flat bike tire on the trail?", r"tire|tyre|puncture|flat|tube"),
    ("I am lost in the woods. Should I stay put or try to walk out?", r"lost|survival|navigation|rescue"),
    ("How do I build an emergency shelter for one night in the snow?", r"shelter|snow|cold"),
]

STOPWORDS = set("""
a about above after again against all am an and any are as at be because been before being below between both but
by can could did do does doing down during each few for from further had has have having he her here hers herself
him himself his how i if in into is it its itself just me more most my myself no nor not now of off on once only or
other our ours ourselves out over own same she should so some such than that the their theirs them themselves then
there these they this those through to too under until up very was we were what when where which while who whom why
will with would you your yours yourself yourselves
""".split())
OFFICIAL = {"ready-gov", "cdc-travel", "medlineplus", "nhs-medicines", "military-medicine", "wikem", "medical-library",
            "water", "post-disaster", "food-prep", "survival-manuals", "first-aid-guides", "usda-canning", "risk"}


def query_words(q):
    return [w for w in re.findall(r"[\w']+", q.lower()) if len(w) > 1 and w not in STOPWORDS][:12]


def search(db, question, limit=5):
    """The app's search: all words first, any word if that finds too little; BM25 with official sources up."""
    words = query_words(question)
    terms = ['"' + w.replace('"', "") + '"' for w in words]
    hits = []
    for joiner in (" ", " OR "):
        hits = db.execute("SELECT rowid, rank FROM fts WHERE fts MATCH ? AND rank MATCH 'bm25(4.0, 1.0)' "
                          "ORDER BY rank LIMIT 300", (joiner.join(terms),)).fetchall()
        if len(hits) >= 3 or len(words) == 1:
            break
    if not hits:
        return []
    rank = dict(hits)
    rows = db.execute(f"""SELECT p.id, d.id, d.title, s.key FROM passages p JOIN docs d ON d.id = p.doc_id
        JOIN sources s ON s.id = d.source_id WHERE p.id IN ({",".join(str(h[0]) for h in hits)})""").fetchall()

    def weight(k):
        return 1.3 if k in OFFICIAL else 1.15 if k in ("wikipedia", "wikimed") else 1

    rows.sort(key=lambda r: rank[r[0]] * weight(r[3]))
    out, seen = [], set()
    for _, doc, title, key in rows:
        if doc not in seen:
            seen.add(doc)
            out.append((title, key))
        if len(out) >= limit:
            break
    return out


def main():
    folder = sys.argv[1]
    verbose = "--verbose" in sys.argv
    db = sqlite3.connect(f"file:{folder}/index.sqlite?immutable=1", uri=True)
    passed = 0
    for q, about in QUESTIONS:
        results = search(db, q)
        ok = any(re.search(about, t, re.I) for t, _ in results)
        passed += ok
        print(("PASS " if ok else "MISS ") + q)
        if verbose or not ok:
            for t, k in results:
                print(f"       [{k}] {t}")
    share = passed / len(QUESTIONS)
    print(f"\n{passed}/{len(QUESTIONS)} questions found a relevant article in the top 5 ({share:.0%})")
    sys.exit(0 if share >= 0.9 else 1)


if __name__ == "__main__":
    main()
