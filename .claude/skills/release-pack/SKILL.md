---
name: release-pack
description: Release a library as an Apple-hosted asset pack, from checks to App Store Connect upload. Run only when the user asks.
argument-hint: "<pack-id> [--rebuild] [--no-upload] [--hf user/name] [--force]"
disable-model-invocation: true
---

Release the asset pack the user named: `$ARGUMENTS` (default pack ID `lite`, Essentials).

Work from the repository's main checkout (the folder that has `library.noindex/`). In a worktree, pass
`--library <main checkout>/library.noindex/library-<pack-id>`.

1. **Preflight.**
   - `.asc.env` exists with `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_APP_ID`, unless `--no-upload` was given. If
     it's missing, stop and tell the user what to fill in from `.asc.env.example`. Never ask for or print the
     `.p8` key's contents.
   - The working tree is clean apart from your own changes.
2. **Run the release** in the background and wait for it to finish. Uploads and `--rebuild` take a long time:

   ```bash
   scripts/release-pack.sh $ARGUMENTS
   ```

3. **If it stops,** read the message:
   - **Search check below target:** show the misses and ask the user before rerunning with `--force`.
   - **License check failed:** a source with a non-commercial or no-derivatives license got in. Find it in
     `library/build_library.py` and `SOURCES.md`. Never release that pack.
   - **Credentials or upload failed:** report the `altool` error from `build/asset-packs/<id>-upload.log`.
4. **Review the quality audit** (`<library>-reports/quality-audit.md`). Report any source whose failures or
   thin passes jumped since the last release, with a few example titles.
5. **Commit the PackCatalog update.** The script rewrites the sizes in `Sources/LibraryStore.swift`. If it
   printed "No PackCatalog entry", add an entry first, using the existing one as the model. Commit with a
   message naming the pack and its article count. Don't push.
6. **Report:**
   - articles, download size and on-phone size, compared with the previous values in the diff;
   - the upload result and the new version number, from `build/asset-packs/<id>-release.md`;
   - what is left by hand: test the pack in TestFlight, then submit it for review with the next build in App
     Store Connect;
   - publishing on Hugging Face, if `--hf` wasn't passed (the CC BY-SA sources need it once per release).
