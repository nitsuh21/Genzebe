# Genzeb (GenzeBet)

**What:** Offline-first Flutter personal-finance app for Ethiopia that turns bank/wallet SMS (CBE, Telebirr, Awash, BOA, Hibret, Dashen) into a categorized ledger with budgets and reports.
**Status:** Active
**Stack:** Flutter 3 / Dart, sqflite (on-device ledger), Riverpod, Supabase (optional Google sign-in, plans, account deletion), Gemini (chat assistant, Plus-only)

## Next Step
> Play blockers in `docs/play-store-submission.md` §0 (upload keystore, host privacy policy, rotate old Gemini key).

## Built So Far
- Real logos for 28 banks/wallets (`assets/logos/`, sources in SOURCES.md); monogram fallback for the other 10. Alerts lead with the counterparty name and show direction · type · account.
- Parser v2 (2026-09-25), driven by 22 real messages from the owner's phone (`test/fixtures/sms/real_2026_09.json`): Hibret 'is made to/from your account' + signed amounts, CBE 'debit transaction of', telebirr withdrawals/cancellations/bonus, M-PESA Amharic purchases/receipts, promotion + evidence gates (Amharic marketing words, links without a balance). On the real inbox: review 245 → 0, fake Awash income gone. Parser version bump triggers a one-time history rebuild (never without SMS permission).
- System push notifications (2026-09-25): bank/wallet SMS with the app closed → manifest SmsReceiver → headless engine runs `smsBackgroundMain` → booked + alert + notification (tap opens the transaction). Live-vs-inbox duplicates prevented by a 15-min same-sender/same-text twin check. Verified end-to-end on the emulator with a real modem SMS.
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
- 2026-09-25: Owner chose real bank logos over monograms, accepting the Play trademark risk.
