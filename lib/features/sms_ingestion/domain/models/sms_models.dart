class SmsMessage {
  const SmsMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
  });

  final String id;
  final String sender;
  final String body;
  final DateTime receivedAt;
}

enum SmsIngestionStatus {
  pending,
  parsed,
  pendingReview,
  rejected,
  failed,
  duplicate,
}

enum EthiopianInstitution {
  cbe,
  awash,
  telebirr,
  boa,
  hibret,
  dashen,
  unknown,
}

/// The structural facts a parse was able to establish. Confidence is derived
/// from this — never guessed — so a transaction lands in the review queue
/// exactly when one of these is missing.
class ParseEvidence {
  const ParseEvidence({
    required this.institutionKnown,
    required this.explicitDirection,
    required this.hasReference,
    required this.hasBalance,
    required this.specificCategory,
    required this.hasCounterparty,
  });

  /// The sender is a recognised bank/wallet (template or user mapping).
  final bool institutionKnown;

  /// An unambiguous phrase ("has been debited with", "you have received")
  /// decided the direction, not a bare keyword guess.
  final bool explicitDirection;

  final bool hasReference;
  final bool hasBalance;

  /// Category came from a keyword/merchant rule rather than the bare
  /// income/expense fallback.
  final bool specificCategory;

  final bool hasCounterparty;

  ParseEvidence copyWith({
    bool? institutionKnown,
    bool? explicitDirection,
    bool? hasReference,
    bool? hasBalance,
    bool? specificCategory,
    bool? hasCounterparty,
  }) {
    return ParseEvidence(
      institutionKnown: institutionKnown ?? this.institutionKnown,
      explicitDirection: explicitDirection ?? this.explicitDirection,
      hasReference: hasReference ?? this.hasReference,
      hasBalance: hasBalance ?? this.hasBalance,
      specificCategory: specificCategory ?? this.specificCategory,
      hasCounterparty: hasCounterparty ?? this.hasCounterparty,
    );
  }

  /// Human-readable reasons this parse needs a second look (empty when the
  /// evidence is complete). Shown on review-queue tiles.
  List<String> get reviewReasons {
    return [
      if (!institutionKnown) 'Unknown sender',
      if (!explicitDirection) 'Income/expense unclear',
      if (!specificCategory) 'No category match',
    ];
  }
}

class ParsedSmsTransaction {
  const ParsedSmsTransaction({
    required this.detectedAmountMinor,
    required this.confidence,
    required this.categoryHint,
    required this.description,
    required this.institution,
    this.reference,
    this.balanceMinor,
    this.accountNumberHint,
    this.evidence,
  });

  final int detectedAmountMinor;
  final double confidence;
  final String categoryHint;
  final String description;
  final EthiopianInstitution institution;
  final String? reference;
  final int? balanceMinor;
  final String? accountNumberHint;

  /// Null only for legacy/synthetic instances built outside the parser.
  final ParseEvidence? evidence;

  ParsedSmsTransaction copyWith({
    double? confidence,
    String? categoryHint,
    EthiopianInstitution? institution,
    ParseEvidence? evidence,
  }) {
    return ParsedSmsTransaction(
      detectedAmountMinor: detectedAmountMinor,
      confidence: confidence ?? this.confidence,
      categoryHint: categoryHint ?? this.categoryHint,
      description: description,
      institution: institution ?? this.institution,
      reference: reference,
      balanceMinor: balanceMinor,
      accountNumberHint: accountNumberHint,
      evidence: evidence ?? this.evidence,
    );
  }
}

class SmsReviewItem {
  const SmsReviewItem({
    required this.id,
    required this.smsMessage,
    required this.parsed,
    required this.status,
  });

  final String id;
  final SmsMessage smsMessage;
  final ParsedSmsTransaction parsed;
  final String status;
}

class StoredSmsMessage {
  const StoredSmsMessage({
    required this.sms,
    required this.messageHash,
    required this.status,
    this.parsedTransactionId,
    this.failureReason,
    this.ingestedAt,
  });

  final SmsMessage sms;
  final String messageHash;
  final SmsIngestionStatus status;
  final String? parsedTransactionId;
  final String? failureReason;
  final DateTime? ingestedAt;

  StoredSmsMessage copyWith({
    SmsMessage? sms,
    String? messageHash,
    SmsIngestionStatus? status,
    String? parsedTransactionId,
    String? failureReason,
    DateTime? ingestedAt,
  }) {
    return StoredSmsMessage(
      sms: sms ?? this.sms,
      messageHash: messageHash ?? this.messageHash,
      status: status ?? this.status,
      parsedTransactionId: parsedTransactionId ?? this.parsedTransactionId,
      failureReason: failureReason ?? this.failureReason,
      ingestedAt: ingestedAt ?? this.ingestedAt,
    );
  }
}
