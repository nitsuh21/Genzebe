import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';

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
    // Position-based: a CBE transfer contains BOTH "debited" (your side) and
    // "credited to the beneficiary" — the earlier cue decides whose
    // transaction this is.
    final isExpense = isExpenseMessage(lowered);

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

const _expenseCues = [
  'debited',
  'debit',
  'paid',
  'payment',
  'purchase',
  'withdraw',
  'sent',
  'transferred to',
  'you have transferred',
  'ተከፍሏል',
  'ወጪ',
];

const _incomeCues = [
  'credited',
  'credit',
  'received',
  'deposit',
  'salary',
  'refund',
  'refunded',
  'reversal',
  'transferred to your',
  'ገቢ',
  'ተቀብለዋል',
  'ተመላሽ',
];

/// Direction detection: the EARLIEST cue in the message wins.
///
/// Ethiopian bank/wallet SMS lead with the primary action ("Your account has
/// been debited…", "You have received…") and often mention the counterparty's
/// side later ("…and credited to the beneficiary", "…Abebe has received the
/// amount"). Whichever side is mentioned first is whose transaction this is;
/// a bare income word later in the body must not flip an expense to income.
bool isExpenseMessage(String lowered) {
  int? earliest(List<String> cues) {
    int? best;
    for (final cue in cues) {
      final index = lowered.indexOf(cue);
      if (index >= 0 && (best == null || index < best)) best = index;
    }
    return best;
  }

  final expenseAt = earliest(_expenseCues);
  final incomeAt = earliest(_incomeCues);

  if (incomeAt == null) return true; // no income cue -> default expense
  if (expenseAt == null) return false; // only income cues -> income
  // Same position means an income phrase extends an expense one (e.g.
  // 'transferred to' vs 'transferred to your') — the longer, more specific
  // income phrase wins.
  return expenseAt < incomeAt;
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
///
/// Order matters: the first matching rule wins, so more specific categories
/// (airtime, fees) come before broad ones (shopping). Keywords include the
/// common Ethiopian merchants and Amharic terms that appear in real bank and
/// Telebirr notifications.
String inferCategory({required String body, required bool isExpense}) {
  const Map<String, List<String>> rules = {
    'salary': ['salary', 'payroll', 'wage', 'ደመወዝ'],
    'savings': ['saving', 'deposit to', 'fixed', 'equb', 'iqub', 'እቁብ', 'ቁጠባ'],
    'airtime': [
      'airtime',
      'recharge',
      'top up',
      'topup',
      'bundle',
      'data package',
      'internet package',
      'package',
      'minute',
      'የአየር ሰዓት',
    ],
    'fees': [
      'fee',
      'charge',
      'service charge',
      'commission',
      'vat',
      'stamp duty',
      'excise',
      'disaster fund',
    ],
    'rent': ['rent', 'house rent', 'apartment', 'ኪራይ'],
    'transport': [
      'taxi',
      'ride',
      'trip',
      'bus',
      'anbessa',
      'fuel',
      'petrol',
      'benzin',
      'transport',
      'feres',
      'zayride',
      'bolt',
      'uber',
      'yango',
      'little',
    ],
    'groceries': [
      'supermarket',
      'grocery',
      'mart',
      'market',
      'ገበያ',
      'shoa',
      'safari',
      'fresh corner',
      'queens',
      'getfam',
    ],
    'food': [
      'restaurant',
      'cafe',
      'coffee',
      'food',
      'hotel',
      'burger',
      'pizza',
      'juice',
      'bakery',
      'lounge',
      'tomoca',
      'kaldi',
      'kitfo',
      'ምግብ',
    ],
    'bills': [
      'bill',
      'utility',
      'electric',
      'eeu',
      'water',
      'dstv',
      'canal',
      'tv',
      'internet',
      'wifi',
      'መብራት',
      'ውሃ',
    ],
    'health': [
      'pharmacy',
      'hospital',
      'clinic',
      'medical',
      'health',
      'ፋርማሲ',
      'ሆስፒታል',
      'መድኃኒት',
    ],
    'education': [
      'school',
      'tuition',
      'university',
      'college',
      'course',
      'ትምህርት',
    ],
    'entertainment': [
      'cinema',
      'movie',
      'game',
      'bet',
      'ticket',
      'concert',
      'hulusport',
    ],
    'shopping': ['shop', 'store', 'mall', 'boutique', 'purchase'],
  };

  for (final entry in rules.entries) {
    for (final keyword in entry.value) {
      if (_containsKeyword(body, keyword)) {
        if (!isExpense && entry.key != 'salary' && entry.key != 'savings') {
          continue;
        }
        if (isExpense && entry.key == 'salary') continue;
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

// ---------------------------------------------------------------------------
// Merchant / counterparty extraction
// ---------------------------------------------------------------------------

// Amount with the currency token on either side: "ETB 120.00" / "320.00 birr".
const _amountPhrase =
    r'(?:etb|birr|ብር)?\s*[\d,.]*\s*(?:etb|birr|ብር)?\s*';

final List<RegExp> _expenseMerchantPatterns = [
  // "paid ETB 120.00 to Shoa Supermarket via telebirr" /
  // "paid 320.00 birr to GebeyaGo Delivery via app"
  RegExp('paid\\s+${_amountPhrase}to\\s+([^.,\\n]{2,48}?)\\s+(?:via|through|on|using|ref)',
      caseSensitive: false),
  // "transferred to W/ro Almaz — house rent"
  RegExp(r'transferred\s+to\s+([^.,\n—-]{2,48})', caseSensitive: false),
  // "You have sent ETB 1,500.00 to Emebet K. via telebirr"
  RegExp('sent\\s+${_amountPhrase}to\\s+([^.,\\n]{2,48}?)\\s+(?:via|through|on|ref)',
      caseSensitive: false),
  // "debited ETB 450.00 at Safari Supermarket"
  RegExp(r'\bat\s+([a-zA-Z][^.,\n]{2,48})', caseSensitive: false),
  // "paid ETB 260.00 for Ride trip via telebirr"
  RegExp(r'\bfor\s+([a-zA-Z][^.,\n]{2,48}?)\s+(?:via|through|on|using)',
      caseSensitive: false),
];

final List<RegExp> _incomeMerchantPatterns = [
  // "received ETB 500.00 from Abebe Kebede via telebirr"
  RegExp(r'from\s+([^.,\n]{2,48}?)\s+(?:via|through|on|ref)',
      caseSensitive: false),
  RegExp(r'from\s+([^.,\n]{2,48})', caseSensitive: false),
];

/// Extracts the merchant / counterparty name from a transaction SMS, or null
/// when none can be found. Used for display and for learned category rules.
String? extractMerchant(String body, {required bool isExpense}) {
  final patterns =
      isExpense ? _expenseMerchantPatterns : _incomeMerchantPatterns;
  for (final pattern in patterns) {
    final match = pattern.firstMatch(body);
    final raw = match?.group(1)?.trim();
    if (raw == null || raw.isEmpty) continue;
    final cleaned = _cleanMerchant(raw);
    if (cleaned != null) return cleaned;
  }
  return null;
}

String? _cleanMerchant(String raw) {
  var value = raw
      .replaceAll(RegExp(r'''["'“”]'''), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Drop trailing possessive/connector fragments left by loose matches.
  value = value.replaceAll(RegExp(r'[—–-]\s*$'), '').trim();
  if (value.length < 2) return null;
  // Masked accounts / OTP-ish fragments are not merchants.
  if (value.contains('*')) return null;
  if (RegExp(r'^[\d\s+/-]+$').hasMatch(value)) return null;
  if (value.length > 48) value = value.substring(0, 48).trim();
  return value;
}

/// Canonical form used as the key for learned category rules.
String normalizeMerchant(String merchant) {
  return merchant
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9ሀ-፿ ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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
