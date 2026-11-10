"""Download individual survival / first-aid manuals (PDFs) that are not in any Kiwix ZIM.

Usage: python3 library/fetch_manuals.py
Files land in library.noindex/raw/manuals/<group>/ with a manifest.json of titles and licenses.
Group: "us-gov" = U.S. government works (public domain). Non-commercial manuals (IFRC, WHO), the Emergency
Response Guidebook (not for resale) and Nuclear War Survival Skills (copyrighted 1986 additions) are left out.
Sources and terms were checked on 2026-10-23; see SOURCES.md.
"""
import json
import os
import subprocess

ARMY = "https://armypubs.army.mil/epubs/DR_pubs/DR_a/"
MANUALS = [
    ("us-gov", "USAF AFH 10-644: SERE Operations (survival, evasion, field medicine)",
     "https://static.e-publishing.af.mil/production/1/af_a3/publication/afh10-644/afh10-644.pdf"),
    ("us-gov", "US Army ATP 3-50.21: Survival", ARMY + "pdf/web/ARN12086_ATP%203-50x21%20FINAL%20WEB%202.pdf"),
    ("us-gov", "US Army ATP 4-02.11: Casualty Response, Tactical Combat Casualty Care and First Aid (2026)",
     ARMY + "ARN46159-ATP_4-02.11-000-WEB-1.pdf"),
    ("us-gov", "US Army TC 21-3: Cold Weather Survival and Operations", ARMY + "ARN45217-TC_21-3-000-WEB-1.pdf"),
    ("us-gov", "US Army ATP 4-25.12: Unit Field Sanitation", ARMY + "ARN44577-ATP_4-25.12-002-WEB-3.pdf"),
    ("us-gov", "US Army TB MED 577: Sanitary Control and Surveillance of Field Water Supplies",
     ARMY + "pdf/web/tbmed577.pdf"),
    ("us-gov", "US Army TB MED 507: Heat Stress Control and Heat Casualty Management",
     ARMY + "ARN43608-TB_MED_507-001-WEB-2.pdf"),
    ("us-gov", "FEMA: Are You Ready? An In-Depth Guide to Citizen Preparedness",
     "https://www.ready.gov/sites/default/files/2021-11/are-you-ready-guide.pdf"),
    ("us-gov", "FEMA CERT Basic Training Participant Manual",
     "https://www.ready.gov/sites/default/files/2019.CERT_.Basic_.PM_FINAL_508c.pdf"),
    ("us-gov", "Joint Trauma System: Prolonged Casualty Care Guidelines (2021)",
     "https://jts.health.mil/assets/docs/cpgs/Prolonged_Casualty_Care_Guidelines_21_Dec_2021_ID91v1.1.pdf"),
]
# The official sites refuse scripted downloads (HTTP 403, checked 2026-10-23); the Internet Archive has the same files.
FALLBACK = {
    "https://static.e-publishing.af.mil/production/1/af_a3/publication/afh10-644/afh10-644.pdf":
        "https://web.archive.org/web/2025id_/https://static.e-publishing.af.mil/production/1/af_a3/publication/afh10-644/afh10-644.pdf",
}
LICENSES = {"us-gov": "U.S. government work, public domain (17 U.S.C. 105)"}
# Some government sites refuse curl's default user agent.
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

ROOT = os.path.join(os.environ.get("BACKCOUNTRY_DATA") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "library.noindex"), "raw", "manuals")
for group in LICENSES:
    os.makedirs(os.path.join(ROOT, group), exist_ok=True)
manifest = {g: [] for g in LICENSES}
for n, (group, title, url) in enumerate(MANUALS):
    dest = os.path.join(ROOT, group, f"{n:02d}.pdf")
    if not (os.path.exists(dest) and open(dest, "rb").read(4) == b"%PDF"):
        for src in filter(None, (url, FALLBACK.get(url))):
            r = subprocess.run(["curl", "-L", "--fail", "-sS", "-A", UA, "--retry", "3", "-o", dest, src])
            ok = r.returncode == 0 and open(dest, "rb").read(4) == b"%PDF"
            if ok:
                break
        print(("ok      " if ok else "FAILED  ") + title, flush=True)
        if not ok:
            if os.path.exists(dest):
                os.remove(dest)
            continue
    manifest[group].append({"file": os.path.basename(dest), "title": title, "url": url, "license": LICENSES[group]})
for group, items in manifest.items():
    with open(os.path.join(ROOT, group, "manifest.json"), "w") as f:
        json.dump(items, f, indent=1)
print({g: len(v) for g, v in manifest.items()})
