import 'package:genzebet/features/sms_ingestion/domain/models/sms_models.dart';

abstract class SmsParserTemplate {
  bool canParse(SmsMessage sms);
  ParsedSmsTransaction? parse(SmsMessage sms);
}

/// Fallback parser for any bank/wallet SMS that mentions money.
class GenericAmountParserTemplate implements SmsParserTemplate {
  const GenericAmountParserTemplate();

  @override
  bool canParse(SmsMessage sms) {
    final normalized = sms.body.toLowerCase();
    return _containsCurrencyToken(normalized) &&
        _looksTransactionalMessage(normalized);
  }

  @override
  ParsedSmsTransaction? parse(SmsMessage sms) {
    final lowered = sms.body.toLowerCase();
    if (_shouldIgnoreNonLedgerMessage(lowered)) return null;

    final amountMajor = extractTransactionAmountMajor(sms.body);
    if (amountMajor == null) return null;
    final isExpense = isExpenseMessage(lowered);
    final baseConfidence = lowered.contains('etb') ||
            lowered.contains('birr') ||
            lowered.contains('ብር')
        ? 0.82
        : 0.6;

    return ParsedSmsTransaction(
      detectedAmountMinor: (amountMajor * 100).round() * (isExpense ? -1 : 1),
      confidence: baseConfidence,
      categoryHint: inferCategory(body: lowered, isExpense: isExpense),
      description: sms.body,
      institution: EthiopianInstitution.unknown,
      reference: extractReference(sms.body),
      balanceMinor: extractBalanceMinor(sms.body),
      accountNumberHint: extractAccountHint(sms.body),
    );
  }
}

abstract class _InstitutionTemplate implements SmsParserTemplate {
  const _InstitutionTemplate(this.institution, this.senderKeywords);

  final EthiopianInstitution institution;
  final List<String> senderKeywords;

  @override
  bool canParse(SmsMessage sms) {
    final sender = sms.sender.toLowerCase();
    final body = sms.body.toLowerCase();
    return senderKeywords.any((kw) => sender.contains(kw) || body.contains(kw));
  }

  @override
  ParsedSmsTransaction? parse(SmsMessage sms) {
    final lowered = sms.body.toLowerCase();
    if (_shouldIgnoreNonLedgerMessage(lowered)) return null;

    final amountMajor = extractTransactionAmountMajor(sms.body);
    if (amountMajor == null) return null;
    final isExpense = isExpenseMessage(lowered);

    return ParsedSmsTransaction(
      detectedAmountMinor: (amountMajor * 100).round() * (isExpense ? -1 : 1),
      confidence: _confidenceFor(lowered),
      categoryHint: inferCategory(body: lowered, isExpense: isExpense),
      description: sms.body,
      institution: institution,
      reference: extractReference(sms.body),
      balanceMinor: extractBalanceMinor(sms.body),
      accountNumberHint: extractAccountHint(sms.body),
    );
  }

  double _confidenceFor(String loweredBody) {
    var confidence = 0.74;
    if (loweredBody.contains('etb') ||
        loweredBody.contains('birr') ||
        loweredBody.contains('ብር')) {
      confidence += 0.08;
    }
    if (loweredBody.contains('account') ||
        loweredBody.contains('wallet') ||
        loweredBody.contains('ac ')) {
      confidence += 0.06;
    }
    if (extractReference(loweredBody) != null) {
      confidence += 0.04;
    }
    if (isExpenseMessage(loweredBody) ||
        loweredBody.contains('credited') ||
        loweredBody.contains('received')) {
      confidence += 0.04;
    }
    return confidence.clamp(0.0, 0.98).toDouble();
  }
}

class CbeSmsParserTemplate extends _InstitutionTemplate {
  const CbeSmsParserTemplate()
      : super(EthiopianInstitution.cbe, const ['cbe', 'commercial bank']);

  @override
  ParsedSmsTransaction? parse(SmsMessage sms) {
    final lowered = sms.body.toLowerCase();
    final isCredit = lowered.contains('credited') || lowered.contains('credit');
    final isDebit = lowered.contains('debited') || lowered.contains('debit');
    final isExpense = isDebit && !isCredit;

    final amountMajor = _extractCbeTransactionAmountMajor(
          sms.body,
          isExpense: isExpense,
        ) ??
        extractTransactionAmountMajor(sms.body);
    if (amountMajor == null) return null;

    var category = inferCategory(body: lowered, isExpense: isExpense);
    if (isExpense &&
        (lowered.contains('service charge') ||
            lowered.contains('vat') ||
            lowered.contains('disaster fund'))) {
      category = 'fees';
    }

    return ParsedSmsTransaction(
      detectedAmountMinor: (amountMajor * 100).round() * (isExpense ? -1 : 1),
      confidence: 0.96,
      categoryHint: category,
      description: sms.body,
      institution: EthiopianInstitution.cbe,
      reference: _extractCbeReference(sms.body) ?? extractReference(sms.body),
      balanceMinor: extractBalanceMinor(sms.body),
      accountNumberHint: extractAccountHint(sms.body),
    );
  }
}

class AwashSmsParserTemplate extends _InstitutionTemplate {
  const AwashSmsParserTemplate()
      : super(EthiopianInstitution.awash, const ['awash']);
}

class TelebirrSmsParserTemplate extends _InstitutionTemplate {
  const TelebirrSmsParserTemplate()
      : super(EthiopianInstitution.telebirr, const ['telebirr', 'tele birr']);
}

class BoaSmsParserTemplate extends _InstitutionTemplate {
  const BoaSmsParserTemplate()
      : super(EthiopianInstitution.boa, const ['abyssinia', 'boa']);
}

class HibretSmsParserTemplate extends _InstitutionTemplate {
  const HibretSmsParserTemplate()
      : super(EthiopianInstitution.hibret, const ['hibret', 'united bank']);
}

class DashenSmsParserTemplate extends _InstitutionTemplate {
  const DashenSmsParserTemplate()
      : super(EthiopianInstitution.dashen, const ['dashen']);
}

class SmsParserEngine {
  SmsParserEngine(this._templates);

  final List<SmsParserTemplate> _templates;

  ParsedSmsTransaction? parse(SmsMessage sms) {
    for (final template in _templates) {
      if (!template.canParse(sms)) continue;
      final parsed = template.parse(sms);
      if (parsed != null) return parsed;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Extraction helpers (top-level so they can be unit tested and reused).
// ---------------------------------------------------------------------------

const _amountCapturePattern = r'([0-9]+(?:[,\s][0-9]{3})*(?:\.[0-9]{1,2})?)';

final _amountWithCurrency = RegExp(
  '(?:etb|birr|ብር)\\s*$_amountCapturePattern',
  caseSensitive: false,
);
final _amountBeforeCurrency = RegExp(
  '$_amountCapturePattern\\s*(?:etb|birr|ብር)',
  caseSensitive: false,
);
final _balanceRegex = RegExp(
  '(?:bal(?:ance)?|available(?:\\s+balance)?|current\\s+balance|ቀሪ\\s*ሂሳብ)(?:\\s+is|[:\\s])*(?:etb|birr|ብር)?\\s*$_amountCapturePattern',
  caseSensitive: false,
);

double? _toMajor(String? raw) {
  if (raw == null) return null;
  final normalized = raw.replaceAll(',', '').replaceAll(' ', '');
  return double.tryParse(normalized);
}

/// Extracts the transaction amount, deliberately skipping the balance figure
/// when both appear in the same message.
double? extractTransactionAmountMajor(String body) {
  final balanceRaw = _balanceRegex.firstMatch(body)?.group(1);
  final balance = _toMajor(balanceRaw);

  final candidates = <double>[];
  for (final m in _amountWithCurrency.allMatches(body)) {
    final v = _toMajor(m.group(1));
    if (v != null) candidates.add(v);
  }
  for (final m in _amountBeforeCurrency.allMatches(body)) {
    final v = _toMajor(m.group(1));
    if (v != null) candidates.add(v);
  }

  for (final value in candidates) {
    if (balance != null && value == balance) continue;
    return value;
  }
  if (candidates.isNotEmpty) return candidates.first;
  return null;
}

int? extractBalanceMinor(String body) {
  final major = _toMajor(_balanceRegex.firstMatch(body)?.group(1));
  if (major == null) return null;
  return (major * 100).round();
}

String? extractReference(String body) {
  final match = RegExp(
    r'(?:ref(?:erence)?|trx|txn|txnid|transaction)[:\s#-]*([a-z0-9]{4,})',
    caseSensitive: false,
  ).firstMatch(body);
  return match?.group(1);
}

String? extractAccountHint(String body) {
  final match = RegExp(
    r'(?:acc(?:ount)?|wallet)[:\s#-]*([0-9\*]{3,})',
    caseSensitive: false,
  ).firstMatch(body);
  return match?.group(1);
}

bool isExpenseMessage(String lowered) {
  const expenseWords = [
    'debited',
    'debit',
    'paid',
    'payment',
    'purchase',
    'withdraw',
    'sent',
    'transferred to',
    'ተከፍሏል',
    'ወጪ',
  ];
  const incomeWords = [
    'credited',
    'credit',
    'received',
    'deposit',
    'salary',
    'refund',
    'ገቢ',
    'ተቀብለዋል',
  ];
  for (final word in incomeWords) {
    if (lowered.contains(word)) return false;
  }
  for (final word in expenseWords) {
    if (lowered.contains(word)) return true;
  }
  // Default: treat unknown direction as expense (more conservative).
  return true;
}

bool _isAirtimeOrPackageMessage(String lowered) {
  const tokens = [
    'airtime',
    'recharge',
    'top up',
    'topup',
    'data package',
    'bundle',
    'internet package',
    'package',
  ];
  for (final token in tokens) {
    if (_containsKeyword(lowered, token)) return true;
  }
  return false;
}

/// Keyword-driven category inference from the message body.
String inferCategory({required String body, required bool isExpense}) {
  const Map<String, List<String>> rules = {
    'groceries': ['supermarket', 'grocery', 'mart', 'market'],
    'food': [
      'restaurant',
      'cafe',
      'coffee',
      'food',
      'hotel',
      'burger',
      'pizza'
    ],
    'transport': [
      'taxi',
      'ride',
      'bus',
      'fuel',
      'petrol',
      'transport',
      'feres',
      'bolt',
      'uber'
    ],
    'shopping': ['shop', 'store', 'mall', 'boutique', 'purchase'],
    'bills': ['bill', 'utility', 'electric', 'water', 'dstv', 'tv', 'internet'],
    'airtime': ['airtime', 'data', 'recharge', 'package', 'minute'],
    'rent': ['rent', 'house', 'apartment'],
    'health': ['pharmacy', 'hospital', 'clinic', 'medical', 'health'],
    'education': ['school', 'tuition', 'university', 'college', 'course'],
    'entertainment': ['cinema', 'movie', 'game', 'bet', 'ticket'],
    'savings': ['saving', 'deposit to', 'fixed'],
    'fees': ['fee', 'charge', 'service charge', 'commission'],
    'salary': ['salary', 'payroll', 'wage'],
  };

  for (final entry in rules.entries) {
    for (final keyword in entry.value) {
      if (_containsKeyword(body, keyword)) {
        if (!isExpense && entry.key != 'salary' && entry.key != 'savings') {
          continue;
        }
        return entry.key;
      }
    }
  }

  if (!isExpense) {
    if (_containsKeyword(body, 'salary') || _containsKeyword(body, 'payroll')) {
      return 'salary';
    }
    if (_containsKeyword(body, 'transfer') || _containsKeyword(body, 'received')) {
      return 'transfer_in';
    }
    return 'income';
  }
  if (_containsKeyword(body, 'transfer') || _containsKeyword(body, 'sent')) {
    return 'transfer_out';
  }
  return 'expense';
}

bool _containsKeyword(String body, String keyword) {
  // Use word-ish boundaries for latin keywords so "rent" doesn't match
  // inside unrelated words like "current".
  final escaped = RegExp.escape(keyword.toLowerCase());
  final pattern = RegExp('(^|[^a-z0-9])$escaped([^a-z0-9]|' r'$)');
  return pattern.hasMatch(body.toLowerCase());
}

bool _containsCurrencyToken(String body) {
  return RegExp(r'(^|[^a-z0-9])(etb|birr|ብር)([^a-z0-9]|$)')
      .hasMatch(body.toLowerCase());
}

bool _looksTransactionalMessage(String body) {
  if (_shouldIgnoreNonLedgerMessage(body)) return false;
  if (_isAirtimeOrPackageMessage(body)) return true;
  const indicators = [
    'debited',
    'debit',
    'credited',
    'credit',
    'paid',
    'payment',
    'purchase',
    'withdraw',
    'sent',
    'transfer',
    'received',
    'deposit',
    'balance',
    'service charge',
    'vat',
    'disaster fund',
    'ገቢ',
    'ወጪ',
    'ተከፍሏል',
    'ተቀብለዋል',
  ];
  for (final token in indicators) {
    if (_containsKeyword(body, token)) return true;
  }
  return false;
}

bool _isLikelyOtpOrVerification(String body) {
  const blockers = [
    'verification code',
    'otp',
    'one-time password',
    'one time password',
    'use this code',
    'do not share',
    'security code',
    'reset code',
    'activation code',
  ];
  for (final blocker in blockers) {
    if (body.contains(blocker)) return true;
  }
  return false;
}

bool _isAirtimeReceivedMirrorMessage(String body) {
  // Provider-side mirror notifications like:
  // "You have received ETB X airtime from ...", which should not create
  // separate ledger income entries.
  return _containsKeyword(body, 'received') &&
      _containsKeyword(body, 'airtime') &&
      _containsKeyword(body, 'from');
}

bool _shouldIgnoreNonLedgerMessage(String body) {
  return _isLikelyOtpOrVerification(body) ||
      _isAirtimeReceivedMirrorMessage(body);
}

double? _extractCbeTransactionAmountMajor(
  String body, {
  required bool isExpense,
}) {
  final totalMatch = RegExp(
    '(?:total(?:\\s+of)?)\\s*(?:etb|birr|ብር)\\s*$_amountCapturePattern',
    caseSensitive: false,
  ).firstMatch(body);
  final totalMajor = _toMajor(totalMatch?.group(1));
  if (isExpense && totalMajor != null) return totalMajor;

  final directionRegex = isExpense
      ? RegExp(
          'debited\\s+with\\s*(?:etb|birr|ብር)\\s*$_amountCapturePattern',
          caseSensitive: false,
        )
      : RegExp(
          'credited\\s+with\\s*(?:etb|birr|ብር)\\s*$_amountCapturePattern',
          caseSensitive: false,
        );
  final directionMajor = _toMajor(directionRegex.firstMatch(body)?.group(1));
  if (directionMajor != null) return directionMajor;

  return null;
}

String? _extractCbeReference(String body) {
  final receiptMatch = RegExp(
    r'(?:branchreceipt/|[?&]id=)([a-z0-9]+)',
    caseSensitive: false,
  ).firstMatch(body);
  return receiptMatch?.group(1);
}
