# Launch plan

What has to happen before BackcountryAI goes on the App Store, and what comes after. The release mechanics
(fastlane lanes, workflows, one-time App Store Connect setup) are in [`docs/release.md`](docs/release.md); this file
tracks the work. Ask Claude to add, move or check off items and it edits this file.

## Pre-launch checklist

### Blockers

- [x] Version numbers: the three `Info.plist` files hard-coded `1.0` / `1`, which overrode `MARKETING_VERSION` and
      the build number fastlane passes, so every upload would have been "1.0 (1)". They now read the build settings
      (`project.yml` → `info.properties`).
- [x] Privacy manifest: `Sources/PrivacyInfo.xcprivacy` declares no tracking, no collected data, and the
      required-reason APIs (UserDefaults `CA92.1`, disk space `E174.1` / `85F4.1`).
- [x] Privacy report: a Release archive scanned with `scripts/privacy-scan.sh` showed MLXLMCommon reading file
      modification dates and mlx-swift carrying the `systemUptime` selector, with no manifests of their own. Both
      are now declared in the app's manifest (`C617.1`, `35F9.1`). Rerun the scan after a package update.
- [x] CDC Yellow Book: the online edition says CDC material is public domain; only the Yellow Book name and logo
      are HHS trademarks, and the app uses neither.
- [x] NHS medicines: dropped from the library, because nhs.uk's terms forbid charging for access to the content.
      MedlinePlus covers most of the same medicines. Rebuild and re-upload the `lite` pack before the first build
      if an older one is already in App Store Connect.
- [x] Medical disclaimer beyond Field cards: onboarding ("I'm a reference, not medical advice…") and a footer on
      every answer ("Reference, not medical advice"). App Review 1.4.1.
- [x] Emergency number: the SOS banner, onboarding, field cards, fixed replies, the model's instructions and its
      answers use the number for the phone's region (`Sources/Emergency.swift`): 911 in North America, 999 in the UK,
      000 in Australia, 112 where no other number is certain. The region is the phone's setting, not its location.
      Poison Control stays the U.S. number, labeled as such.

### App Store Connect (manual, once; steps in `docs/release.md`)

- [ ] Paid Apps Agreement, banking, tax
- [ ] App Small Business Program (15% commission instead of 30%)
- [ ] App IDs: `docs/release.md` step 3 registers the app and `.downloader`; check that automatic signing also
      creates `.widgets` (the Live Activity extension) on the first TestFlight build, or add it to that step
- [ ] Price and availability (see the emergency-number item for countries)
- [ ] Privacy and support pages live (`APP_SITE_URL`, GitHub Pages), contact address set
- [ ] App Privacy answers: Data Not Collected (`fastlane privacy`)
- [ ] Review notes: mention the download Live Activity, and that the larger model is the default on phones that
      can run it (`fastlane/review_notes.txt` calls it optional)
- [ ] Fix the size in `docs/release.md` step 9 ("3 GB model") if it means the shipped pack, which is 2.3 GB
- [ ] Both asset packs uploaded and attached to the first build (`scripts/release-pack.sh lite`,
      `scripts/release-model-pack.sh`)
- [ ] Public TestFlight group with a few real hikers and a WFR or two; collect feedback for a couple of weeks
- [ ] Featuring nomination (App Store Connect › Featuring › Nominations), at least 3 weeks before launch day

### Product decisions

- [ ] **Pricing.** Paid up front costs most of the downloads a free listing gets. Options: stay paid; free download
      with a one-time StoreKit 2 unlock after a few answers (search, Guide and Field mode stay free); or a free
      trial on the unlock. Decide before the first submission. Moving a paid app to free later is easy, and the
      reverse angers early buyers.
- [ ] **Cellular downloads.** The packs are 0.8 GB and 2.3 GB. Decide whether they may use cellular, and warn before
      a big download when the connection is expensive.
- [ ] **Review prompt.** SwiftUI `requestReview` after a good moment (for example the third answer with citations, or
      finishing the Trail ready checklist), at most once per version. Never after an urgent or SOS answer, a failed
      answer, or in Field mode.
- [ ] **Older iPhones.** Without Apple Intelligence the app searches and shows articles but writes no answers. Say so
      in the description and on the product page, so nobody pays for answers their phone can't write.

### Store listing and ASO

- [ ] Name (30 characters, weighted most): "BackcountryAI" uses 13. Test something like "BackcountryAI: Survival Guide"
      or "BackcountryAI: Offline First Aid".
- [ ] Keywords: "survival" and "offline" are already in the subtitle, so they waste keyword characters. Replace them
      with researched terms (see Automation). Don't repeat words from the name or subtitle, and don't name other apps.
- [ ] Description: lead with what the phone does with no signal, then citations, then Field mode, and mention the
      larger on-device model.
- [ ] Screenshot captions (`fastlane/screenshot-fixtures/captions.json`): use the words people search for. Apple
      hasn't confirmed it indexes caption text, but plain captions help conversion either way.
- [ ] Check the current required screenshot sizes (6.9" and 6.3" iPhone). iPhone Duo screenshots become required in
      April 2027 for apps built with the iOS 27.1 SDK.
- [ ] Product page header and search results art (iOS 27 Asset Library slots). fastlane doesn't upload these yet; port
      `header` from Silver Screen's `scripts/marketing.py` and the Asset Library upload from its `scripts/asc_media.py`.
- [ ] App icon: tinted variant and an Icon Composer `.icon` for Liquid Glass.
- [ ] Custom Product Pages, one per audience (hikers, hunters, overlanders, preppers, WFR students), each with its own
      keywords and screenshot order. They show in organic search when linked to keywords.
- [ ] Metadata in more locales: es-MX and others the US store may also index; then the app itself (`.xcstrings`).

### Automation and agents

- [ ] Release gate hook: port Silver Screen's `.claude/hooks/gate-release-actions.sh` so an agent asks before
      `fastlane release`, `beta`, `metadata`, a `v*` tag or a push to `main`. Put the App Store Connect secrets in a
      GitHub `release` environment that waits for your approval.
- [ ] Metadata linter in CI: character limits, keywords repeated from the name or subtitle, other apps' names, and
      required lines (the sources credit). Silver Screen's `marketing.py metadata` does this for `titles.json`.
- [ ] Keyword research skill: competitors' names and subtitles from the public iTunes Search API, plus search
      popularity from the Apple Ads API, turned into a keyword PR against `fastlane/metadata`.
- [ ] Screenshot QA: after `fastlane screenshots`, an agent checks every image (size, clipped captions, status bar,
      leftover fixture text) before anything uploads.
- [ ] Weekly digest: port Silver Screen's `scripts/weekly_digest.py` (downloads, conversion, ratings, new reviews from
      the App Store Connect API) to a Monday GitHub issue.
- [ ] Review replies: an agent drafts responses to new reviews and you approve each one before it posts.

## Post-launch

- [ ] In-App Events for the seasons: hiking season opening, hunting season, winter backcountry and avalanche season.
- [ ] Product Page Optimization tests on the icon and the first three screenshots.
- [ ] Halt the phased rollout automatically if a crash spike shows up.
- [ ] Localization of the app UI.
- [ ] Share an answer as an image card (with its citations) for group chats before a trip.
