import 'dart:math' as math;

import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';

export 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart'
    show institutionForSender, inferInstitutionFromSignature, isFinancialSender;

abstract class SmsParserTemplate {
  bool canParse(SmsMessage sms);
  ParsedSmsTransaction? parse(SmsMessage sms);
}

// ---------------------------------------------------------------------------
// Confidence
// ---------------------------------------------------------------------------

/// Bump whenever parser behaviour changes in a way that should rewrite
/// history. The next sync then re-parses the whole inbox once (manual
/// entries and user rejections survive), so old misreads are corrected.
const int kParserVersion = 2;

/// Parses at or above this confidence are booked directly; below it they
/// wait in the review queue for the user.
const double kAutoAcceptConfidence = 0.85;

/// Confidence is a function of the evidence, nothing else.
///
/// Two facts are non-negotiable for auto-accept: a recognised sender and an
/// unambiguous direction phrase. Without both, the score is capped just
/// below [kAutoAcceptConfidence] no matter how much else lines up, because
/// those are precisely the mistakes (wrong account, income booked as
/// expense) a user cannot spot at a glance.
double scoreConfidence(ParseEvidence evidence) {
  var score = evidence.institutionKnown ? 0.80 : 0.58;
  if (evidence.explicitDirection) score += 0.10;
  if (evidence.hasReference) score += 0.03;
  if (evidence.hasBalance) score += 0.03;
  if (evidence.specificCategory) score += 0.02;
  if (evidence.hasCounterparty) score += 0.02;

  final cap = evidence.institutionKnown && evidence.explicitDirection
      ? 0.98
      : kAutoAcceptConfidence - 0.01;
  return (math.min(score, cap) * 100).round() / 100;
}

/// Category ids that mean "no idea, just the direction".
bool isSpecificCategory(String categoryId) {
  return categoryId != 'expense' &&
      categoryId != 'income' &&
      categoryId != 'other';
}

// ---------------------------------------------------------------------------
// Templates
// ---------------------------------------------------------------------------

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

    final direction = detectDirection(lowered);
    final amountMajor = extractTransactionAmountMajor(
      sms.body,
      allowBalanceAsAmount: direction.explicit,
    );
    if (amountMajor == null) return null;
    if (!_looksLikeRealTransaction(sms.body, direction)) return null;

    final isExpense = direction.isExpense;
    final category = inferCategory(body: lowered, isExpense: isExpense);
    final reference = extractReference(sms.body);
    final balanceMinor = extractBalanceMinor(sms.body);
    final evidence = ParseEvidence(
      // The sender is unrecognised by definition here; a signature can name
      // the institution but does not vouch for the message.
      institutionKnown: false,
      explicitDirection: direction.explicit,
      hasReference: reference != null,
      hasBalance: balanceMinor != null,
      specificCategory: isSpecificCategory(category),
      hasCounterparty: extractMerchant(sms.body, isExpense: isExpense) != null,
    );

    return ParsedSmsTransaction(
      detectedAmountMinor: (amountMajor * 100).round() * (isExpense ? -1 : 1),
      confidence: scoreConfidence(evidence),
      categoryHint: category,
      description: sms.body,
      institution: inferInstitutionFromSignature(lowered),
      reference: reference,
      balanceMinor: balanceMinor,
      accountNumberHint: extractAccountHint(sms.body),
      evidence: evidence,
    );
  }
}

abstract class _InstitutionTemplate implements SmsParserTemplate {
  const _InstitutionTemplate(this.institution);

  final EthiopianInstitution institution;

  @override
  bool canParse(SmsMessage sms) {
    // Sender-only: matching on the body misfiles cross-institution messages
    // (a telebirr receipt mentioning "from CBE account" is NOT a CBE
    // transaction). Sync only reads registered senders; the generic
    // template exists for messages the user pastes by hand.
    return institutionForSender(sms.sender) == institution;
  }

  /// Institution-specific amount extraction; null falls back to the shared
  /// currency-token scan.
  double? amountFor(String body, {required DirectionEvidence direction}) =>
      null;

  /// Institution-specific reference extraction; null falls back to the
  /// shared "ref/txn" scan.
  String? referenceFor(String body) => null;

  @override
  ParsedSmsTransaction? parse(SmsMessage sms) {
    final lowered = sms.body.toLowerCase();
    if (_shouldIgnoreNonLedgerMessage(lowered)) return null;

    final direction = detectDirection(lowered);
    final amountMajor = amountFor(sms.body, direction: direction) ??
        extractTransactionAmountMajor(
          sms.body,
          allowBalanceAsAmount: direction.explicit,
        );
    if (amountMajor == null) return null;
    if (!_looksLikeRealTransaction(sms.body, direction)) return null;

    final isExpense = direction.isExpense;
    final category = inferCategory(body: lowered, isExpense: isExpense);
    final reference = referenceFor(sms.body) ?? extractReference(sms.body);
    final balanceMinor = extractBalanceMinor(sms.body);
    final evidence = ParseEvidence(
      institutionKnown: true,
      explicitDirection: direction.explicit,
      hasReference: reference != null,
      hasBalance: balanceMinor != null,
      specificCategory: isSpecificCategory(category),
      hasCounterparty: extractMerchant(sms.body, isExpense: isExpense) != null,
    );

    return ParsedSmsTransaction(
      detectedAmountMinor: (amountMajor * 100).round() * (isExpense ? -1 : 1),
      confidence: scoreConfidence(evidence),
      categoryHint: category,
      description: sms.body,
      institution: institution,
      reference: reference,
      balanceMinor: balanceMinor,
      accountNumberHint: extractAccountHint(sms.body),
      evidence: evidence,
    );
  }
}

class CbeSmsParserTemplate extends _InstitutionTemplate {
  const CbeSmsParserTemplate() : super(EthiopianInstitution.cbe);

  /// CBE receipts itemize fees and state a "total of ETB X" — the total is
  /// what actually left the account, so it wins over the headline amount.
  @override
  double? amountFor(String body, {required DirectionEvidence direction}) {
    return _extractCbeTransactionAmountMajor(
      body,
      isExpense: direction.isExpense,
    );
  }

  @override
  String? referenceFor(String body) => _extractCbeReference(body);
}

class AwashSmsParserTemplate extends _InstitutionTemplate {
  const AwashSmsParserTemplate() : super(EthiopianInstitution.awash);
}

class TelebirrSmsParserTemplate extends _InstitutionTemplate {
  const TelebirrSmsParserTemplate() : super(EthiopianInstitution.telebirr);
}

class BoaSmsParserTemplate extends _InstitutionTemplate {
  const BoaSmsParserTemplate() : super(EthiopianInstitution.boa);
}

class HibretSmsParserTemplate extends _InstitutionTemplate {
  const HibretSmsParserTemplate() : super(EthiopianInstitution.hibret);
}

class DashenSmsParserTemplate extends _InstitutionTemplate {
  const DashenSmsParserTemplate() : super(EthiopianInstitution.dashen);
}

/// Any other registered bank or wallet (Wegagen, NIB, M-PESA, ...). Uses the
/// shared extraction; the institution comes from the sender ID. Listed after
/// the institution-specific templates so those keep precedence.
class KnownInstitutionParserTemplate extends _InstitutionTemplate {
  const KnownInstitutionParserTemplate() : super(EthiopianInstitution.unknown);

  @override
  bool canParse(SmsMessage sms) => isFinancialSender(sms.sender);

  @override
  ParsedSmsTransaction? parse(SmsMessage sms) {
    return super
        .parse(sms)
        ?.copyWith(institution: institutionForSender(sms.sender));
  }
}

/// The production template order. Tests use this too, so the corpus always
/// exercises exactly what ships.
SmsParserEngine buildDefaultSmsParserEngine() {
  return SmsParserEngine(
    const [
      CbeSmsParserTemplate(),
      AwashSmsParserTemplate(),
      TelebirrSmsParserTemplate(),
      BoaSmsParserTemplate(),
      HibretSmsParserTemplate(),
      DashenSmsParserTemplate(),
      KnownInstitutionParserTemplate(),
      GenericAmountParserTemplate(),
    ],
  );
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

// Hibret writes outgoing amounts signed ("ETB -10027.6"); the sign is noise
// — direction comes from the wording.
final _amountWithCurrency = RegExp(
  '(?:etb|birr|ብር)\\s*-?\\s*$_amountCapturePattern',
  caseSensitive: false,
);
final _amountBeforeCurrency = RegExp(
  '$_amountCapturePattern\\s*(?:etb|birr|ብር)',
  caseSensitive: false,
);
final _balanceRegex = RegExp(
  '(?:bal(?:ance)?|available(?:\\s+balance)?|current\\s+balance|ቀሪ\\s*ሂሳብ|ቀሪ\\s*ሒሳብ)(?:\\s+is|[:\\s])*(?:etb|birr|ብር)?\\s*$_amountCapturePattern',
  caseSensitive: false,
);

double? _toMajor(String? raw) {
  if (raw == null) return null;
  final normalized = raw.replaceAll(',', '').replaceAll(' ', '');
  return double.tryParse(normalized);
}

/// Extracts the transaction amount, deliberately skipping the balance figure
/// when both appear in the same message.
///
/// When the only amount in the message IS the balance, this is a balance
/// inquiry rather than a transaction — unless [allowBalanceAsAmount] says an
/// explicit transaction phrase is present (a first deposit can legitimately
/// equal the new balance).
double? extractTransactionAmountMajor(
  String body, {
  bool allowBalanceAsAmount = false,
}) {
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
  if (candidates.isNotEmpty && allowBalanceAsAmount) return candidates.first;
  return null;
}

int? extractBalanceMinor(String body) {
  final major = _toMajor(_balanceRegex.firstMatch(body)?.group(1));
  if (major == null) return null;
  return (major * 100).round();
}

/// "Ref AXE1234", "Transaction number ABC123", "Your transaction number is
/// DF24JC2U3S". A real reference always carries a digit, so prose after the
/// keyword ("transaction with CBE") is never mistaken for one.
String? extractReference(String body) {
  final amharic = RegExp(
    r'መለያ\s*ቁጥር\s*((?=[a-z]*[0-9])[a-z0-9]{4,})',
    caseSensitive: false,
  ).firstMatch(body);
  if (amharic != null) return amharic.group(1);
  final match = RegExp(
    r'(?:ref(?:erence)?|trx|txn|txnid|transaction)(?:\s+(?:number|no|id))?[:\s#.-]*(?:is\s+)?((?=[a-z]*[0-9])[a-z0-9]{4,})',
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

// ---------------------------------------------------------------------------
// Direction
// ---------------------------------------------------------------------------

class DirectionEvidence {
  const DirectionEvidence({required this.isExpense, required this.explicit});

  final bool isExpense;

  /// True when an unambiguous phrase decided it; false when only a bare
  /// keyword (or nothing at all) was available.
  final bool explicit;
}

/// Phrases that can only describe money LEAVING the user's account.
/// Lower-case; matched by position, so the earliest phrase in a message wins.
const _explicitOutflowPhrases = [
  // Hibret: "ETB 10012 Outgoing Transfer ... is made from your account"
  'is made from your account',
  // CBE: "A debit transaction of ETB 100.0. has occurred on your account"
  'debit transaction of',
  // telebirr: "The request to withdraw ETB 2,000.00 ... is successfully completed"
  'request to withdraw',
  // Hibret: "your Mobile Topup transaction of 50 Birr ... has been successful"
  'topup transaction of',
  'has been debited',
  'have been debited',
  'is debited',
  'was debited',
  'account debited',
  'debited with',
  'debited by',
  'debited from',
  'debited etb',
  'debited birr',
  'you have paid',
  'you paid',
  'paid etb',
  'paid birr',
  'paid to',
  'you have transferred',
  'successfully transferred',
  'you have sent',
  'you sent',
  'sent etb',
  'sent birr',
  'you have recharged',
  'recharged etb',
  'recharged birr',
  'you have purchased',
  'purchase of',
  'withdrawn',
  'withdrawal',
  'cash out',
  'cash-out',
  'ወጪ',
  'ተከፍሏል',
  'ልከዋል',
  'ከፍለዋል',
  // M-PESA: "የ2,200.00 ብር ... ጥቅል ... ገዝተዋል" (you bought)
  'ገዝተዋል',
];

/// Phrases that can only describe money ARRIVING in the user's account.
const _explicitInflowPhrases = [
  // Hibret: "ETB 300 Mobile Funds Transfer is made to your account"
  'is made to your account',
  'credit transaction of',
  'has been credited',
  'have been credited',
  'is credited',
  'was credited',
  'account credited',
  'credited with',
  'credited by',
  'credited etb',
  'credited birr',
  'credited to your',
  'you have received',
  'you received',
  'received etb',
  'received birr',
  'received from',
  'sent you',
  'sent to you',
  'transferred to your',
  'deposited to your',
  'deposited into your',
  'deposit to your',
  'paid to you',
  'paid into your',
  'cash in',
  'cash-in',
  'refund',
  'reversal',
  'reversed',
  'ገቢ',
  'ተቀብለዋል',
];

/// Bare keywords used only when no explicit phrase is present.
const _weakExpenseCues = [
  'debited',
  'debit',
  'paid',
  'payment',
  'purchase',
  'withdraw',
  'sent',
  'transferred',
  'transfer',
];

const _weakIncomeCues = [
  // "ተመላሽ" (refund/cashback) appears in far more promotions than refunds.
  'ተመላሽ',
  'credited',
  'credit',
  'received',
  'deposit',
  'salary',
];

int? _earliestIndex(String lowered, List<String> cues) {
  int? best;
  for (final cue in cues) {
    final index = lowered.indexOf(cue);
    if (index >= 0 && (best == null || index < best)) best = index;
  }
  return best;
}

/// Direction detection: the EARLIEST cue in the message wins.
///
/// Ethiopian bank/wallet SMS lead with the primary action ("Your account has
/// been debited…", "You have received…") and often mention the counterparty's
/// side later ("…and credited to the beneficiary", "…Abebe has received the
/// amount"). Whichever side is mentioned first is whose transaction this is.
///
/// Explicit phrases are consulted first and make the result [explicit];
/// bare keywords are a fallback and leave the parse in the review queue.
/// With no cue at all the message is treated as an expense (the safer
/// default for a spending tracker) — also non-explicit.
DirectionEvidence detectDirection(String lowered) {
  final outAt = _earliestIndex(lowered, _explicitOutflowPhrases);
  final inAt = _earliestIndex(lowered, _explicitInflowPhrases);
  if (outAt != null || inAt != null) {
    if (inAt == null) {
      return const DirectionEvidence(isExpense: true, explicit: true);
    }
    if (outAt == null) {
      return const DirectionEvidence(isExpense: false, explicit: true);
    }
    // Same position means an inflow phrase extends an outflow one ("paid to"
    // vs "paid to your") — the longer, more specific inflow phrase wins.
    return DirectionEvidence(isExpense: outAt < inAt, explicit: true);
  }

  final weakOutAt = _earliestIndex(lowered, _weakExpenseCues);
  final weakInAt = _earliestIndex(lowered, _weakIncomeCues);
  if (weakInAt == null) {
    return const DirectionEvidence(isExpense: true, explicit: false);
  }
  if (weakOutAt == null) {
    return const DirectionEvidence(isExpense: false, explicit: false);
  }
  return DirectionEvidence(isExpense: weakOutAt < weakInAt, explicit: false);
}

/// Convenience for callers that only need the sign.
bool isExpenseMessage(String lowered) => detectDirection(lowered).isExpense;

// ---------------------------------------------------------------------------
// Category
// ---------------------------------------------------------------------------

bool _isAirtimeOrPackageMessage(String lowered) {
  const tokens = [
    'airtime',
    'recharge',
    'recharged',
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
  const Map<String, List<String>> priorityRules = {
    'salary': ['salary', 'payroll', 'wage', 'ደመወዝ'],
    'savings': ['saving', 'deposit to', 'fixed', 'equb', 'iqub', 'እቁብ', 'ቁጠባ'],
    'airtime': [
      'airtime',
      'recharge',
      'recharged',
      'top up',
      'topup',
      'bundle',
      'data package',
      'internet package',
      'package',
      'minute',
      'የአየር ሰዓት',
    ],
  };
  const Map<String, List<String>> rules = {
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

  String? matchRules(Map<String, List<String>> ruleSet) {
    for (final entry in ruleSet.entries) {
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
    return null;
  }

  final priority = matchRules(priorityRules);
  if (priority != null) return priority;

  // A person-to-person / account-to-account transfer outranks incidental
  // fee wording: CBE transfer receipts always list "service charge" and
  // "VAT", but the transaction is the transfer, not the fees.
  if (_containsKeyword(body, 'transferred') ||
      _containsKeyword(body, 'transfer')) {
    return isExpense ? 'transfer_out' : 'transfer_in';
  }
  // Cash withdrawals itemize a "service fee" too; the money moved is cash.
  if (isExpense && body.contains('withdraw')) return 'transfer_out';

  final matched = matchRules(rules);
  if (matched != null) return matched;

  if (!isExpense) {
    if (_containsKeyword(body, 'salary') || _containsKeyword(body, 'payroll')) {
      return 'salary';
    }
    if (_containsKeyword(body, 'transfer') ||
        _containsKeyword(body, 'received')) {
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
const _amountPhrase = r'(?:etb|birr|ብር)?\s*[\d,.]*\s*(?:etb|birr|ብር)?\s*';

final List<RegExp> _expenseMerchantPatterns = [
  // "paid ETB 120.00 to Shoa Supermarket via telebirr" /
  // "paid 320.00 birr to GebeyaGo Delivery via app"
  RegExp(
      'paid\\s+${_amountPhrase}to\\s+([^.,\\n]{2,48}?)\\s+(?:via|through|on|using|ref)',
      caseSensitive: false),
  // "transferred to W/ro Almaz — house rent"
  RegExp(r'transferred\s+to\s+([^.,\n—-]{2,48})', caseSensitive: false),
  // "transferred ETB 500.00 to Abebe Kebede (2519****) on 09/07/2026"
  RegExp(
      'transferred\\s+${_amountPhrase}to\\s+([^.,\\n(]{2,48}?)\\s*(?:\\(|via|through|on|ref)',
      caseSensitive: false),
  // "You have sent ETB 1,500.00 to Emebet K. via telebirr"
  RegExp(
      'sent\\s+${_amountPhrase}to\\s+([^.,\\n]{2,48}?)\\s+(?:via|through|on|ref)',
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
      // "Mekuria Solomon(2519****4846)" — the masked phone in parentheses is
      // not part of the name.
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
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

final _feeItemPattern = RegExp(
  '(?:service\\s+charge|vat\\s*\\(?[0-9%]*\\)?|commission|'
  'disaster\\s+(?:recovery|fund)\\s*\\(?[0-9%]*\\)?|stamp\\s+duty|'
  'excise)\\s*(?:of)?\\s*(?:etb|birr|ብር)?\\s*$_amountCapturePattern',
  caseSensitive: false,
);

/// Sums the fee components a bank itemizes inside a receipt ("Service charge
/// of ETB 1.00 and VAT(15%) of ETB0.15 ..."). Returns 0 when none.
int extractItemizedFeesMinor(String body) {
  var total = 0;
  for (final match in _feeItemPattern.allMatches(body)) {
    final major = _toMajor(match.group(1));
    if (major != null) total += (major * 100).round();
  }
  return total;
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

// ---------------------------------------------------------------------------
// Non-ledger message filters
// ---------------------------------------------------------------------------

bool _looksTransactionalMessage(String body) {
  if (_shouldIgnoreNonLedgerMessage(body)) return false;
  if (_isAirtimeOrPackageMessage(body)) return true;
  // Note: a bare "balance" is deliberately NOT an indicator — a balance
  // inquiry reply mentions money without any money moving.
  const indicators = [
    'debited',
    'debit',
    'credited',
    'credit',
    'paid',
    'payment',
    'purchase',
    'withdraw',
    'withdrawn',
    'withdrawal',
    'sent',
    'transfer',
    'transferred',
    'received',
    'deposit',
    'deposited',
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

/// A declined or failed attempt moves no money and must not reach the ledger.
bool _isFailedTransactionMessage(String body) {
  const blockers = [
    'unsuccessful',
    'not successful',
    'failed',
    'declined',
    'rejected',
    'insufficient balance',
    'insufficient funds',
    'could not be processed',
    'cannot be processed',
    'has been cancelled',
    'has been canceled',
    'is incorrect',
    'is cancelled',
    'is canceled',
    'አልተሳካም',
    'በቂ ሒሳብ የለዎትም',
    'በቂ ሂሳብ የለዎትም',
  ];
  for (final blocker in blockers) {
    if (_containsKeyword(body, blocker)) return true;
  }
  return false;
}

bool _shouldIgnoreNonLedgerMessage(String body) {
  return _isLikelyOtpOrVerification(body) ||
      _isAirtimeReceivedMirrorMessage(body) ||
      _isFailedTransactionMessage(body) ||
      _isBonusMessage(body) ||
      _isRechargeMirrorMessage(body);
}

/// Airtime/package bonuses ("You have got ETB 67.65 bonus") are not cash.
bool _isBonusMessage(String body) => _containsKeyword(body, 'bonus');

/// Hibret sends a second "X have recharged your prepaid mobile" notice for
/// the same top-up its "Mobile Topup transaction" receipt already booked.
bool _isRechargeMirrorMessage(String body) =>
    body.contains('recharged your prepaid');

/// Marketing words, English and Amharic. Banks and telcos send far more
/// promotions than receipts, and promotions quote birr amounts ("up to ብር
/// 5000", "win 250,000 ብር") next to words like ተመላሽ (cashback).
const _promotionCues = [
  'lottery',
  'prize',
  'cashback',
  'cash back',
  'discount',
  'spin the wheel',
  'offer',
  'ሽልማት', // prize
  'ሸለሙ', // be awarded
  'ያሸንፉ', // win
  'ዕጣ', // draw
  'ዕድል', // luck / lucky draw
  'ሎተሪ', // lottery
  'ይበደሩ', // borrow
  'ብድር', // loan
  'ቅናሽ', // discount
  'ስጦታ', // gift
  'ያገኛሉ', // "you will get"
  'ይመዝገቡ', // register
  'ይላኩ', // "send (A to 9632)"
  '%',
];

bool _hasLink(String lowered) =>
    lowered.contains('http') ||
    lowered.contains('www.') ||
    lowered.contains('bit.ly') ||
    lowered.contains('t.me/');

/// A receipt states facts about an account: a balance, a reference, an
/// account number — or at least an unambiguous "you paid / you received".
/// Promotions and notices have none of these, so they are dropped instead
/// of filling the review queue (or worse, being booked as income).
bool _looksLikeRealTransaction(String body, DirectionEvidence direction) {
  final lowered = body.toLowerCase();
  final hasBalance = _balanceRegex.hasMatch(body);
  final promotional = _hasLink(lowered) ||
      _containsKeyword(lowered, 'win') ||
      _containsKeyword(lowered, 'loan') ||
      _promotionCues.any(lowered.contains);
  // Real receipts with links or "VAT(15%)" always state the new balance.
  if (promotional && !hasBalance) return false;
  if (direction.explicit) return true;
  return hasBalance ||
      extractReference(body) != null ||
      extractAccountHint(body) != null;
}

// ---------------------------------------------------------------------------
// CBE specifics
// ---------------------------------------------------------------------------

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
