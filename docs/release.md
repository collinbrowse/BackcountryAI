# Releasing BackcountryAI

Everything that can be automated is. This page is the whole process: what runs by itself, the one-time setup only
you can do, and the short checklist for each release.

## What happens automatically

| When | What runs | Result |
|---|---|---|
| Pull request, or push to `main` | `CI` workflow | Build and unit tests |
| Push to `main` | `TestFlight` workflow | Signed build on TestFlight; "What to Test" is the commits since the last release |
| You press **Run workflow** on `Release` | `Release` workflow | Tests → fresh screenshots and preview video from that exact code → build → TestFlight → every App Store field filled in → submitted for review → `vX.Y.Z` tag and GitHub release |
| Push to `main` that touches `site/` | `Site` workflow | Privacy policy, support and home pages published |

After App Review approves a version, it releases itself as a 7-day phased rollout (`automatic_release` and
`phased_release` in `fastlane/Fastfile`).

What the release fills in on App Store Connect, and where each piece comes from:

| App Store field | Source |
|---|---|
| Name, subtitle, description, keywords, promotional text | `fastlane/metadata/en-US/*.txt` |
| Categories, copyright | `fastlane/metadata/*.txt` |
| Screenshots (8, iPhone 6.9") | Taken from the build by `UITests/ScreenshotTests.swift`; captions in `fastlane/screenshot-fixtures/captions.json` |
| App Preview video | Recorded from the build by the same test file (`testPreviewWalkthrough`) |
| What's New | `fastlane/release_notes.txt` if you edited it since the last release, otherwise the commit subjects since then |
| Support, marketing and privacy policy addresses | `APP_SITE_URL` + `site/` |
| Age rating | `fastlane/age_rating.json` |
| Review contact and notes | `REVIEW_*` secrets and `fastlane/review_notes.txt` |
| Export compliance, content rights, advertising identifier | Set in `project.yml` and `fastlane/Fastfile` |
| Version and build number | `MARKETING_VERSION` in `project.yml`; the build number is the last TestFlight build + 1 |
| Signing | Xcode automatic signing with the App Store Connect API key. No certificates or profiles are stored |

Screenshots and the video use a debug-only **screenshot mode** (`Sources/ScreenshotMode.swift`): a 600-article
sample of the real library and three scripted answers in `fastlane/screenshot-fixtures/`, so they look the same on
any machine. Release builds contain none of it.

## One-time setup (about an hour, only you can do these)

Do them in order. Each one says why it can't be automated.

### 1. Check the bundle ID is the one you want

The app is `com.collinbrowse.backcountryai`, with `.downloader` for the extension and the app group
`group.com.collinbrowse.backcountryai`. A bundle ID can never change after step 3.

### 2. Accept the agreements (Apple requires the account holder)

1. Open [App Store Connect › Business](https://appstoreconnect.apple.com/business).
2. Accept the **Paid Apps Agreement**, then add your bank account and tax forms. BackcountryAI is a paid app; without
   this it can be reviewed but not sold.

### 3. Create the app record (the API can't create apps)

1. Open [Certificates, Identifiers & Profiles › Identifiers](https://developer.apple.com/account/resources/identifiers/list)
   and click **+**. Register an **App ID** with bundle ID `com.collinbrowse.backcountryai`. Tick **App Groups** and
   **Increased Memory Limit**.
2. Register a second App ID, `com.collinbrowse.backcountryai.downloader`, with **App Groups** ticked.
3. Still under Identifiers, switch the filter to **App Groups**, click **+** and register
   `group.com.collinbrowse.backcountryai`. Then open each of the two App IDs, click **Configure** next to App Groups
   and select that group.
4. Open [App Store Connect › Apps](https://appstoreconnect.apple.com/apps), click **+ › New App**:
   - Platform: **iOS**
   - Name: **BackcountryAI** (if Apple says the name is taken, pick another and put the same text in
     `fastlane/metadata/en-US/name.txt`)
   - Primary language: **English (U.S.)**
   - Bundle ID: `com.collinbrowse.backcountryai`
   - SKU: `backcountryai`
   - User access: Full Access

### 4. Set the price (the pipeline deliberately never touches money)

In the app's page: **Pricing and Availability** → choose the price → choose countries → Save.

### 5. Create the API key (this is the credential everything else uses)

1. Open [Users and Access › Integrations › App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api).
2. Click **+**, name it `BackcountryAI CI`, access **Admin** (Admin is what lets the key create signing
   certificates), then **Generate**.
3. Download the `.p8` file. Apple lets you download it once. Note the **Key ID** and the **Issuer ID** at the top of
   the page.

### 6. Create the GitHub repository and give it the key

```bash
gh repo create BackcountryAI --private --source . --remote origin
```

```bash
git push -u origin main
```

Then add the secrets. Each command asks for the value, so nothing lands in your shell history:

```bash
gh secret set ASC_KEY_ID
```

```bash
gh secret set ASC_ISSUER_ID
```

```bash
base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8 | gh secret set ASC_KEY_P8_BASE64
```

```bash
gh secret set REVIEW_FIRST_NAME
```

```bash
gh secret set REVIEW_LAST_NAME
```

```bash
gh secret set REVIEW_PHONE
```

```bash
gh secret set REVIEW_EMAIL
```

`REVIEW_PHONE` needs the country code, like `+1 555 555 0100`. App Review uses these only to contact you.

Move the `.p8` file somewhere safe (a password manager) and delete it from Downloads.

### 7. Publish the privacy and support pages

App Store Connect requires a live privacy policy and support address.

1. Read `site/privacy.html` and `site/support.html` and edit anything that isn't true for you.
2. Set the contact address shown on them: `gh variable set SUPPORT_EMAIL --body "you@example.com"`
3. In the repository on GitHub: **Settings › Pages › Build and deployment › Source: GitHub Actions**.
   GitHub Pages on a private repository needs a paid GitHub plan. If you're on the free plan, either make the
   repository public or host the three files in `site/` anywhere else.
4. Run the workflow: `gh workflow run Site`. When it finishes, open the address it prints and check all three pages.
5. Tell the pipeline where they are (no trailing slash):
   `gh variable set APP_SITE_URL --body "https://<your-user>.github.io/BackcountryAI"`

### 8. Pick where the workflows run

The app runs on iOS 26 and later but is built with the iOS 27 SDK, so the runner needs Xcode 27 and the iPhone 18 Pro Max simulator. The workflows default to
GitHub's `macos-26` image and stop with a clear message if it has no Xcode 27. Two ways to change that:

- A different GitHub image: `gh variable set MACOS_RUNNER --body "macos-27"` (use whatever label GitHub lists).
- Your own Mac, which is free and already has everything:
  1. On GitHub: **Settings › Actions › Runners › New self-hosted runner**, choose macOS, and run the commands it
     shows on your Mac.
  2. `gh variable set MACOS_RUNNER --body "self-hosted"`
  3. Leave `./run.sh` running (or install it as a service with `./svc.sh install && ./svc.sh start`).

### 9. Upload the asset packs (they're built on your Mac from 29 GB of sources and a 3 GB model)

The Essentials library and the optional "Better answers" model are Apple-hosted asset packs, separate from the app
binary.

1. Build it: `docs/library-hosting.md`, steps 1 to 4.
2. Upload `lite.aar` with the **Transporter** app to the BackcountryAI record.
3. Wait for the "asset pack is ready" email. The pack is reviewed together with the first build that uses it.

4. Upload the Better answers model (pack `answers`): `scripts/release-model-pack.sh`. Until it's on App Store
   Connect, the Better answers card says it isn't available yet.

Repeat these only when the library or the model changes.

### 10. Answer App Privacy (Apple's API doesn't cover it; this lane uses your Apple ID once)

```bash
bundle exec fastlane privacy
```

It asks for your Apple ID, password and two-factor code, then publishes "Data Not Collected" from
`fastlane/app_privacy_details.json`. If it fails, do it by hand: App Store Connect › the app › **App Privacy** ›
Get Started › **No, we do not collect data** › Publish.

### 11. Confirm the answers I chose for you

These were filled in from reading the code. Change the file if any is wrong:

- `fastlane/age_rating.json`: frequent medical/treatment information, health topics, mild weapons references
  (the Army survival manual). Everything else "none".
- `fastlane/metadata/primary_category.txt` is `REFERENCE` and `secondary_category.txt` is `TRAVEL`.
  `MEDICAL` invites stricter review.
- `fastlane/review_notes.txt`: what App Review is told about the app.
- `fastlane/metadata/copyright.txt`: `2026 Collin Browse`.
- `Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` is a generated placeholder icon
  (`scripts/make-app-icon.swift`). Replace the PNG with a designed 1024×1024 icon, no transparency.
- `docs/library-hosting.md` still lists two open questions before a first release: the NHS and CDC Yellow Book
  terms.

### 12. First run

1. Push to `main` (or `gh workflow run TestFlight`). The first signed build registers the signing certificate and
   takes about 20 minutes. Install it from TestFlight on your iPhone, download the library, and ask a question
   in Airplane Mode.
2. Add yourself as an internal tester if you haven't: App Store Connect › the app › **TestFlight › Internal
   Testing › +**. This is needed once; later builds arrive on their own.
3. To send builds to external testers too, create a group under TestFlight, fill in **Test Information**, then
   `gh variable set TESTFLIGHT_GROUPS --body "Friends"`. The first external build waits for Beta App Review.

## Each release

1. Make sure `main` is what you want to ship and its `TestFlight` run is green.
2. Optional: write the "What's New" text in `fastlane/release_notes.txt` and commit it. If you skip this, the
   commit subjects since the last release are used. (The very first version has no What's New.)
3. Start it:

   ```bash
   gh workflow run Release
   ```

   To stop with everything filled in but not submitted, so you can look it over in App Store Connect first:

   ```bash
   gh workflow run Release -f submit=false
   ```

4. Wait for the "Ready for Distribution" email from Apple. It then rolls out by itself.
5. Start the next version:

   ```bash
   bundle exec fastlane bump version:1.1.0
   ```

   Commit `project.yml` and `BackcountryAI.xcodeproj`. The Release workflow refuses to run twice for one version.

### When Apple needs you

| What you see | What to do |
|---|---|
| Email: "issues with your submission" | Read the message in App Store Connect › the app › **App Review**. Reply there, or fix, push and run `Release` again; it replaces the rejected submission |
| Release fails at "precheck" | The log names the field and the rule. Edit the file under `fastlane/metadata/` and rerun |
| "name is already in use" | Change `fastlane/metadata/en-US/name.txt` (step 3) |
| Signing error mentioning certificates | The API key must be **Admin** (step 5). An account has a limit of distribution certificates; revoke unused ones under Certificates |
| Agreement banner in App Store Connect | Only the account holder can accept it (step 2). Uploads fail until you do |
| A serious bug after release | App Store Connect › the app › **Phased Release › Pause**, then ship a fix |

## Running it from your Mac

The workflows only call fastlane, so everything also runs locally.

```bash
bundle install
```

```bash
cp fastlane/.env.example fastlane/.env
```

Fill in `fastlane/.env`, then:

| Command | Does |
|---|---|
| `bundle exec fastlane test` | Unit tests |
| `bundle exec fastlane screenshots` | Screenshots → `fastlane/screenshots/en-US` |
| `bundle exec fastlane previews` | Preview video → `fastlane/app_previews/en-US` |
| `bundle exec fastlane beta` | Build and upload to TestFlight |
| `bundle exec fastlane metadata` | Refresh the listing (text, screenshots, video) without a new build |
| `bundle exec fastlane release` | The whole release |

`test`, `screenshots` and `previews` need no Apple credentials.

## Changing the screenshots or video

- **Captions:** `fastlane/screenshot-fixtures/captions.json`. The order there is the App Store order.
- **Which screens:** `UITests/ScreenshotTests.swift`. Each `snap("NN_name")` is one screenshot; add a caption with
  the same name.
- **The answers shown:** `fastlane/screenshot-fixtures/answers.json`.
- **The sample library:** after rebuilding the real library, run
  `.venv/bin/python library/make_demo_library.py` and commit the result.
- **The video:** `testPreviewWalkthrough` in the same test file. It must run 15 to 30 seconds between its two
  `PREVIEW_MARK` lines; a longer run is sped up to fit.
- **Another language:** add `fastlane/metadata/<locale>/`, then extend `LOCALE` in the Fastfile.

Run `bundle exec fastlane media` and open `fastlane/screenshots/en-US` to see the result before releasing.
