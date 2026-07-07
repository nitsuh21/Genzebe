import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';

void main() {
  final parser = SmsParserEngine(
    const [
      CbeSmsParserTemplate(),
      AwashSmsParserTemplate(),
      TelebirrSmsParserTemplate(),
      BoaSmsParserTemplate(),
      HibretSmsParserTemplate(),
      DashenSmsParserTemplate(),
      GenericAmountParserTemplate(),
    ],
  );

  test('parses CBE message', () {
    final parsed = parser.parse(
      SmsMessage(
        id: '1',
        sender: 'CBE',
        body: 'CBE Alert: account debited ETB 450.00 at POS',
        receivedAt: DateTime.now(),
      ),
    );
    expect(parsed, isNotNull);
    expect(parsed!.institution, EthiopianInstitution.cbe);
    expect(parsed.detectedAmountMinor, -45000);
  });

  test('parses Awash message', () {
    final parsed = parser.parse(
      SmsMessage(
        id: '2',
        sender: 'AWASH',
        body: 'Awash Bank credited ETB 1,200.00 salary',
        receivedAt: DateTime.now(),
      ),
    );
    expect(parsed, isNotNull);
    expect(parsed!.institution, EthiopianInstitution.awash);
    expect(parsed.detectedAmountMinor, 120000);
  });

  test('parses Telebirr message', () {
    final parsed = parser.parse(
      SmsMessage(
        id: '3',
        sender: 'TELEBIRR',
        body: 'Telebirr wallet paid ETB 150.50',
        receivedAt: DateTime.now(),
      ),
    );
    expect(parsed, isNotNull);
    expect(parsed!.institution, EthiopianInstitution.telebirr);
    expect(parsed.detectedAmountMinor, -15050);
  });

  test('parses BOA message', () {
    final parsed = parser.parse(
      SmsMessage(
        id: '4',
        sender: 'ABYSSINIA',
        body: 'BOA account debited ETB 300.00 ref AA11',
        receivedAt: DateTime.now(),
      ),
    );
    expect(parsed, isNotNull);
    expect(parsed!.institution, EthiopianInstitution.boa);
  });

  test('parses Hibret message', () {
    final parsed = parser.parse(
      SmsMessage(
        id: '5',
        sender: 'HIBRET',
        body: 'Hibret Bank credited ETB 2,000.00',
        receivedAt: DateTime.now(),
      ),
    );
    expect(parsed, isNotNull);
    expect(parsed!.institution, EthiopianInstitution.hibret);
  });

  test('parses Dashen message', () {
    final parsed = parser.parse(
      SmsMessage(
        id: '6',
        sender: 'DASHEN',
        body: 'Dashen account debited ETB 90.00 taxi',
        receivedAt: DateTime.now(),
      ),
    );
    expect(parsed, isNotNull);
    expect(parsed!.institution, EthiopianInstitution.dashen);
  });

  test('amount selection skips the balance figure', () {
    final parsed = parser.parse(
      SmsMessage(
        id: '7',
        sender: 'CBE',
        body: 'CBE: debited ETB 450.00 at supermarket. Bal ETB 9,100.00',
        receivedAt: DateTime.now(),
      ),
    );
    expect(parsed, isNotNull);
    expect(parsed!.detectedAmountMinor, -45000);
    expect(parsed.balanceMinor, 910000);
  });

  test('infers category from merchant keywords', () {
    final groceries = parser.parse(
      SmsMessage(
        id: '8',
        sender: 'CBE',
        body: 'CBE: debited ETB 250.00 at supermarket',
        receivedAt: DateTime.now(),
      ),
    );
    expect(groceries!.categoryHint, 'groceries');

    final transport = parser.parse(
      SmsMessage(
        id: '9',
        sender: 'TELEBIRR',
        body: 'Telebirr: paid ETB 80.00 for taxi ride',
        receivedAt: DateTime.now(),
      ),
    );
    expect(transport!.categoryHint, 'transport');

    final salary = parser.parse(
      SmsMessage(
        id: '10',
        sender: 'AWASH',
        body: 'Awash: credited ETB 9,000.00 salary payment',
        receivedAt: DateTime.now(),
      ),
    );
    expect(salary!.categoryHint, 'salary');
  });

  test('detects income/expense direction with Amharic keywords', () {
    final income = parser.parse(
      SmsMessage(
        id: '11',
        sender: 'CBE',
        body: 'CBE: ETB 500.00 ገቢ ሆኗል',
        receivedAt: DateTime.now(),
      ),
    );
    expect(income, isNotNull);
    expect(income!.detectedAmountMinor, 50000);
  });

  test('ignores telebirr verification code message', () {
    final parsed = parser.parse(
      SmsMessage(
        id: 'otp-1',
        sender: 'Ethio telecom',
        body:
            'Dear Customer, 827103 is your telebirr verification code. Thank you for using telebirr.',
        receivedAt: DateTime.now(),
      ),
    );
    expect(parsed, isNull);
  });

  test('parses only telebirr airtime purchase (ignore mirrored received airtime)', () {
    final recharge = parser.parse(
      SmsMessage(
        id: 'tb-airtime-1',
        sender: 'Ethio telecom',
        body:
            'Dear Nitsuh You have recharged ETB 100.00 airtime for 910050569 on 03/06/2026 12:45:39.',
        receivedAt: DateTime.now(),
      ),
    );
    expect(recharge, isNotNull);
    expect(recharge!.detectedAmountMinor, -10000);
    expect(recharge.categoryHint, 'airtime');

    final receivedAirtime = parser.parse(
      SmsMessage(
        id: 'tb-airtime-2',
        sender: 'ethio telecom',
        body:
            'Dear Customer You have received ETB 100.00 airtime from 251910050569 on 03/06/2026 12:45:39.',
        receivedAt: DateTime.now(),
      ),
    );
    expect(receivedAirtime, isNull);
  });

  test('parses telebirr person-to-person received money as income', () {
    final parsed = parser.parse(
      SmsMessage(
        id: 'tb-income-1',
        sender: 'Ethio telecom',
        body:
            'Dear Nitsuh You have received ETB 53.00 from Mekuria Solomon(2519****4846) '
            'on 02/06/2026 13:14:04. Your transaction number is DF24JC2U3S. '
            'Your current E-Money Account balance is ETB 2,828.26. Thank you for using telebirr',
        receivedAt: DateTime.now(),
      ),
    );
    expect(parsed, isNotNull);
    expect(parsed!.detectedAmountMinor, 5300);
  });

  test('parses CBE credit format with current balance', () {
    final parsed = parser.parse(
      SmsMessage(
        id: '12',
        sender: 'CBE',
        body:
            'Dear Nitsuh Demissew your Account 1****9722 has been credited with ETB 5000.00. '
            'Your Current Balance is ETB 201239.71. Thank you for Banking with CBE! '
            'for Reciept https://apps.cbe.com.et:100/BranchReceipt/FT26147S2FCW&17459722',
        receivedAt: DateTime.now(),
      ),
    );
    expect(parsed, isNotNull);
    expect(parsed!.institution, EthiopianInstitution.cbe);
    expect(parsed.detectedAmountMinor, 500000);
    expect(parsed.balanceMinor, 20123971);
    expect(parsed.reference, contains('FT26147S2FCW'));
  });

  test('parses CBE debit format and prefers total amount', () {
    final parsed = parser.parse(
      SmsMessage(
        id: '13',
        sender: 'CBE',
        body:
            'Dear Nitsuh your Account 1*****9722 has been debited with ETB5,000.00. '
            'Service charge of ETB 10.00 and VAT(15%) of ETB1.50 and Disaster Fund (5%) '
            'of ETB0.50 with a total of ETB 5012.00. '
            'Your Current Balance is ETB 283,760.67. Thank you for Banking with CBE! '
            'https://apps.cbe.com.et:100/?id=FT26140YL4N417459722',
        receivedAt: DateTime.now(),
      ),
    );
    expect(parsed, isNotNull);
    expect(parsed!.institution, EthiopianInstitution.cbe);
    expect(parsed.detectedAmountMinor, -501200);
    expect(parsed.balanceMinor, 28376067);
    expect(parsed.categoryHint, 'fees');
    expect(parsed.reference, contains('FT26140YL4N417459722'));
  });
}
