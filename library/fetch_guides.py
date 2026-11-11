"""Download U.S. government safety pages that fill the library's weak spots (bears, lightning, flash floods, cold
water, avalanches, chainsaws, downed power lines, carbon monoxide, food after floods...).

Usage: .venv/bin/python library/fetch_guides.py
Reads library/guides.tsv (title, url) and writes library.noindex/raw/guides/ with a manifest.json for
build_library.py. Every page is a U.S. federal government work (public domain, 17 U.S.C. 105); see SOURCES.md.
Sites that refuse scripted downloads are fetched from the Internet Archive's copy instead.
"""
import csv
import hashlib
import json
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("BACKCOUNTRY_DATA") or os.path.join(HERE, "..", "library.noindex")
OUT = os.path.join(ROOT, "raw", "guides")
LICENSE = "U.S. government work, public domain (17 U.S.C. 105)"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"


def fetch(url, dest):
    for src in (url, "https://web.archive.org/web/2026id_/" + url):
        r = subprocess.run(["curl", "-L", "--fail", "-sS", "--compressed", "-A", UA, "--retry", "2", "-m", "120",
                            "-o", dest, src], capture_output=True)
        if r.returncode == 0 and os.path.getsize(dest) > 2000:
            return True
    if os.path.exists(dest):
        os.remove(dest)
    return False


def main():
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(HERE, "guides.tsv")) as f:
        rows = [r for r in csv.DictReader(f, delimiter="\t") if r["url"].strip()]
    manifest, failed = [], []
    for row in rows:
        url, title = row["url"].strip(), row["title"].strip()
        ext = ".pdf" if url.lower().split("?")[0].endswith(".pdf") else ".html"
        name = hashlib.sha1(url.encode()).hexdigest()[:12] + ext
        dest = os.path.join(OUT, name)
        if ext == ".html" and os.path.exists(dest[:-5] + ".pdf"):
            name, dest = name[:-5] + ".pdf", dest[:-5] + ".pdf"
        if not os.path.exists(dest) and not fetch(url, dest):
            failed.append(title)
            print("FAILED  " + title, flush=True)
            continue
        if dest.endswith(".html") and open(dest, "rb").read(5) == b"%PDF-":  # a .htm link that serves a PDF
            os.rename(dest, dest[:-5] + ".pdf")
            name = name[:-5] + ".pdf"
        manifest.append({"file": name, "title": title, "url": url, "license": LICENSE, "kind": "web"})
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    print(f"{len(manifest)} guides, {len(failed)} failed")


if __name__ == "__main__":
    main()
