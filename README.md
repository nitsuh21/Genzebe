# GenzeBet

GenzeBet is an offline-first Flutter finance app tailored for Ethiopia.

This implementation includes:

- Transaction ledger domain for SMS/manual/sync sources.
- SMS parser engine with confidence scoring and review queue.
- Dashboard, ledger, reporting, premium, and admin screens.
- Trial and premium entitlement lifecycle (default 90-day trial, 6-month premium).
- Semi-manual subscription flow for Chapa/Telebirr claims.
- Opt-in cloud sync scaffold with backup/restore hooks.
- AI summary boundary gated by entitlement status.

## Run

Install Flutter SDK, then:

```bash
flutter pub get
flutter run
```
