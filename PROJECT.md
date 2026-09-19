# Genzeb (GenzeBet)

**What:** Offline-first Flutter personal-finance app for Ethiopia that turns bank/wallet SMS (CBE, Telebirr, Awash, BOA, Hibret, Dashen) into a categorized ledger with budgets and reports.
**Status:** Active
**Stack:** Flutter 3 / Dart, sqflite (on-device ledger), Riverpod, Supabase (Google sign-in + plan table only), Gemini (chat assistant only)

## Next Step
> Issue #1 — collect real SMS samples for Awash, BOA, Dashen and Hibret (from `learning_base.json` on a phone) and replace the `synthetic` cases in `test/fixtures/sms/*.json` with them; fix the parser until `flutter test test/sms_corpus_test.dart` is green. Then decide #2 (Gemini chat) and #3 (Supabase).

## Built So Far
- UI pass (2026-09-19): month stepper on Ledger/Reports, trailing 3/6-month windows, honest empty states, merchant names on tiles, transaction detail sheet (SMS text, delete), review nudge on Home + badge on Profile, direction flip in review, global hide-amounts, status-bar contrast, plain-language SMS page, on-demand SMS permission, own transfers excluded from budgets.
- SMS ingestion: per-institution templates, sender-ID identification, explicit-phrase direction detection, itemized-fee handling (CBE totals), balance/reference extraction.
- Evidence-based confidence: auto-accept only with a recognised sender AND an unambiguous direction phrase; everything else goes to the review queue with the reason shown.
- User-taught merchant rules and sender→account mappings outrank the parser and are re-applied on every sync / re-parse.
- Fixture corpus (`test/fixtures/sms/`) as the parser spec — 39 pinned cases, table-driven test.
- Ledger, budgets, dashboard, monthly reports with own-transfer pairing and fee tracking.
- Gemini chat assistant grounded in an aggregated ledger summary (SMS text never sent).
- Google sign-in via Supabase; freemium plan auto-provisioned.

## Half-Done / Known Issues
- Awash/BOA/Dashen/Hibret fixtures are synthetic — only CBE and Telebirr are pinned by real messages.
- Gemini free-tier quota is exhausted/unpayable; the chat assistant is effectively down. Key is bundled in the APK (extractable). Decision pending: proxy via Supabase Edge Function with a paid provider, or drop chat.
- Supabase does nothing beyond auth + a placeholder `subscriptions` row; keep only if paid plans or the AI proxy happen.
- README used to claim users could bring their own AI key — no user-key path exists.

## Services & Billing
| Service | Purpose | Cost/mo |
|---------|---------|---------|
| Supabase | auth, plans table | $0 (free tier) |
| Google Cloud | OAuth client | $0 |
| Gemini API | chat assistant | $0 (free tier, quota-limited) |

## Credentials
All secrets in NordLocker → folder "genzeb".
Required config keys: see `env.example.json` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_SERVER_CLIENT_ID`, `GEMINI_API_KEY`).

## Decisions Log
- 2026-09-19: Removed AI (Gemini) from SMS extraction entirely — categorization/direction/institution are now deterministic + user rules + review queue. Reason: Gemini quota/billing blockers, key exposure in APK, and SMS text was leaving the device. Chat assistant kept for now.
