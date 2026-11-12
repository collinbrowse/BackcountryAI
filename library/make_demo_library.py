"""Builds the small demo library that App Store screenshots and preview videos are taken with.

It copies a few hundred real articles out of the full Essentials library: the best matches for every Guide topic,
SOS topic and scripted screenshot question, plus the first titles of every source so the source pages fill up.
The sources table keeps the real article counts, so the app shows the real library size.

Usage: .venv/bin/python library/make_demo_library.py [library-lite folder] [out folder]
  defaults: library.noindex/library-lite → fastlane/screenshot-fixtures/Library
Re-run it after rebuilding the library or adding topics; commit the result (a few MB).
"""
import json
import os
import re
import shutil
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "library.noindex", "library-lite")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "fastlane", "screenshot-fixtures", "Library")
PER_QUERY = 6       # best articles kept per topic or question
PER_SOURCE = 15     # alphabetical titles kept per source, for the source pages
MAX_BYTES = 40_000  # long manuals are skipped to keep the fixture small enough to commit
STOP = set("a about after all an and are as at be by can do does for from get how i if in into is it its me my "
           "of on or should so some someone than that the their them then they this to up what when where which "
           "who why will with you your".split())


def queries():
    """Every Guide/SOS topic (its search terms, else its title) and every scripted screenshot question."""
    out = []
    for name in ("Guide.swift", "Topics.swift"):
        src = open(os.path.join(ROOT, "Sources", name), encoding="utf-8").read()
        for m in re.finditer(r'Topic\(id: "[^"]+", title: "([^"]+)".*?(?:terms: "([^"]+)")?\)', src, re.S):
            out.append(m.group(2) or m.group(1))
    answers = os.path.join(ROOT, "fastlane", "screenshot-fixtures", "answers.json")
    if os.path.exists(answers):
        out += [a["question"] for a in json.load(open(answers, encoding="utf-8"))]
    return out


def words(q):
    return [w for w in re.findall(r"[\w']+", q.lower()) if len(w) > 1 and w not in STOP][:12]


def main():
    src = sqlite3.connect(f"file:{os.path.join(SRC, 'index.sqlite')}?mode=ro", uri=True)
    keep = set()
    for q in queries():
        terms = " OR ".join(f'"{w}"' for w in words(q))
        if not terms:
            continue
        rows = src.execute("SELECT p.doc_id FROM fts JOIN passages p ON p.id = fts.rowid "
                           "JOIN docs d ON d.id = p.doc_id WHERE fts MATCH ? AND d.length < ? "
                           "ORDER BY bm25(fts, 4.0, 1.0) LIMIT 200", (terms, MAX_BYTES)).fetchall()
        picked = []
        for (doc,) in rows:
            if doc not in picked:
                picked.append(doc)
            if len(picked) >= PER_QUERY:
                break
        keep.update(picked)
    for (sid,) in src.execute("SELECT id FROM sources WHERE done=1 AND docs>0"):
        keep.update(d for (d,) in src.execute(
            "SELECT id FROM docs WHERE source_id=? AND length < ? ORDER BY title COLLATE NOCASE LIMIT ?",
            (sid, MAX_BYTES, PER_SOURCE)))

    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(os.path.join(OUT, "text"))
    db = sqlite3.connect(os.path.join(OUT, "index.sqlite"), isolation_level=None)
    db.executescript("""
        PRAGMA journal_mode=DELETE;
        CREATE TABLE sources(id INTEGER PRIMARY KEY, key TEXT UNIQUE, label TEXT, topic TEXT,
                             origin TEXT, docs INT DEFAULT 0, done INT DEFAULT 0, license TEXT);
        CREATE TABLE files(id INTEGER PRIMARY KEY, path TEXT UNIQUE);
        CREATE TABLE docs(id INTEGER PRIMARY KEY, source_id INT, title TEXT, url TEXT, file_id INT, offset INT, length INT);
        CREATE INDEX docs_title ON docs(title COLLATE NOCASE);
        CREATE TABLE passages(id INTEGER PRIMARY KEY, doc_id INT, offset INT, length INT);
        CREATE VIRTUAL TABLE fts USING fts5(title, body, content='', contentless_delete=1,
                                            tokenize='porter unicode61 remove_diacritics 2');
        BEGIN;
    """)
    # Real counts: the app shows the size of the real library, not of this sample.
    for row in src.execute("SELECT id, key, label, topic, origin, docs, done, license FROM sources"):
        db.execute("INSERT INTO sources VALUES(?,?,?,?,?,?,?,?)", row)

    paths = dict(src.execute("SELECT id, path FROM files"))
    shards = {}  # source key -> (file id, open file)
    docs = src.execute(f"SELECT d.id, d.source_id, d.title, d.url, d.file_id, d.offset, d.length, s.key "
                       f"FROM docs d JOIN sources s ON s.id = d.source_id "
                       f"WHERE d.id IN ({','.join(map(str, sorted(keep)))}) ORDER BY s.key, d.title").fetchall()
    for doc_id, source_id, title, url, file_id, offset, length, key in docs:
        with open(os.path.join(SRC, "text", paths[file_id]), "rb") as f:
            f.seek(offset)
            body = f.read(length)
        if key not in shards:
            rel = f"{key}/0000.md"
            os.makedirs(os.path.join(OUT, "text", key), exist_ok=True)
            fid = db.execute("INSERT INTO files(path) VALUES(?)", (rel,)).lastrowid
            shards[key] = (fid, open(os.path.join(OUT, "text", rel), "wb"))
        fid, out = shards[key]
        start = out.tell()
        out.write(body)
        db.execute("INSERT INTO docs VALUES(?,?,?,?,?,?,?)", (doc_id, source_id, title, url, fid, start, length))
        for pid, poff, plen in src.execute("SELECT id, offset, length FROM passages WHERE doc_id=?", (doc_id,)):
            chunk = body[poff - offset: poff - offset + plen]
            db.execute("INSERT INTO passages VALUES(?,?,?,?)", (pid, doc_id, start + poff - offset, plen))
            db.execute("INSERT INTO fts(rowid, title, body) VALUES(?,?,?)",
                       (pid, title, chunk.decode("utf-8", "replace")))
    for _, f in shards.values():
        f.close()
    db.execute("COMMIT")
    db.execute("INSERT INTO fts(fts) VALUES('optimize')")
    db.execute("VACUUM")
    db.close()
    size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(OUT) for f in fs)
    print(f"Demo library: {len(docs)} articles, {size / 1e6:.1f} MB → {OUT}")


if __name__ == "__main__":
    main()
