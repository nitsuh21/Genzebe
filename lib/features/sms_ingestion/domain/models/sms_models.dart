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
  });

  final int detectedAmountMinor;
  final double confidence;
  final String categoryHint;
  final String description;
  final EthiopianInstitution institution;
  final String? reference;
  final int? balanceMinor;
  final String? accountNumberHint;
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
