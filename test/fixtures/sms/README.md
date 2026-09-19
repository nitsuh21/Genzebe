# SMS parser corpus

Every message format the parser supports is pinned here, one JSON file per
institution (`cbe.json`, `telebirr.json`, … and `generic.json` for
unrecognised senders). `test/sms_corpus_test.dart` runs the full parser
engine over every case and checks each expectation.

**This corpus is the spec.** When a real message is parsed wrongly, the fix
is: add the message here with the correct expectation, watch the test fail,
then fix the parser. Never edit an existing `real` case to match the parser.

## Adding a case

```json
{
  "id": "cbe-debit-with-fees",
  "source": "real",
  "sender": "CBE",
  "body": "Dear Nitsuh your Account 1*****9722 has been debited with ETB5,000.00. ...",
  "expect": {
    "parsed": true,
    "institution": "cbe",
    "direction": "out",
    "amountMinor": 501200,
    "category": "fees",
    "balanceMinor": 28376067,
    "referenceContains": "FT26140YL4N417459722",
    "merchant": null,
    "explicitDirection": true,
    "autoAccept": true
  }
}
```

- `source` — `real` (copied from a phone; mask names/accounts, keep the
  wording exactly) or `synthetic` (written by hand to pin a rule). Replace
  synthetic cases with real ones whenever you get them.
- `sender` — the SMS sender ID exactly as the phone shows it.
- `expect.parsed: false` — the message must be ignored (OTP, balance
  inquiry, failed transaction, promo). No other expectations are needed.
- `direction` — `in` (money arrived) or `out` (money left).
- `amountMinor` / `balanceMinor` — ETB × 100.
- `referenceContains` — substring the extracted reference must contain.
- `merchant` — exact counterparty the parser should extract, or `null`.
- `explicitDirection` — whether an unambiguous phrase decided the direction
  (bare keywords like "transfer" are not explicit).
- `autoAccept` — whether the parse is trusted enough to skip the review
  queue (confidence ≥ 0.85). Without a recognised sender AND an explicit
  direction this must be `false`.

Every field under `expect` is optional except `parsed`; only the ones you
include are checked.

## Getting real messages

The app writes `learning_base.json` to its documents directory on the first
sync (sender, body and how it was parsed). Copy `sender` and `body` from
there. Mask account numbers and personal names before committing.

Run just this corpus with:

```bash
flutter test test/sms_corpus_test.dart
```
