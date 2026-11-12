# Building and releasing the library

The app has one library, **Essentials**, shipped as an Apple-hosted asset pack:

| Pack ID | Download policy | Files in the app |
|---|---|---|
| `lite` | `onDemand`: downloads when someone taps Download | `lite/index.sqlite`, `lite/text/…` |

iOS keeps a downloaded pack up to date through the `BackcountryAIDownloader` extension and the
`group.com.collinbrowse.backcountryai` app group. A copy of the text is also published on Hugging Face, which
the CC BY-SA sources require.

## Where things are

The data folder, `$BACKCOUNTRY_DATA`, defaults to `library.noindex/` in the main checkout.

| What | Where |
|---|---|
| Downloaded sources (the Kiwix archives of WikiMed, MedlinePlus, Stack Exchange and the rest) | `$BACKCOUNTRY_DATA/zim/` (27 GB) and `raw/` (0.1 GB) |
| The library | `$BACKCOUNTRY_DATA/library-lite/` |
| Quality reports, kept out of the pack | `$BACKCOUNTRY_DATA/library-lite-reports/` |
| Built pack and release summary | `build/asset-packs/` |
| Article count and sizes the app shows | `PackCatalog` in `Sources/LibraryStore.swift` |
| Upload credentials, git-ignored | `.asc.env` |

## Release

In Claude Code, from the main checkout:

```
/release-pack lite
```

The command runs `scripts/release-pack.sh`, which stops at the first problem. In order, it:

1. checks the App Store Connect key;
2. runs the license check, the search check and the quality audit;
3. builds `lite.aar`;
4. updates `PackCatalog`;
5. uploads the pack with `xcrun altool --upload-asset-pack --wait`, which returns once Apple has processed it.

The agent then reviews the audit, commits the `PackCatalog` change and reports the new version.

| Option | What it does |
|---|---|
| `--rebuild` | Downloads the sources and rebuilds the library first (hours) |
| `--hf user/name` | Also publishes the text on Hugging Face (do this every release) |
| `--no-upload` | Does everything except the upload |
| `--force` | Releases even if the search check is below target |

Without `--rebuild`, a release takes about 3 minutes plus the upload. Two steps stay manual in App Store Connect,
because Apple offers no command for them:

1. test the new version with TestFlight;
2. submit it for review with the next build.

## The Better answers model

The optional larger model (Qwen 3.5 4B, see `docs/on-device-model-comparison.md`) is a second on-demand pack,
`answers`, released the same way:

```bash
scripts/release-model-pack.sh
```

It downloads the pinned model from Hugging Face, drops the image weights, builds `build/asset-packs/answers.aar`
(2.3 GB) and uploads it. Pass `--no-upload` to stop after the build. If the size changes, update
`BetterModel.estimatedDownloadBytes` and `unpackedBytes`. Then test it in TestFlight and submit it for review with
the next build, like the library.

## One-time setup (only before your first release)

1. **Python and tools:**

   ```bash
   /opt/homebrew/bin/python3.12 -m venv .venv
   .venv/bin/pip install libzim lxml trafilatura pypdf huggingface_hub
   brew install poppler
   ```

2. **App Store Connect API key:**
   1. In App Store Connect, go to Users and Access › Integrations › App Store Connect API and create a Team key
      with the App Manager role.
   2. Save the `.p8` file as `~/private_keys/AuthKey_<KEY_ID>.p8`. Apple lets you download it only once.
   3. Copy `.asc.env.example` to `.asc.env` and fill in the key ID, the Issuer ID and the app's Apple ID.

3. **Hugging Face:** run `.venv/bin/hf auth login` with a write token. You only need this for `--hf`.

## What the build does

`scripts/build-library.sh`, run by `--rebuild`, does three things:

1. **Downloads every source** listed in `SOURCES.md`. Interrupted downloads resume.
2. **Builds `library-full`, then `library-lite`.** The `library-full` build includes Wikipedia but only exists as a
   step: Essentials reuses its converted text, and the app never ships it.
3. **Drops junk articles** with the quality filter. The rejected ones are listed in `left-out.tsv`.

To add a source, see `SOURCES.md` for what's allowed. Then add the source to `library/build_library.py`, or to
`library/guides.tsv` if it's a single web page. `docs/library-quality.md` covers the quality checks.

## Testing on a phone without App Store Connect

Apple-hosted packs only download in TestFlight and App Store builds. For an Xcode build, copy the library in
instead:

1. Install the app from Xcode and open it once.
2. In Finder, select the iPhone and open the Files tab.
3. Drag `library-lite` into BackcountryAI, then rename the copy to `Library`.

The app shows it as a "Custom" library. A downloaded pack takes priority over this copy, so delete the pack first
if the phone has one.

To test the real download path, serve the pack from your Mac with `xcrun ba-serve`, following Apple's
[Testing asset packs locally](https://developer.apple.com/documentation/backgroundassets/testing-asset-packs-locally).
