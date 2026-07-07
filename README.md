# Genzeb

Genzeb is a free, offline-first Flutter finance app tailored for Ethiopia.
It reads bank and wallet SMS notifications (CBE, Telebirr, Awash, Abyssinia,
Hibret, Dashen, and a generic fallback) and turns them into a categorized
personal ledger — no account, no signup, everything stored on the device.

Features:

- SMS parser engine with per-institution templates, confidence scoring, and a
  human review queue for low-confidence matches.
- Transaction ledger for SMS and manual entries, persisted in on-device SQLite.
- Budgets with category/institution scoping, dashboard, and monthly reports.
- Optional AI assistant (Gemini) grounded in your data — bring your own free
  API key via Settings; only an aggregated summary is sent, never your SMS.

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
