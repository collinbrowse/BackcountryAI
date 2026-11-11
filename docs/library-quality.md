# Keeping the library's content useful

Sources come in as whole websites and wikis, so they bring pages nobody should read in the field: database records
("265 Energy (Cookstove DB)" is an empty form plus map JSON), price tables, translations, site navigation, gene pages,
one-line forum answers. Four layers keep those out. Each one runs on every build, so a new source gets the same
treatment as the old ones.

## 1. Text checks on every article (automatic)

`library/quality.py` looks at the text itself and rejects an article that has:

- **almost no sentences:** under 250 characters of sentence-like lines (index pages, forms, figure-only pages,
  one-line answers);
- **not English prose:** under 18% of words are common English words like "the" and "of" (other languages, tables,
  lists of names);
- **mostly code or data:** over 3% braces, brackets or `=` (table pipes don't count) (JSON, wiki templates, data dumps).

`library/build_library.py` applies it to every source except the hand-picked ones (`HAND_PICKED`: the risk
references and government guides, where formulas would read as code) and prints how many articles each check left out. Every
rejected article goes to `left-out.tsv` in the `<library>-reports` folder beside it (not inside it, since a pack ships the whole folder), with the reason, title and address.

## 2. Rules for known junk families (by hand, from the audit)

Some pages pass the text checks but still don't belong: Energypedia's project databases and job ads, MedlinePlus
recipes and A-Z indexes, Ready.gov graphics collections and translated PDFs. `SKIP_PATHS` and `SKIP_TITLES` in
`build_library.py` drop them by address or title. When the audit turns up a new family, add a rule there with a
comment saying what it is.

## 3. The audit report (read before each release)

```bash
.venv/bin/python library/audit_library.py "$BACKCOUNTRY_DATA/library-lite" --out audit.md
```

For each source, it shows how many articles fail and why. It also lists a random sample of failures, so you can
spot good articles the checks wrongly dropped, and a sample of articles that passed but are thin, so you can spot
junk that got through. File-name titles and duplicate titles are listed at the end. `scripts/build-library.sh`
writes the report to `<library>-reports/quality-audit.md`. Spend ten minutes on it per release: each sample
line is a link.

## 4. Real questions (retrieval quality)

`scripts/check-answers.sh <library>` runs the 88 questions in `library/questions.tsv` through the app's search and
Apple's on-device model. It counts how many found a relevant article. `docs/library-weak-spots.md` records the
results and what's still missed. When users ask about something new, add it to `questions.tsv`.

## Tuning

The thresholds sit at the top of `library/quality.py`. To see what a change would do, run the audit on an existing
library with `--failing`. That lists every article that would fail.
