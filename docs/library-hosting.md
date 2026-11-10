# Hosting the library

The app no longer downloads from the Survival LLM GitHub. Libraries are **Apple-hosted asset packs**
(free with the developer program, up to 200 GB per app). A public copy of the text goes on **Hugging Face**
to meet CC BY-SA's share-alike terms.

| Library | Asset pack ID | Path in the app's asset namespace |
|---|---|---|
| Essentials | `lite` | `lite/index.sqlite`, `lite/text/…` |
| Everything | `full` | `full/index.sqlite`, `full/text/…` |

Both use the `onDemand` policy: nothing downloads until someone picks a library. iOS keeps a downloaded
pack up to date in the background. The `BackcountryDownloader` extension and the
`group.com.collinbrowse.backcountryguide` app group make that work.

## Release a library

1. Check the licenses. This fails on any NC or ND source:
   `scripts/check-licenses.sh <library-folder>`
2. Build the pack: `scripts/build-asset-packs.sh <library-folder> lite` (or `full`). This writes `build/asset-packs/lite.aar`.
3. In App Store Connect, open the app record and upload the `.aar` with the
   [Transporter](https://apps.apple.com/us/app/transporter/id1450874784) app.
4. Test it with TestFlight internal testers, then submit the pack for review along with the next build.
5. Publish the text: `scripts/upload-huggingface.sh <library-folder> <your-hf-user>/backcountry-library`.
   You need `pip install -U huggingface_hub` and `hf auth login` first.

If you change the article counts or sizes, update `PackCatalog` in `Sources/LibraryStore.swift`. The app
replaces the size estimates with Apple's real figures once it can reach the App Store.

## Test locally (no App Store Connect)

Apple-hosted packs only download in TestFlight and App Store builds. For Xcode builds, serve the pack from your Mac:

1. Build a pack. `--allow-noncommercial` lets you test with the current library, but never upload that pack.
2. Follow Apple's [Testing asset packs locally](https://developer.apple.com/documentation/backgroundassets/testing-asset-packs-locally)
   to make a certificate and trust it on the phone.
3. Run `xcrun ba-serve --host <your-mac>.local build/asset-packs/lite.aar`.
4. On the phone, go to Settings › Developer › Background Assets Testing › Development Overrides and set the URL override to `https://<your-mac>.local:<port>`.
5. Run the app from Xcode.

To skip downloads entirely, copy a library folder to Files › On My iPhone › Backcountry › Library.
The app reads it as a "Custom" library.
