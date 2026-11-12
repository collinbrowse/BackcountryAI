# Building and hosting the library

The app offers one library, **Essentials** (277,281 articles; 0.81 GB download, 1.9 GB on the phone). It ships as
an **Apple-hosted asset pack**: free with the developer program, up to 200 GB per app. A public copy of the text
also goes on **Hugging Face**, to meet the share-alike terms of the CC BY-SA sources.

| Library | Asset pack ID | Download policy | Path in the app's asset namespace |
|---|---|---|---|
| Essentials | `lite` | `onDemand`: nothing downloads until someone taps Download | `lite/index.sqlite`, `lite/text/…` |

An "Everything" pack with Wikipedia was dropped on 2026-11-11. It was ten times the size, and its general articles
crowded out the practical ones. `library-full` is still built, but only as a step that Essentials reuses text from.
Never upload `full.aar`.

iOS keeps a downloaded pack up to date in the background. Two pieces make that work: the `BackcountryDownloader`
extension and the `group.com.collinbrowse.backcountryguide` app group. `project.yml` sets `BAHasManagedAssetPacks` and
`BAUsesAppleHosting`.

## Where things are

The table assumes `BACKCOUNTRY_DATA` is left at its default, `library.noindex/` in the repository root. Set it to put
the data somewhere else.

| What | Where |
|---|---|
| Downloaded sources (about 29 GB, resumable) | `$BACKCOUNTRY_DATA/raw/` and `$BACKCOUNTRY_DATA/zim/` |
| The app's library | `$BACKCOUNTRY_DATA/library-lite/` (`index.sqlite`, `text/`, `SOURCES.md`) |
| Quality reports, kept out of the pack | `$BACKCOUNTRY_DATA/library-lite-reports/` (`left-out.tsv`, `quality-audit.md`) |
| Built asset pack | `build/asset-packs/lite.aar` and `lite-manifest.json` (the current, ready-to-upload pack was moved to `library.noindex/asset-packs/`) |
| What the app expects | `PackCatalog` in `Sources/LibraryStore.swift` (article count and byte sizes) |
| Sources and licenses | `SOURCES.md`; `library/guides.tsv` lists the government guide pages |

## 1. One-time setup

```bash
/opt/homebrew/bin/python3.12 -m venv .venv
.venv/bin/pip install libzim lxml trafilatura pypdf
brew install poppler
```

You need about 40 GB free for the sources and both builds.

## 2. Build the library

```bash
scripts/build-library.sh
```

Prefix the command with `BACKCOUNTRY_DATA=/path/with/space` to build elsewhere.

The script:

1. **Downloads the sources.** Finished downloads are skipped, so a re-run is quick:
   - the manuals;
   - the Kiwix ZIMs;
   - the government guides in `library/guides.tsv`, falling back to the Internet Archive if a site is down;
   - the risk references.
2. **Builds `library-full`, then `library-lite`.** Essentials reuses the text already converted for `library-full`.
3. **Runs the quality filter.** `library/quality.py` rejects articles with almost no sentences, articles that aren't
   English prose, and articles that are mostly code or data. Every rejected article goes to `left-out.tsv` in the
   reports folder. See `docs/library-quality.md`.
4. **Checks each library:**
   - the license check fails on any non-commercial, no-derivatives or unlicensed source;
   - the search check runs real questions through the app's ranking;
   - the quality audit is written to `quality-audit.md` in the reports folder.

## 3. Check it before release

1. **Read `library-lite-reports/quality-audit.md`.** It lists, for each source:
   - articles that fail the checks;
   - articles that only just pass;
   - titles that are file names;
   - duplicate titles.

   To remove more, fix the cause in `library/build_library.py` (`SKIP_PATHS`, `SKIP_TITLES` or a source's own
   filter), then rebuild.
2. **Run retrieval and answers through Apple's model.** This needs a Mac with Apple Intelligence on:

   ```bash
   scripts/check-answers.sh library.noindex/library-lite
   ```

   - The last result was 88 of 89 questions finding the right article.
   - To judge the written answers, add `--answers` and run it with
     `QUESTIONS=library/answer-questions.tsv`.
   - Misses are tracked in `docs/library-weak-spots.md`.
3. **Update `PackCatalog`** in `Sources/LibraryStore.swift` if the article count or sizes changed.
   - Article count: `sqlite3 library.noindex/library-lite/index.sqlite "SELECT SUM(docs) FROM sources WHERE done=1"`.
   - `downloadBytes` is the size of `lite.aar` from step 4.
   - `unpackedBytes` is the size of the `library-lite` folder.

   Once the app can reach the App Store, it replaces these estimates with Apple's real figures.

## 4. Build the asset pack

```bash
scripts/build-asset-packs.sh library.noindex/library-lite lite
```

- It runs the license check again and refuses a library that fails it.
- It writes `build/asset-packs/lite.aar` and `lite-manifest.json`.
- The pack ID must be `lite`, to match `PackCatalog`.
- The `--allow-noncommercial` flag skips the license check. Use it only for a local test, and never upload that
  pack.

## 5. Upload to Apple

1. **Upload a build.** In Xcode, use Product › Archive, then Distribute App › App Store Connect. The asset pack
   attaches to the app's record, so the record and a build have to exist.
2. **Upload `lite.aar`** with the [Transporter](https://apps.apple.com/us/app/transporter/id1450874784) app. Sign in
   with the developer account and add the `.aar` file. `xcrun altool` also works from the command line.
3. **Wait for Apple to process it.** The pack then appears under the app's record in App Store Connect. See Apple's
   [Background Assets documentation](https://developer.apple.com/documentation/backgroundassets) for the current
   screens.
4. **Test in TestFlight.** Install the TestFlight build, tap Download on the Library screen, and check that:
   - the download finishes;
   - search works;
   - the library survives quitting and reopening the app.
5. **Submit the pack for review** together with the next App Store build.

To ship a new version of the library, rebuild, then repeat steps 4 and 5 with the same pack ID. iOS updates
downloaded copies in the background.

## 6. Publish the text on Hugging Face

```bash
.venv/bin/pip install -U huggingface_hub
hf auth login   # needs a write token
scripts/upload-huggingface.sh library.noindex/library-lite <your-hf-user>/backcountry-library
```

The script:

- refuses to upload a library that fails the license check;
- uploads the folder;
- writes a dataset card from `docs/huggingface-dataset-card.md`, with a table of sources and licenses.

Do this whenever you ship a new version of the pack.

Still to check before the first release: the NHS and CDC Yellow Book terms (see `SOURCES.md`).

## Testing on a phone without App Store Connect

Apple-hosted packs only download in TestFlight and App Store builds. In an Xcode build, Download does nothing.
There are two ways around that.

### Copy the library in with Finder (simplest)

1. Install the app from Xcode and open it once.
2. Plug in the phone, open Finder, select the iPhone, and open the **Files** tab.
3. Drag `library.noindex/library-lite` into **Backcountry**, then rename the copy to **Library**. It must end up as
   On My iPhone › Backcountry › Library, with `index.sqlite` directly inside. The copy is 1.8 GB and takes a few
   minutes.
4. Reopen the app. The Library screen shows the library as "Custom".

A downloaded asset pack takes priority over this folder. To test a new build of the library on a phone that already
has the pack, delete the pack from the Library screen first.

### Serve the pack from your Mac

This tests the real download path.

1. Build the pack (step 4).
2. Follow Apple's
   [Testing asset packs locally](https://developer.apple.com/documentation/backgroundassets/testing-asset-packs-locally)
   to make a certificate and trust it on the phone.
3. Run `xcrun ba-serve --host <your-mac>.local build/asset-packs/lite.aar`.
4. On the phone, go to Settings › Developer › Background Assets Testing › Development Overrides. Set the URL
   override to `https://<your-mac>.local:<port>`.
5. Run the app from Xcode and tap Download.

## The optional answer model (prototype)

Library › Lab can download Qwen 3.5 4B (about 3 GB). Unlike the library, it isn't an asset pack yet: it downloads
straight from Hugging Face, so it works in Xcode builds too. `docs/on-device-model-comparison.md` covers how to
benchmark it on a phone and how to decide whether to ship it. If it ships, it would become a second
Apple-hosted asset pack, released the same way as above.

Before a TestFlight build goes to anyone outside your own testing, decide whether the Lab screen stays in. It's
currently in every build.

## Cleaning up disk space

These can be deleted once you no longer need them:

- `library.noindex/asset-packs/full.aar` (8.5 GB), the dropped Wikipedia library;
- the build logs (`library.noindex/*.log`);
- the evaluation models in `~/.cache/huggingface` (about 20 GB).

Keep `raw/`, `zim/` and `library-full/` if you'll rebuild: without them the build downloads and converts
everything again.
