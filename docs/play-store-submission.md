# Genzeb — Google Play submission checklist

App: **Genzeb** · package `com.nitsuh.genzeb` · category Finance · audience 18+
Policy facts checked on 2026-09-25 (sources linked inline). Re-check before each submission; Play policies change.

---

## 0. Blockers to clear before the first upload

Fixed in code on 2026-09-25:
- [x] **Gemini key no longer read from the bundled `env.json`** (`AppConfig` only accepts it via `--dart-define`, and the local `env.json` value was blanked). **Still to do: rotate the old key in Google AI Studio** — earlier APKs contain it.
- [x] **AI assistant is gated to Genzeb Plus** (`aiEntitledProvider`); Plus is not purchasable, so no release user can reach Gemini. The privacy policy and Data safety answers below assume no AI traffic. Revisit both before Plus launches.
- [x] **`learning_base.json` export** runs only in debug builds (`kReleaseMode` guard).
- [x] **Personal SMS are never stored**: sync ingests only recognised bank/wallet senders, and a one-time cleanup removes personal messages older versions stored.
- [x] **Money in / money out system notifications** (app closed): manifest `SmsReceiver` (guarded by `BROADCAST_SMS`) → headless Dart parser → notification. Uses RECEIVE_SMS (already in the SMS declaration — mention it in the declaration video) and POST_NOTIFICATIONS, asked once after SMS access is granted. Lock-screen version hides the amount.
- [x] **Sign-in and subscriptions switched off** (`AppConfig.accountsEnabled`, build flag `GENZEB_ACCOUNTS`). No accounts means Play's account-deletion requirement doesn't apply, and the release manifest drops INTERNET. (The in-app deletion flow + `delete_my_account` migration are kept for when accounts return.)

Still open:
- [ ] Only when accounts return: apply `supabase/migrations/0002_delete_my_account.sql` and add the account-deletion web link ([requirement](https://support.google.com/googleplay/android-developer/answer/13327111)).
- [ ] Replace `CONTACT_EMAIL` in `docs/privacy-policy.html` and publish it (see §9).
- [ ] Create the upload keystore and `android/key.properties` (§1). Without it the bundle is debug-signed and Play rejects it.
- [ ] Fix the local toolchain: `flutter doctor` reports a missing `cmdline-tools` component and unknown license status. Install "Android SDK Command-line Tools" in Android Studio → SDK Manager, then run `flutter doctor --android-licenses`. Without them, `flutter build appbundle` exits 1 with "failed to strip debug symbols" even though the `.aab` builds.
- [ ] New personal developer accounts: closed test with 12+ testers for 14 days before production access.

---

## 1. Signing (Play App Signing + upload key)

Use **Play App Signing**, which new apps get by default. Google holds the app-signing key and you sign uploads with an **upload key**.

1. Generate the upload keystore **outside the repo** and back it up somewhere safe, like a password manager or offline storage:
   ```sh
   keytool -genkey -v \
     -keystore ~/keys/genzeb-upload-keystore.jks \
     -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
     -alias upload
   ```
2. `cp android/key.properties.example android/key.properties` and fill in `storePassword`, `keyPassword`, `keyAlias=upload`, and `storeFile=/Users/<you>/keys/genzeb-upload-keystore.jks`. `key.properties`, `*.jks` and `*.keystore` are gitignored.
3. `android/app/build.gradle.kts` uses this key for `release` when `key.properties` exists. Without it, Gradle prints
   `WARNING: android/key.properties not found — release builds will be signed with the DEBUG key...`
   and Play will reject that bundle.
4. Check the signer before uploading:
   `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab`. The owner must not be `CN=Android Debug`.
5. On the first upload, accept Play App Signing. If you ever lose the upload key, you can ask Play support to reset it. The app-signing key can't be lost because Google holds it.

## 2. Permissions Declaration Form — READ_SMS / RECEIVE_SMS

Policy: [Use of SMS or Call Log permission groups](https://support.google.com/googleplay/android-developer/answer/10208820). Genzeb is not the default SMS handler, so it has to qualify under an **exception**. The matching row in the policy table:

| Use case | Policy description (verbatim) | Eligible permissions |
|---|---|---|
| **SMS-based money management** | "For example, apps that track and manage budget" | `READ_SMS`, `RECEIVE_MMS`, `RECEIVE_SMS`, `RECEIVE_WAP_PUSH` |

(The related "SMS-based financial transactions" row, e.g. UPI and transaction verification, does **not** fit Genzeb.)

The policy says exceptions apply only when the permission enables **core app functionality** and there is no alternative method. It also says budgeting apps may not exfiltrate or share non-financial or personal SMS history.

Where to file it: Play Console → App content → Sensitive app permissions → **Permissions declaration form** ([Declare permissions for your app](https://support.google.com/googleplay/android-developer/answer/9214102)). The form also appears during release if the bundle requests SMS permissions without a declaration.

Draft answers:
- **Core functionality:** Genzeb is a personal-finance app for Ethiopia. Ethiopian banks and mobile-money wallets (CBE, telebirr, etc.) report every transaction only by SMS and offer no public API. Genzeb reads these SMS on-device to record transactions, balances and fees automatically and to power budgets and reports. Without SMS access the core feature doesn't work and the app falls back to manual entry.
- **Permissions:** `READ_SMS` imports historical transaction SMS from recognised financial senders. `RECEIVE_SMS` records new transaction SMS while the app is in the foreground.
- **Data handling:** Parsing is fully on-device and deterministic. SMS text is never transmitted. Non-financial SMS are ignored and not stored. Android backup is disabled (`allowBackup=false`).
- **Why no alternative works:** there is no bank/wallet API or SMS Retriever-style alternative for reading third-party transaction receipts.
- [ ] **Demo video (required):** a YouTube link (preferred) or a cloud link to an mp4, about 30–90 s. Show: first launch → prominent disclosure screen → user taps accept → Android permission dialog → transactions appear from bank SMS → a new SMS arriving while the app is open → personal SMS not shown. Use a test device with sample messages, not real personal SMS.
- [ ] **Test instructions:** no login is needed. Explain how a reviewer can see parsing, e.g. a test build or instructions to send a sample CBE/telebirr-format SMS from an emulator.

## 3. Prominent in-app disclosure (User Data policy)

Required before the runtime SMS permission request ([User Data policy — Prominent Disclosure & Consent](https://support.google.com/googleplay/android-developer/answer/10144311)). The disclosure must:
- [ ] be **inside the app**, not only in the store listing, a website or the privacy policy;
- [ ] appear in **normal app usage** (onboarding), not buried in settings;
- [ ] describe the data accessed (SMS from bank/wallet senders) and how it is used or shared (on-device only, never uploaded);
- [ ] not be bundled with unrelated disclosures;
- [ ] **immediately precede** the consent/runtime-permission request;
- [ ] require an **affirmative action** (a tap on "Allow SMS access"). Back, tapping away or a timeout must not count as consent.

Suggested copy: *"Genzeb reads SMS from your bank and mobile-money wallet (e.g. CBE, telebirr) to record your transactions automatically. Messages are processed only on this phone and are never uploaded. Personal messages are ignored. You can add transactions manually instead."* Buttons: **Allow SMS access** / **Not now**.

## 4. Data safety form

Must match `docs/privacy-policy.html`. Data that is processed only on the device and never sent off it doesn't count as "collected" ([Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469)).

Sign-in is switched off for this release (`AppConfig.accountsEnabled = false`) and the release build has **no INTERNET permission**, so:

| Question | Answer |
|---|---|
| Does the app collect or share any required user data types? | **No** |
| Is all collected data encrypted in transit? | Not applicable (nothing is transmitted) |
| Can users request that data be deleted? | Not applicable — all data is on-device; uninstalling or clearing app data deletes it |

SMS messages and financial records are processed and stored on-device only, so they are not "collected". If sign-in is turned back on, restore the account-data rows (email, name, user ID, profile picture; Supabase as service provider) and the account-deletion answers.

Also: no advertising ID. The manifest strips `com.google.android.gms.permission.AD_ID`, so answer "No" to advertising ID use under Policy → App content → Advertising ID.

## 5. Other App content items

- [ ] **Privacy policy URL:** the public GitHub Pages URL (§9).
- [ ] **Ads:** No, the app contains no ads.
- [ ] **App access:** all functionality is available without login. The optional paid plan isn't live yet; if it is gated at review time, provide a test account.
- [ ] **Content rating (IARC questionnaire):** category *Utility/Productivity/Communication/Other* (or Reference). Answer No to violence, sexual content, profanity, drugs and gambling; no user-generated content sharing; no location sharing; no digital purchases (until the paid plan). Expected rating: Everyone / PEGI 3.
- [ ] **Target audience:** 18 and over only. The app isn't designed for children, so select "No" for appealing to children.
- [ ] **Financial features declaration:** declare "personal finance management / budgeting" and state there are no loans, no payments and no investments.
- [ ] **Government app / news / health:** No.
- [ ] **Testing requirement:** new *personal* developer accounts must run a **closed test with at least 12 testers for 14 consecutive days** before applying for production access (applies to personal accounts created after 2023-11-13; [App testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465)). Confirm in Play Console → Dashboard.

## 6. Target API / SDK

- Play requirement: starting **2026-08-31**, new apps and updates must target **Android 16 (API 36)** ([Target API level requirements](https://developer.android.com/google/play/requirements/target-sdk)).
- Genzeb resolves to `compileSdk 36`, `targetSdk 36`, `minSdk 24`. That's the Flutter 3.44 default, with a floor of 36 in `android/app/build.gradle.kts`. Verified in the merged release manifest.

## 7. Versioning

- `version:` in `pubspec.yaml` controls both values, as `versionName+versionCode` (currently `0.2.0+2`).
- Every upload needs a **higher versionCode** than any bundle ever uploaded, on any track. Bump the `+N` part, e.g. `1.0.0+3`, or override it for one build: `flutter build appbundle --release --build-name=1.0.0 --build-number=3`.

## 8. Build

```sh
# with android/key.properties in place
flutter build appbundle --release
# output: build/app/outputs/bundle/release/app-release.aab
```
Release builds use R8 (`isMinifyEnabled`, `isShrinkResources`) with `android/app/proguard-rules.pro`. Upload `build/app/outputs/mapping/release/mapping.txt` if Play doesn't pick it up from the bundle; it is embedded in the bundle as BUNDLE-METADATA. Native debug symbols are included in the bundle metadata too.

Smoke-test the release build on a device before uploading: SMS import, incoming SMS in the foreground, Google sign-in, sharing. R8 problems only show up in release builds.

## 9. Host the privacy policy (GitHub Pages)

1. Replace `CONTACT_EMAIL` in `docs/privacy-policy.html`.
2. GitHub repo → Settings → Pages → Source: *Deploy from a branch*, branch `main`, folder `/docs`.
3. URL: `https://<user>.github.io/<repo>/privacy-policy.html`. It has to be public and must not be a PDF or geo-blocked. If the repo is private, Pages needs a paid plan, or you can host the single HTML file anywhere public.

## 10. Store listing (en-US draft)

**App name** (≤30): `Genzeb: Money Tracker Ethiopia`

**Short description** (≤80):
`Track spending automatically from your bank & telebirr SMS. Private, offline.`

**Full description** (≤4000):
```
Genzeb turns the bank and mobile-money SMS you already receive into a clear picture of your money — automatically, and without your data ever leaving your phone.

AUTOMATIC TRACKING
Every time your bank or wallet texts you about a transaction, Genzeb records it: amount, fees, balance and who you paid or received from. No typing, no spreadsheets.

BUILT FOR ETHIOPIA
Understands transaction messages from recognised Ethiopian banks and mobile-money services, in Birr.

SEE WHERE YOUR MONEY GOES
• Income, expenses and transfers, categorised
• Fees and charges you pay, added up
• Monthly reports and cash-flow insights
• Budgets that update as you spend

PRIVATE BY DESIGN
• SMS are read on your phone only — never uploaded
• Personal messages are ignored and not stored
• Your records live in a database on your device
• No ads, no analytics, no tracking, no data selling
• No account needed

YOU'RE IN CONTROL
Prefer not to grant SMS access? Add transactions manually. Revoke permission any time in Android settings.

Genzeb is a personal budgeting tool. It does not move money, offer loans or access your bank account.
```

## 11. Graphics

| Asset | Requirement |
|---|---|
| App icon | 512 × 512 px, 32-bit PNG (with alpha), ≤ 1 MB |
| Feature graphic | 1024 × 500 px, JPG or 24-bit PNG (no alpha) |
| Phone screenshots | 2–8, JPG or 24-bit PNG, 16:9 or 9:16, each side 320–3840 px, long side ≤ 2× short side. Use at least 4 at ≥ 1080 px for promotion eligibility |
| 7" / 10" tablet screenshots | Optional (the app isn't tablet-optimised) |
| Promo video | Optional YouTube URL. The SMS declaration demo video is separate (§2) |

Screenshots should show only sample data, not real personal transactions.
