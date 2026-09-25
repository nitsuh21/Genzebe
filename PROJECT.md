# Genzeb (GenzeBet)

**What:** Offline-first Flutter personal-finance app for Ethiopia that turns bank/wallet SMS (CBE, Telebirr, Awash, BOA, Hibret, Dashen) into a categorized ledger with budgets and reports.
**Status:** Active
**Stack:** Flutter 3 / Dart, sqflite (on-device ledger), Riverpod, Supabase (optional Google sign-in, plans, account deletion), Gemini (chat assistant, Plus-only)

## Next Step
> Cut the review queue (249 items on the dev phone, all from recognised senders): with the owner's OK, export real bank/wallet SMS from the phone, add them to `test/fixtures/sms/`, and fix the parser until the corpus is green (issue #1). Play launch blockers are listed in `docs/play-store-submission.md` §0 (upload keystore, host the privacy policy, rotate the old Gemini key).

## Built So Far
- Play-readiness pass (2026-09-25): no login required (sign-in optional, in Profile, for Plus); registry of 38 Ethiopian banks + wallets with auto-detected accounts and brand monograms (manual sender mapping removed); sync reads only recognised financial senders and purges personal SMS stored by old versions; auto-sync on launch/resume/incoming bank SMS; in-app money in/out alerts (banner + bell inbox); AI assistant gated to Genzeb Plus; light theme default; in-app account deletion; release signing via key.properties, R8, target SDK 36; privacy policy + Play checklist in `docs/`; offline startup no longer blocks on Supabase.
- UI pass (2026-09-19): month stepper on Ledger/Reports, trailing 3/6-month windows, honest empty states, merchant names on tiles, transaction detail sheet (SMS text, delete), review nudge on Home + badge on Profile, direction flip in review, global hide-amounts, status-bar contrast, plain-language SMS page, on-demand SMS permission, own transfers excluded from budgets.
- SMS ingestion: per-institution templates, sender-ID identification, explicit-phrase direction detection, itemized-fee handling (CBE totals), balance/reference extraction.
- Evidence-based confidence: auto-accept only with a recognised sender AND an unambiguous direction phrase; everything else goes to the review queue with the reason shown.
- User-taught merchant rules and sender→account mappings outrank the parser and are re-applied on every sync / re-parse.
- Fixture corpus (`test/fixtures/sms/`) as the parser spec — 39 pinned cases, table-driven test.
- Ledger, budgets, dashboard, monthly reports with own-transfer pairing and fee tracking.
- Gemini chat assistant grounded in an aggregated ledger summary (SMS text never sent).
- Google sign-in via Supabase; freemium plan auto-provisioned.

## Half-Done / Known Issues
- Review queue is still large on real data: messages from recognised senders without an explicit direction phrase. Needs real samples (issue #1).
- Numeric shortcodes seen on the dev phone are unclassified: 251994, 830, 9923, 131, 605, 8202, 994, 810, 824 — plus `apollo` (possibly BoA's Apollo). Only `127` (telebirr) is mapped.
- Awash/BOA/Dashen/Hibret and all newly added institutions' fixtures are synthetic.
- Sign-in, plans/Plus and the AI assistant are switched off (`AppConfig.accountsEnabled`, `--dart-define=GENZEB_ACCOUNTS=true` to re-enable; also restore INTERNET in the manifest). Release has no INTERNET permission.
- `flutter build appbundle` exits 1 locally ("failed to strip debug symbols") until Android cmdline-tools are installed; the .aab itself builds.

## Services & Billing
| Service | Purpose | Cost/mo |
|---------|---------|---------|
| Supabase | auth, plans table | $0 (free tier) |
| Google Cloud | OAuth client | $0 |
| Gemini API | chat assistant | $0 (free tier, quota-limited) |

## Credentials
All secrets in NordLocker → folder "genzeb".
Required config keys: see `env.example.json` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_SERVER_CLIENT_ID`). `GEMINI_API_KEY` is dev-only via `--dart-define`, never bundled. Release upload key: `android/key.properties` (template: `android/key.properties.example`) — keystore + passwords belong in NordLocker.

## Decisions Log
- 2026-09-19: Removed AI (Gemini) from SMS extraction entirely — categorization/direction/institution are now deterministic + user rules + review queue. Reason: Gemini quota/billing blockers, key exposure in APK, and SMS text was leaving the device. Chat assistant kept for now.
- 2026-09-25: Play-readiness. Login optional (no sign-in wall); AI chat kept but gated to the Plus plan and its key removed from the bundle; manual sender mapping replaced by a built-in institution registry; bank logos replaced by brand-coloured monograms (trademark / Play impersonation risk).
- 2026-09-25: Sign-in and subscription UI switched off for v1 (code kept behind `accountsEnabled`); release drops INTERNET. Supabase unused until Plus launches.
