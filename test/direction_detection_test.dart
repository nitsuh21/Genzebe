import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';

void main() {
  group('direction: earliest cue wins', () {
    test('telebirr send mentioning the recipient received is still expense',
        () {
      // The classic false-income: 'received' appears near the end.
      expect(
        isExpenseMessage(
          'you have transferred etb 500.00 to abebe kebede (2519****) on '
          '09/07/2026. abebe kebede has received the amount. your current '
          'balance is etb 1,200.00.'.toLowerCase(),
        ),
        isTrue,
      );
    });

    test('CBE debit-and-credited-to-beneficiary is expense', () {
      expect(
        isExpenseMessage(
          'dear customer, your account 1****234 has been debited with '
          'etb 2,000.00 and credited to the beneficiary account. '
          'your current balance is etb 8,000.00',
        ),
        isTrue,
      );
    });

    test('real income still detected', () {
      expect(
        isExpenseMessage(
          'you have received etb 750.00 from emebet k. via telebirr.',
        ),
        isFalse,
      );
      expect(
        isExpenseMessage(
          'dear customer, your account has been credited with etb 28,500.00 '
          'salary payment.',
        ),
        isFalse,
      );
    });

    test('transferred-to-your-account is income despite expense prefix', () {
      expect(
        isExpenseMessage(
          'etb 4,000.00 transferred to your savings account 1****120.',
        ),
        isFalse,
      );
    });
  });

  test('real CBE transfer receipt: expense, total amount, transfer_out', () {
    // Reported by the user as wrongly recorded income. The receipt has no
    // "debited" keyword, mentions fees, and says "successfully transferred".
    final parsed = const CbeSmsParserTemplate().parse(
      SmsMessage(
        id: 'cbe-real-1',
        sender: 'CBE',
        body: 'Dear  Nitsuh Demissew Mekonnen You have successfully '
            'transferred ETB1100.00 from account 1**9722 to account 1**4607 '
            '(Nebyou Elias Zewde). Service charge of ETB 1.00 and VAT(15%) '
            'of ETB0.15 and Disaster Recovery(5%) of 0.05 with total of '
            'ETB1101.20 .Your current balance is ETB89,468.32. Thanks for '
            'Banking with CBE. https://mbreciept.cbe.com.et/v2-hfHCxzVQsJzR5',
        receivedAt: DateTime(2026, 7, 9, 12, 0),
      ),
    );
    expect(parsed, isNotNull);
    // Money left the account: expense, and the debited total incl. charges.
    expect(parsed!.detectedAmountMinor, -110120);
    // The transfer is the transaction — not the fees it happens to mention.
    expect(parsed.categoryHint, 'transfer_out');
    expect(parsed.balanceMinor, 8946832);
  });

  test('cross-institution mention does not steal the message', () {
    // A telebirr receipt that mentions CBE must NOT match the CBE template.
    expect(
      const CbeSmsParserTemplate().canParse(
        SmsMessage(
          id: 'tb-x',
          sender: '127',
          body: 'You have received ETB 200.00 from CBE account transfer '
              'via telebirr.',
          receivedAt: DateTime(2026, 7, 9),
        ),
      ),
      isFalse,
    );
    // ...and the 127 shortcode routes to the telebirr template.
    expect(
      const TelebirrSmsParserTemplate().canParse(
        SmsMessage(
          id: 'tb-y',
          sender: '127',
          body: 'You have paid ETB 50.00 to Shoa Supermarket via telebirr.',
          receivedAt: DateTime(2026, 7, 9),
        ),
      ),
      isTrue,
    );
  });

  group('CBE template uses position-based direction', () {
    test('transfer with both debited and credited parses as expense', () {
      final parsed = const CbeSmsParserTemplate().parse(
        SmsMessage(
          id: 'cbe-x',
          sender: 'CBE',
          body: 'Dear customer, your account 1****234 has been debited with '
              'ETB 2,000.00 and credited to the beneficiary. '
              'Your current balance is ETB 8,000.00',
          receivedAt: DateTime(2026, 7, 9, 10, 0),
        ),
      );
      expect(parsed, isNotNull);
      expect(parsed!.detectedAmountMinor, -200000);
    });

    test('plain credit still parses as income', () {
      final parsed = const CbeSmsParserTemplate().parse(
        SmsMessage(
          id: 'cbe-y',
          sender: 'CBE',
          body: 'Dear customer, your account 1****234 has been credited with '
              'ETB 28,500.00. Your current balance is ETB 30,000.00',
          receivedAt: DateTime(2026, 7, 9, 10, 0),
        ),
      );
      expect(parsed, isNotNull);
      expect(parsed!.detectedAmountMinor, 2850000);
    });
  });
}
