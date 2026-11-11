"""Does an article read like something a person could use? Shared by build_library.py (which leaves out articles
that fail) and audit_library.py (which reports what passes and fails, source by source).

Articles fail for being mostly data or markup rather than sentences: database records ("265 Energy (Cookstove
DB)" is a form of empty fields plus a JSON map config), tables of numbers, link lists, navigation pages, or text in
another language. The checks are cheap and only look at the text, so they work for every source.
"""
import re

STOPWORDS = set("""a about after all also an and any are as at be because been but by can could do does for from
had has have he her his how if in into is it its may more most must no not of on one only or other our out should
so some such than that the their them then there these they this those to up use used was we were what when where
which while who will with would you your""".split())
WORD = re.compile(r"[A-Za-z][A-Za-z'’-]*")
MARKUP = re.compile(r"[{}\[\]<>=\\]|\":")  # not table pipes: tables are often the useful part
SENTENCE_END = re.compile(r"[.!?:;)\"”]\s*$")

MIN_PROSE_CHARS = 250  # sentences, not counting headings, lists of short items or form fields
MIN_STOPWORD_SHARE = 0.2  # of the words in sentences: English runs about 0.35-0.5, other languages near 0
MAX_MARKUP_SHARE = 0.03  # braces, brackets, pipes and the like per character


def measure(text):
    """Numbers that describe how readable an article is."""
    words = WORD.findall(text)
    prose, prose_words = 0, []
    for line in text.split("\n"):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        ws = WORD.findall(s)
        # A sentence-like line: several words, mostly letters, ends like a sentence or runs long.
        if len(ws) >= 8 and sum(map(len, ws)) >= 0.6 * len(s) and (SENTENCE_END.search(s) or len(ws) >= 20):
            prose += len(s)
            prose_words += ws
    return {
        "chars": len(text),
        "prose_chars": prose,
        "prose_share": prose / max(len(text), 1),
        # Counted in the sentences only, so an infobox or a list of drug names doesn't make English look foreign.
        "stopword_share": sum(w.lower() in STOPWORDS for w in prose_words or words) / max(len(prose_words or words), 1),
        "markup_share": len(MARKUP.findall(text)) / max(len(text), 1),
    }


def problems(text):
    """Why an article isn't worth keeping, or [] if it's fine."""
    m = measure(text)
    out = []
    if m["prose_chars"] < MIN_PROSE_CHARS:
        out.append("almost no sentences")
    if m["stopword_share"] < MIN_STOPWORD_SHARE:
        out.append("not English prose")
    if m["markup_share"] > MAX_MARKUP_SHARE:
        out.append("mostly code or data")
    return out
