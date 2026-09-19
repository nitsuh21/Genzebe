# Genzeb

Genzeb is a free, offline-first Flutter finance app tailored for Ethiopia.
It reads bank and wallet SMS notifications (CBE, Telebirr, Awash, Abyssinia,
Hibret, Dashen, and a generic fallback) and turns them into a categorized
personal ledger — no account, no signup, everything stored on the device.

Features:

- Fully deterministic SMS parser: per-institution templates, evidence-based
  confidence scoring, and a human review queue for anything the parser is not
  sure about. Nothing about your SMS ever leaves the device; corrections you
  make are remembered as rules and applied on every future sync.
- Transaction ledger for SMS and manual entries, persisted in on-device SQLite.
- Budgets with category/institution scoping, dashboard, and monthly reports.
- Optional AI assistant (Gemini) for questions about your finances. Only an
  aggregated summary of your ledger is sent — never SMS text.

## Parser fixtures

Every SMS format the parser supports is pinned by a fixture in
`test/fixtures/sms/`, one JSON file per institution. To teach the parser a
new format, add the real message and the expected result there and run
`flutter test test/sms_corpus_test.dart` — see `test/fixtures/sms/README.md`.

## Run

Install Flutter SDK, then:

```bash
flutter pub get
flutter run
```

To ship a build with a bundled Gemini key instead of user-supplied keys:

```bash
flutter build apk --dart-define=GEMINI_API_KEY=your_key_here
```

## Test

```bash
flutter test
```
