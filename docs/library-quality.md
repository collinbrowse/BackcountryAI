# Keeping the library's content useful

Whole websites and wikis bring pages nobody needs in the field: database records, price tables, translations,
site navigation and one-line forum answers. Four layers keep them out. All of them run on every build, so new
sources get the same treatment.

## 1. Text checks (automatic)

`library/quality.py` rejects an article if it has any of these problems:

- **Almost no sentences:** under 250 characters of sentence-like lines.
- **Not English prose:** under 18% of words are common English words like "the" and "of".
- **Mostly code or data:** over 3% braces, brackets or `=` signs. Table pipes don't count.

The checks skip the hand-picked sources, the risk references and the government guides (`HAND_PICKED` in
`build_library.py`), because their formulas would read as code. Rejected articles are listed in
`<library>-reports/left-out.tsv`, with the reason.

## 2. Rules for known junk (by hand)

Some pages pass the text checks and still don't belong. Examples: Energypedia project databases and job ads,
MedlinePlus recipes and A–Z indexes, Ready.gov graphics collections and translated PDFs.

`SKIP_PATHS` and `SKIP_TITLES` in `library/build_library.py` drop these by address or title. When the audit turns
up a new kind of junk, add a rule there with a comment that says what it removes.

## 3. The audit (read every release)

`<library>-reports/quality-audit.md` is written on every build and every `/release-pack` run. For each source it
lists:

- failures and why they failed, to spot good articles that were wrongly dropped;
- articles that only just passed, to spot junk that got through;
- file-name titles and duplicate titles.

To see what a threshold change in `quality.py` would drop, run
`.venv/bin/python library/audit_library.py <library> --failing`. It lists every article that would fail.

## 4. Real questions

`scripts/check-answers.sh <library>` runs the questions in `library/questions.tsv` through the app's search and
Apple's on-device model. It counts how many find a relevant article. The results are in
`docs/library-weak-spots.md`.

When people ask about something new, add the question to `questions.tsv`.
