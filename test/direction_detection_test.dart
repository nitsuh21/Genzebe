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
