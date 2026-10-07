import 'package:flutter_test/flutter_test.dart';
import 'package:genzeb/features/reports/application/own_transfer_detector.dart';
import 'package:genzeb/features/reports/application/report_service.dart';
import 'package:genzeb/features/sms_ingestion/application/account_resolver.dart';
import 'package:genzeb/features/sms_ingestion/application/sms_ingestion_service.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_sms_message_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/transactions/data/in_memory_ledger_repository.dart';
import 'package:genzeb/features/transactions/domain/models/money.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Message bodies follow real receipts from the fixture corpus
// (test/fixtures/sms/real_2026_09.json, cbe.json, telebirr.json) with names
// and account numbers masked. The account holder is "Abebe Kebede Alemu".

/// A CBE receipt whose salutation carries the holder's full name — the way
/// the app learns who "you" are.
const _cbeFullNameReceipt =
    'Dear  Abebe Kebede Alemu You have successfully transferred ETB400.00 '
    'from account 1********9722 to account 1********6766 (Hanna S. M.). '
    'Service charge of ETB 0.50 and VAT(15%) of ETB0.08 with a total of '
    'ETB400.58. Your Current Balance is ETB 11,420.67. Thank you for '
    'Banking with CBE!';

TransactionRecord _tx({
  required String id,
  required String accountId,
  required TransactionType type,
  required int amountMinor,
  required DateTime at,
  String categoryId = 'expense',
  String? snippet,
  OwnTransferOverride ownTransfer = OwnTransferOverride.none,
  TransactionReviewStatus reviewStatus = TransactionReviewStatus.autoAccepted,
}) {
  return TransactionRecord(
    id: id,
    accountId: accountId,
    type: type,
    amount: Money(minorUnits: amountMinor),
    occurredAt: at,
    categoryId: categoryId,
    source: TransactionSource.sms,
    smsSender: accountId,
    smsSnippet: snippet,
    reviewStatus: reviewStatus,
    ownTransfer: ownTransfer,
  );
}

/// The holder-name receipt, a month earlier so it never lands in the
/// report window.
TransactionRecord _nameSource() => _tx(
      id: 'name-source',
      accountId: 'cbe-main',
      type: TransactionType.expense,
      amountMinor: 40058,
      at: DateTime(2026, 6, 2, 9),
      categoryId: 'transfer_out',
      snippet: _cbeFullNameReceipt,
    );

Future<MonthlyReport> _julyReport(
  List<TransactionRecord> records, {
  Set<String> institutionCodes = const {},
}) async {
  final ledger = InMemoryLedgerRepository();
  for (final code in {'cbe', 'telebirr', 'hibret', 'mpesa'}) {
    await ledger.upsertAccount(Account(
      id: '$code-main',
      name: code,
      kind: 'bank-account',
      createdAt: DateTime(2026, 1, 1),
      institutionCode: code,
    ));
  }
  for (final record in records) {
    await ledger.saveTransaction(record);
  }
  final service = ReportService(
    ledger,
    SmsIngestionService(
      parser: SmsParserEngine(const [GenericAmountParserTemplate()]),
      ledgerRepository: ledger,
      smsMessageRepository: InMemorySmsMessageRepository(),
      accountResolver: AccountResolver(ledger),
      categoryRuleRepository: InMemoryCategoryRuleRepository(),
    ),
  );
  return service.generateReportForRange(
    startInclusive: DateTime(2026, 7, 1),
    endExclusive: DateTime(2026, 8, 1),
    institutionCodes: institutionCodes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('owner profile', () {
    test('learns the fullest consistent holder name from salutations', () {
      final profile = OwnerProfile.learn([
        _tx(
          id: 'a',
          accountId: 'cbe-main',
          type: TransactionType.income,
          amountMinor: 1,
          at: DateTime(2026, 7, 1),
          snippet: 'Dear Abebe your Account 1*****9722 has been credited '
              'with ETB 5000.00.',
        ),
        _tx(
          id: 'b',
          accountId: 'cbe-main',
          type: TransactionType.expense,
          amountMinor: 1,
          at: DateTime(2026, 7, 1),
          // "A" starts the sentence — it is not an initial.
          snippet: 'Dear Abebe A debit transaction of ETB 100.0. has '
              'occurred on your account 1********9722.',
        ),
        _tx(
          id: 'c',
          accountId: 'cbe-main',
          type: TransactionType.expense,
          amountMinor: 1,
          at: DateTime(2026, 7, 1),
          snippet: _cbeFullNameReceipt,
        ),
        _tx(
          id: 'd',
          accountId: 'cbe-main',
          type: TransactionType.income,
          amountMinor: 1,
          at: DateTime(2026, 7, 1),
          snippet: 'Dear customer, your account 1****234 has been credited '
              'with ETB 28,500.00.',
        ),
      ]);
      expect(profile.nameTokens, ['abebe', 'kebede', 'alemu']);
      expect(profile.isOwnerName('Abebe K. A'), isTrue);
      expect(profile.isOwnerName('ABEBE KEBEDE'), isTrue);
      expect(profile.isOwnerName('Abebe Tesfaye'), isFalse);
      expect(profile.isOwnerName('Hanna S. M'), isFalse);
      // A bare first name is too weak to call it the owner.
      expect(profile.isOwnerName('Abebe'), isFalse);
    });

    test('a single-word salutation is never enough to match names', () {
      final profile = OwnerProfile.learn([
        _tx(
          id: 'a',
          accountId: 'telebirr-main',
          type: TransactionType.income,
          amountMinor: 1,
          at: DateTime(2026, 7, 1),
          snippet: 'Dear Abebe You have received ETB 53.00 from Mekuria '
              'Solomon(2519****4846) on 02/06/2026 13:14:04.',
        ),
      ]);
      expect(profile.isOwnerName('Abebe Kebede'), isFalse);
    });

    test('masked account numbers compare on the digits both sides show', () {
      final a = MaskedAccount.parse('1*****4607')!;
      expect(a.sameAs(MaskedAccount.parse('1**4607')!), isTrue);
      expect(a.sameAs(MaskedAccount.parse('1000123454607')!), isTrue);
      expect(a.sameAs(MaskedAccount.parse('1**4608')!), isFalse);
      expect(a.sameAs(MaskedAccount.parse('2**4607')!), isFalse);
      // A phone tail of two digits can't identify anything.
      expect(
        MaskedAccount.parse('2519******69')!
            .sameAs(MaskedAccount.parse('2519******69')!),
        isFalse,
      );
    });
  });

  group('pairs the detector used to miss', () {
    test('Hibret IPS "Instant Payment To Other Bank" pairs with the credit',
        () async {
      final t = DateTime(2026, 7, 8, 10);
      final report = await _julyReport([
        _tx(
          id: 'ips-out',
          accountId: 'hibret-main',
          type: TransactionType.expense,
          amountMinor: 1002760,
          at: t,
          snippet: 'Dear customer, Please be informed that ETB -10027.6 '
              'Outgoing Instant Payment To Other Bank - (Ips) is made from '
              'your account 474041*******013  . Available Balance : '
              '15458.92 Current Balance : 15458.92  .For further queries '
              'please call 995. United, We Prosper!',
        ),
        _tx(
          id: 'ips-in',
          accountId: 'cbe-main',
          type: TransactionType.income,
          amountMinor: 1000000,
          at: t.add(const Duration(minutes: 4)),
          categoryId: 'transfer_in',
          snippet: 'Dear Abebe your Account 1*********9722 has been Credited '
              'with ETB 10,000.00 from Abebe Kebede Alemu, on 08/07/2026 at '
              '10:04:10 with Ref No FT26189AB1CD Your Current Balance is '
              'ETB 25,000.00. Thank you for Banking with CBE!',
        ),
      ]);
      expect(report.incomeMinor, 0);
      // Only the ETB 27.60 the transfer cost is spending.
      expect(report.expenseMinor, 2760);
      expect(report.categoryTotalsMinor['fees'], 2760);
      expect(report.internalMovedMinor, 1002760);
    });

    test('two of your own accounts at the same bank pair up', () async {
      final t = DateTime(2026, 7, 9, 18);
      final report = await _julyReport([
        _tx(
          id: 'same-out',
          accountId: 'cbe-main',
          type: TransactionType.expense,
          amountMinor: 110120,
          at: t,
          categoryId: 'transfer_out',
          snippet: 'Dear customer You have successfully transferred '
              'ETB1100.00 from account 1**9722 to account 1**4607. Service '
              'charge of ETB 1.00 and VAT(15%) of ETB0.15 and Disaster '
              'Recovery(5%) of 0.05 with total of ETB1101.20 .Your current '
              'balance is ETB89,468.32.',
        ),
        _tx(
          id: 'same-in',
          accountId: 'cbe-main',
          type: TransactionType.income,
          amountMinor: 110000,
          at: t.add(const Duration(minutes: 1)),
          categoryId: 'income',
          snippet: 'Dear Abebe your Account 1*****4607 has been credited '
              'with ETB 1,100.00. Your Current Balance is ETB 5,100.00. '
              'Thank you for Banking with CBE!',
        ),
      ]);
      expect(report.incomeMinor, 0);
      expect(report.expenseMinor, 120);
      expect(report.internalMovedMinor, 110120);
    });

    test(
        'bank -> wallet hop pairs across a long delay when both sides '
        'name each other', () async {
      final t = DateTime(2026, 7, 10, 8);
      final report = await _julyReport([
        _tx(
          id: 'tb-out',
          accountId: 'hibret-main',
          type: TransactionType.expense,
          amountMinor: 1001200,
          at: t,
          snippet: 'Dear customer, Please be informed that ETB 10012 '
              'Outgoing Transfer To Tele-Birr Via Mobile is made from your '
              'account 474041*******013  . Available Balance : 6452.14 '
              'Current Balance : 6452.14  .For further queries please call '
              '995. United, We Prosper!',
        ),
        _tx(
          id: 'tb-in',
          accountId: 'telebirr-main',
          type: TransactionType.income,
          amountMinor: 1000000,
          at: t.add(const Duration(hours: 5)),
          categoryId: 'transfer_in',
          snippet: 'Dear Abebe You have received ETB 10,000.00 from Hibret '
              'Bank on 10/07/2026 13:00:04. Your transaction number is '
              'DF24JC2U3S. Thank you for using telebirr',
        ),
      ]);
      expect(report.incomeMinor, 0);
      expect(report.expenseMinor, 1200);
    });

    test('M-PESA credit "from Hibret Bank" pairs with the Hibret debit',
        () async {
      final t = DateTime(2026, 7, 13, 16, 40);
      final report = await _julyReport([
        _tx(
          id: 'mp-out',
          accountId: 'hibret-main',
          type: TransactionType.expense,
          amountMinor: 200000,
          at: t,
          snippet: 'Dear customer, Please be informed that ETB 2000 '
              'Outgoing Transfer To M-Pesa Via Mobile is made from your '
              'account 474041*******013  . Available Balance : 4452.14 '
              'Current Balance : 4452.14  .',
        ),
        _tx(
          id: 'mp-in',
          accountId: 'mpesa-main',
          type: TransactionType.income,
          amountMinor: 200000,
          at: t.add(const Duration(minutes: 3)),
          categoryId: 'income',
          snippet: 'ውድ Abebe፣ 2,000.00 ብር ከ 9000811 - Hibret Bank S.C-B2C '
              'በ 13/7/26 በ 4:43 PM ላይ ተቀብለዋል። የገንዘብ ዝውውር መለያ ቁጥር '
              'UCD1LRXBYF ነው። የእርስዎ አሁን ያለው የM-PESA ቀሪ ሒሳብ 2,369.00 ብር ነው።',
        ),
      ]);
      expect(report.incomeMinor, 0);
      expect(report.expenseMinor, 0);
      expect(report.internalMovedMinor, 200000);
    });
  });

  group('a debit that never says where the money went', () {
    // Real shapes: CBE's app top-up of telebirr debits the account without
    // naming telebirr; only telebirr's receipt names the bank.
    TransactionRecord cbeDebit(DateTime at, {int minor = 500575}) => _tx(
          id: 'cbe-debit',
          accountId: 'cbe-main',
          type: TransactionType.expense,
          amountMinor: minor,
          at: at,
          categoryId: 'fees',
          snippet: 'Dear Abebe Kebede your Account 1********9722 has been '
              'debited with ETB ${(minor / 100).toStringAsFixed(2)} including '
              'Service charge ETB5.00ETB0.25 and VAT(15%) ETB0.75. Your '
              'Current Balance is ETB 14977.6. Thank you for Banking with '
              'CBE!.',
        );
    TransactionRecord telebirrCredit(DateTime at,
            {String from = 'Commercial '
                'Bank of Ethiopia'}) =>
        _tx(
          id: 'tb-credit',
          accountId: 'telebirr-main',
          type: TransactionType.income,
          amountMinor: 500000,
          at: at,
          categoryId: 'transfer_in',
          snippet: 'Dear Abebe, You have received  ETB 5,000.00 by '
              'transaction number DJ30DW1SRY on 2026-07-03 18:04:56 from '
              '$from to your telebirr Account 2519******69 - Abebe Kebede '
              'Alemu. Your current balance is ETB 9,832.48. Thank you for '
              'using telebirr Ethio telecom',
        );

    test('pairs when the wallet receipt names the bank, minutes apart',
        () async {
      final t = DateTime(2026, 7, 3, 18, 4);
      final report = await _julyReport(
          [cbeDebit(t), telebirrCredit(t.add(const Duration(minutes: 1)))]);
      expect(report.incomeMinor, 0);
      expect(report.expenseMinor, 575);
      expect(report.internalMovedMinor, 500575);
    });

    test('a BoA "P2P incoming settlement" credit pairs with the CBE debit',
        () async {
      final t = DateTime(2026, 7, 24, 16, 51);
      final report = await _julyReport([
        cbeDebit(t, minor: 607406),
        _tx(
          id: 'boa-in',
          accountId: 'boa-main',
          type: TransactionType.income,
          amountMinor: 600000,
          at: t.add(const Duration(minutes: 1)),
          categoryId: 'income',
          snippet: 'Dear ABEBE, your account 1*****25 was credited with ETB '
              '6,000.00 by A/R - P2P incoming settlement accou. Available '
              'Balance:  ETB 6,192.43. Receipt: '
              'https://cs.bankofabyssinia.com/slip/?trx=FT25328DXTD110104',
        ),
      ]);
      expect(report.incomeMinor, 0);
      expect(report.expenseMinor, 7406);
    });

    test('does not pair hours apart', () async {
      final t = DateTime(2026, 7, 3, 18, 4);
      final report = await _julyReport(
          [cbeDebit(t), telebirrCredit(t.add(const Duration(hours: 2)))]);
      expect(report.incomeMinor, 500000);
      expect(report.expenseMinor, 500575);
    });

    test('does not pair when the receipt names a different bank', () async {
      final t = DateTime(2026, 7, 3, 18, 4);
      final report = await _julyReport([
        cbeDebit(t),
        telebirrCredit(t.add(const Duration(minutes: 1)), from: 'Hibret Bank'),
      ]);
      expect(report.incomeMinor, 500000);
      expect(report.expenseMinor, 500575);
    });
  });

  group('one-sided own transfers (the other bank sent no SMS)', () {
    test('sent to an account in your own name', () async {
      final report = await _julyReport([
        _nameSource(),
        _tx(
          id: 'own-name',
          accountId: 'cbe-main',
          type: TransactionType.expense,
          amountMinor: 110120,
          at: DateTime(2026, 7, 9, 18),
          categoryId: 'transfer_out',
          snippet: 'Dear  Abebe Kebede Alemu You have successfully '
              'transferred ETB1100.00 from account 1**9722 to account '
              '1**4607 (Abebe K. A.). Service charge of ETB 1.00 and '
              'VAT(15%) of ETB0.15 and Disaster Recovery(5%) of 0.05 with '
              'total of ETB1101.20 .Your current balance is ETB89,468.32.',
        ),
      ]);
      // Only the itemized ETB 1.20 is spending.
      expect(report.expenseMinor, 120);
      expect(report.internalMovedMinor, 110120);
    });

    test('telebirr -> "<bank> account number" of your own account', () async {
      final report = await _julyReport([
        _nameSource(),
        _tx(
          id: 'tb-to-cbe',
          accountId: 'telebirr-main',
          type: TransactionType.expense,
          amountMinor: 300000,
          at: DateTime(2026, 7, 27, 18, 44),
          categoryId: 'transfer_out',
          snippet: 'Dear Abebe\nYou have transferred ETB 3,000.00 '
              'successfully from your telebirr account 2519******69 to '
              'Commercial Bank of Ethiopia account number 1000217459722 on '
              '27/07/2026 18:44:13. Your telebirr transaction number is '
              'DIR974DA1T and your bank transaction number is FT26270W75F0. '
              'The service fee is  ETB 7.83 and  15% VAT on the service fee '
              'is ETB 1.17.',
        ),
      ]);
      expect(report.expenseMinor, 0);
      expect(report.internalMovedMinor, 300000);
    });

    test('received from yourself at another bank', () async {
      final report = await _julyReport([
        _nameSource(),
        _tx(
          id: 'from-self',
          accountId: 'cbe-main',
          type: TransactionType.income,
          amountMinor: 500000,
          at: DateTime(2026, 7, 14, 9),
          categoryId: 'transfer_in',
          snippet: 'Dear Abebe your Account 1*********9722 has been Credited '
              'with ETB 5,000.00 from ABEBE KEBEDE ALEMU, on 14/07/2026 at '
              '09:00:00 with Ref No FT26195XY Your Current Balance is ETB '
              '30,000.00. Thank you for Banking with CBE!',
        ),
      ]);
      expect(report.incomeMinor, 0);
      expect(report.internalMovedMinor, 500000);
    });

    test('sent to an account number the app has seen as yours', () async {
      final report = await _julyReport([
        // Months ago the bank called 1*****4607 "your Account".
        _tx(
          id: 'old-credit',
          accountId: 'cbe-main',
          type: TransactionType.income,
          amountMinor: 1000,
          at: DateTime(2026, 3, 1),
          categoryId: 'income',
          snippet: 'Dear Abebe your Account 1*****4607 has been credited '
              'with ETB 10.00.',
        ),
        _tx(
          id: 'to-own-acct',
          accountId: 'cbe-main',
          type: TransactionType.expense,
          amountMinor: 200000,
          at: DateTime(2026, 7, 15, 9),
          categoryId: 'transfer_out',
          snippet: 'Dear customer You have successfully transferred '
              'ETB2000.00 from account 1**9722 to account 1**4607.',
        ),
      ]);
      expect(report.expenseMinor, 0);
      expect(report.internalMovedMinor, 200000);
    });
  });

  group('never swallows real income or spending', () {
    test(
        'a transfer to someone else is not paired with a credit from '
        'someone else', () async {
      final t = DateTime(2026, 7, 16, 12);
      final report = await _julyReport([
        _tx(
          id: 'to-hanna',
          accountId: 'cbe-main',
          type: TransactionType.expense,
          amountMinor: 40058,
          at: t,
          categoryId: 'transfer_out',
          snippet: _cbeFullNameReceipt,
        ),
        _tx(
          id: 'from-mekuria',
          accountId: 'telebirr-main',
          type: TransactionType.income,
          amountMinor: 40000,
          at: t.add(const Duration(minutes: 10)),
          categoryId: 'transfer_in',
          snippet: 'Dear Abebe You have received ETB 400.00 from Mekuria '
              'Solomon(2519****4846) on 16/07/2026 12:10:04. Your '
              'transaction number is DF24JC2U3S.',
        ),
      ]);
      expect(report.incomeMinor, 40000);
      expect(report.expenseMinor, 40058);
      expect(report.internalMovedMinor, 0);
    });

    test('a transfer that names telebirr does not pair with a CBE credit',
        () async {
      final t = DateTime(2026, 7, 17, 12);
      final report = await _julyReport([
        _tx(
          id: 'to-tb',
          accountId: 'hibret-main',
          type: TransactionType.expense,
          amountMinor: 100000,
          at: t,
          snippet: 'Dear customer, Please be informed that ETB 1000 '
              'Outgoing Transfer To Tele-Birr Via Mobile is made from your '
              'account 474041*******013  .',
        ),
        _tx(
          id: 'cbe-credit',
          accountId: 'cbe-main',
          type: TransactionType.income,
          amountMinor: 100000,
          at: t.add(const Duration(minutes: 20)),
          categoryId: 'income',
          snippet: 'Dear Abebe your Account 1*****9722 has been credited '
              'with ETB 1,000.00.',
        ),
      ]);
      expect(report.incomeMinor, 100000);
      expect(report.expenseMinor, 100000);
    });

    test('an ATM cash withdrawal is never a transfer leg', () async {
      final t = DateTime(2026, 7, 18, 19, 50);
      final report = await _julyReport([
        _tx(
          id: 'atm',
          accountId: 'telebirr-main',
          type: TransactionType.expense,
          amountMinor: 200000,
          at: t,
          categoryId: 'transfer_out',
          snippet: 'Dear Abebe The request to withdraw ETB 2,000.00 from '
              'your telebirr account 2519******69  via secret code ****** '
              'on  2026-07-18 19:50:48 using Awash International Bank S C '
              'ATM with transaction number  DHF9TE0367 is successfully '
              'completed.',
        ),
        _tx(
          id: 'credit',
          accountId: 'cbe-main',
          type: TransactionType.income,
          amountMinor: 200000,
          at: t.add(const Duration(minutes: 30)),
          categoryId: 'income',
          snippet: 'Dear Abebe your Account 1*****9722 has been credited '
              'with ETB 2,000.00.',
        ),
      ]);
      expect(report.incomeMinor, 200000);
      expect(report.expenseMinor, 200000);
    });

    test('a same-name stranger is not you (different father\'s name)',
        () async {
      final report = await _julyReport([
        _nameSource(),
        _tx(
          id: 'namesake',
          accountId: 'cbe-main',
          type: TransactionType.expense,
          amountMinor: 50058,
          at: DateTime(2026, 7, 19, 9),
          categoryId: 'transfer_out',
          snippet: 'Dear Abebe, You have transfered ETB 500.00 to Abebe '
              'Tesfaye on 19/07/2026 at 09:00:00 from your account '
              '1*********9722.',
        ),
      ]);
      expect(report.expenseMinor, 50058);
      expect(report.internalMovedMinor, 0);
      // The name was read — it just isn't the holder's.
      expect(
        extractMerchant(
          'transfered ETB 500.00 to Abebe Tesfaye on 19/07/2026',
          isExpense: true,
        ),
        'Abebe Tesfaye',
      );
    });
  });

  group('your answer always wins', () {
    test('marking a transaction as your own transfer removes it', () async {
      final report = await _julyReport([
        _tx(
          id: 'marked',
          accountId: 'cbe-main',
          type: TransactionType.expense,
          amountMinor: 300000,
          at: DateTime(2026, 7, 20, 9),
          snippet: 'Dear Abebe your Account 1*****9722 has been debited '
              'with ETB3,000.00.',
          ownTransfer: OwnTransferOverride.own,
        ),
      ]);
      expect(report.expenseMinor, 0);
      expect(report.internalMovedMinor, 300000);
    });

    test('"not my own transfer" breaks an automatic pair', () async {
      final t = DateTime(2026, 7, 21, 9);
      final report = await _julyReport([
        _tx(
          id: 'pair-out',
          accountId: 'hibret-main',
          type: TransactionType.expense,
          amountMinor: 1001200,
          at: t,
          snippet: 'ETB 10012 Outgoing Transfer To Tele-Birr Via Mobile is '
              'made from your account 474041*******013',
        ),
        _tx(
          id: 'pair-in',
          accountId: 'telebirr-main',
          type: TransactionType.income,
          amountMinor: 1000000,
          at: t.add(const Duration(minutes: 2)),
          categoryId: 'transfer_in',
          snippet: 'You have received ETB 10,000.00 from Hibret Bank.',
          ownTransfer: OwnTransferOverride.notOwn,
        ),
      ]);
      expect(report.incomeMinor, 1000000);
      expect(report.expenseMinor, 1001200);
      expect(report.internalMovedMinor, 0);
    });

    test('marking one transfer teaches the recipient for next time', () async {
      // The other bank spells the holder's name differently, so the name
      // match can't catch it — the user's answer does.
      String body(String amount) =>
          'Dear Abebe, You have transfered ETB $amount to ABEBE KEBEDDE on '
          '22/07/2026 at 09:00:00 from your account 1*********9722.';
      final report = await _julyReport([
        _nameSource(),
        _tx(
          id: 'taught',
          accountId: 'cbe-main',
          type: TransactionType.expense,
          amountMinor: 100000,
          at: DateTime(2026, 7, 22, 9),
          categoryId: 'transfer_out',
          snippet: body('1,000.00'),
          ownTransfer: OwnTransferOverride.own,
        ),
        _tx(
          id: 'learned',
          accountId: 'cbe-main',
          type: TransactionType.expense,
          amountMinor: 70000,
          at: DateTime(2026, 7, 23, 9),
          categoryId: 'transfer_out',
          snippet: body('700.00'),
        ),
      ]);
      expect(report.expenseMinor, 0);
      expect(report.internalMovedMinor, 170000);
    });

    test('"not my own transfer" stops a name match for that recipient',
        () async {
      // A relative who shares the holder's given and father's name.
      TransactionRecord toNamesake(String id, int minor, int day,
              {OwnTransferOverride answer = OwnTransferOverride.none}) =>
          _tx(
            id: id,
            accountId: 'cbe-main',
            type: TransactionType.expense,
            amountMinor: minor,
            at: DateTime(2026, 7, day, 9),
            categoryId: 'transfer_out',
            snippet: 'Dear Abebe, You have transfered ETB ${minor ~/ 100}.00 '
                'to Abebe Kebede on $day/07/2026 at 09:00:00 from your '
                'account 1*********9722.',
            ownTransfer: answer,
          );

      // Without an answer the name match calls it an own transfer...
      final before = analyzeOwnTransfers(
        [_nameSource(), toNamesake('cousin-2', 50000, 25)],
      );
      expect(before.reasonById['cousin-2'], OwnTransferReason.ownName);

      // ...until the user says this recipient is not them.
      final report = await _julyReport([
        _nameSource(),
        toNamesake('cousin-1', 100000, 24, answer: OwnTransferOverride.notOwn),
        toNamesake('cousin-2', 50000, 25),
      ]);
      expect(report.expenseMinor, 150000);
      expect(report.internalMovedMinor, 0);
    });
  });

  test('a bank filter never turns an own transfer into spending', () async {
    final t = DateTime(2026, 7, 26, 10);
    final report = await _julyReport(
      [
        _tx(
          id: 'f-out',
          accountId: 'hibret-main',
          type: TransactionType.expense,
          amountMinor: 1001200,
          at: t,
          snippet: 'ETB 10012 Outgoing Transfer To Tele-Birr Via Mobile is '
              'made from your account 474041*******013',
        ),
        _tx(
          id: 'f-in',
          accountId: 'telebirr-main',
          type: TransactionType.income,
          amountMinor: 1000000,
          at: t.add(const Duration(minutes: 2)),
          categoryId: 'transfer_in',
          snippet: 'You have received ETB 10,000.00 from Hibret Bank.',
        ),
      ],
      institutionCodes: {'hibret'},
    );
    expect(report.expenseMinor, 1200);
    expect(report.internalMovedMinor, 1001200);
  });

  test(
      'an unmatched transfer to a wallet you also use is flagged for a '
      'yes/no, not silently dropped', () {
    final t = DateTime(2026, 7, 27, 10);
    final records = [
      _tx(
        id: 'tb-history',
        accountId: 'telebirr-main',
        type: TransactionType.expense,
        amountMinor: 10000,
        at: DateTime(2026, 7, 1),
        categoryId: 'airtime',
        snippet: 'Dear Abebe You have recharged ETB 100.00 airtime.',
      ),
      _tx(
        id: 'maybe-own',
        accountId: 'hibret-main',
        type: TransactionType.expense,
        amountMinor: 501200,
        at: t,
        snippet: 'ETB 5012 Outgoing Transfer To Tele-Birr Via Mobile is made '
            'from your account 474041*******013',
      ),
      _nameSource(),
    ];
    final flows = analyzeOwnTransfers(records);
    expect(flows.internalIds, isNot(contains('maybe-own')));
    expect(flows.suggestedIds, contains('maybe-own'));
    // A transfer to a named stranger is never a suggestion.
    expect(flows.suggestedIds, isNot(contains('name-source')));
  });

  test(
      'a payment into someone else\'s account at your bank is spending, '
      'not a question', () {
    final flows = analyzeOwnTransfers([
      _tx(
        id: 'cbe-own',
        accountId: 'cbe-main',
        type: TransactionType.income,
        amountMinor: 13000,
        at: DateTime(2026, 7, 1),
        categoryId: 'income',
        snippet: 'Dear Abebe Kebede your Account 1********9722 has been '
            'credited with ETB 130.',
      ),
      _tx(
        id: 'tb-to-other',
        accountId: 'telebirr-main',
        type: TransactionType.expense,
        amountMinor: 250000,
        at: DateTime(2026, 7, 2, 14, 35),
        categoryId: 'transfer_out',
        snippet: 'Dear Abebe\nYou have transferred ETB 2,500.00 successfully '
            'from your telebirr account 2519******69 to Commercial Bank of '
            'Ethiopia account number 1000123456688 on 02/07/2026 14:35:10.',
      ),
    ]);
    expect(flows.internalIds, isNot(contains('tb-to-other')));
    expect(flows.suggestedIds, isNot(contains('tb-to-other')));
  });

  test('a late bank SMS still pairs when both receipts name each other', () {
    final t = DateTime(2026, 7, 3, 8, 28);
    final flows = analyzeOwnTransfers([
      _tx(
        id: 'late-in',
        accountId: 'telebirr-main',
        type: TransactionType.income,
        amountMinor: 1000000,
        at: t,
        categoryId: 'transfer_in',
        snippet: 'Dear Abebe, You have received  ETB 10,000.00 by '
            'transaction number DJ1 on 2026-07-03 08:28:00 from Hibret Bank '
            'to your telebirr Account 2519******69 - Abebe Kebede Alemu.',
      ),
      // Hibret's own receipt for the same transfer arrived four hours late.
      _tx(
        id: 'late-out',
        accountId: 'hibret-main',
        type: TransactionType.expense,
        amountMinor: 1001150,
        at: t.add(const Duration(hours: 4, minutes: 10)),
        snippet: 'ETB 10011.5 Outgoing Transfer To Tele-Birr Via Mobile is '
            'made from your account 474041*******013',
      ),
    ]);
    expect(flows.partnerById['late-out'], 'late-in');
  });

  test(
      'Hibret "To Ethswitch" (interbank) pairs with the BoA credit that '
      'landed hours before its SMS', () {
    final t = DateTime(2026, 7, 1, 20, 46);
    final flows = analyzeOwnTransfers([
      _tx(
        id: 'boa-in',
        accountId: 'boa-main',
        type: TransactionType.income,
        amountMinor: 130000,
        at: t,
        categoryId: 'income',
        snippet: 'Dear ABEBE, your account 1*****25 was credited with ETB '
            '1,300.00 by A/R - P2P incoming settlement accou. Available '
            'Balance:  ETB 3,647.30.',
      ),
      _tx(
        id: 'ethswitch-out',
        accountId: 'hibret-main',
        type: TransactionType.expense,
        amountMinor: 130598,
        at: t.add(const Duration(hours: 4, minutes: 33)),
        snippet: 'Dear customer, Please be informed that ETB 1305.98 Outgoing '
            'Fund Transfer To Ethswitch is made from your account '
            '474041*******013  . Available Balance : 220.8',
      ),
    ]);
    expect(flows.partnerById['ethswitch-out'], 'boa-in');
  });

  test('no question when the wallet reports its credits and none matched', () {
    final flows = analyzeOwnTransfers([
      // telebirr does send SMS for money coming in...
      _tx(
        id: 'tb-credit-history',
        accountId: 'telebirr-main',
        type: TransactionType.income,
        amountMinor: 5300,
        at: DateTime(2026, 7, 1),
        categoryId: 'transfer_in',
        snippet: 'Dear Abebe You have received ETB 53.00 from Mekuria '
            'Solomon(2519****4846) on 01/07/2026 13:14:04.',
      ),
      // ...so a Hibret -> telebirr transfer with no telebirr credit went to
      // someone else's wallet.
      _tx(
        id: 'to-someones-wallet',
        accountId: 'hibret-main',
        type: TransactionType.expense,
        amountMinor: 50000,
        at: DateTime(2026, 7, 2, 9, 8),
        snippet: 'ETB 500 Outgoing Transfer To Tele-Birr Via Mobile is made '
            'from your account 474041*******013',
      ),
    ]);
    expect(flows.internalIds, isNot(contains('to-someones-wallet')));
    expect(flows.suggestedIds, isNot(contains('to-someones-wallet')));
  });

  test('reasons are reported for every own transfer', () {
    final t = DateTime(2026, 7, 28, 10);
    final flows = analyzeOwnTransfers([
      _nameSource(),
      _tx(
        id: 'p-out',
        accountId: 'hibret-main',
        type: TransactionType.expense,
        amountMinor: 100000,
        at: t,
        snippet: 'ETB 1000 Outgoing Transfer To Tele-Birr Via Mobile is made '
            'from your account 474041*******013',
      ),
      _tx(
        id: 'p-in',
        accountId: 'telebirr-main',
        type: TransactionType.income,
        amountMinor: 100000,
        at: t.add(const Duration(minutes: 1)),
        categoryId: 'transfer_in',
        snippet: 'You have received ETB 1,000.00 from Hibret Bank.',
      ),
      _tx(
        id: 'sav',
        accountId: 'cbe-main',
        type: TransactionType.expense,
        amountMinor: 400000,
        at: t,
        categoryId: 'savings',
      ),
    ]);
    expect(flows.reasonById['p-out'], OwnTransferReason.paired);
    expect(flows.reasonById['p-in'], OwnTransferReason.paired);
    expect(flows.partnerById['p-out'], 'p-in');
    expect(flows.partnerById['p-in'], 'p-out');
    expect(flows.reasonById['sav'], OwnTransferReason.savings);
  });
}
