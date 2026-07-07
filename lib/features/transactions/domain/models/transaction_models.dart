import 'package:genzebet/features/transactions/domain/models/money.dart';

enum TransactionType { income, expense, transferIn, transferOut }

enum TransactionSource { sms, manual, sync }

enum TransactionReviewStatus { autoAccepted, pendingReview, rejected }

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAt,
    this.institutionCode,
    this.maskedAccount,
  });

  final String id;
  final String name;
  final String kind;
  final DateTime createdAt;
  final String? institutionCode;
  final String? maskedAccount;
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.isSystem,
  });

  final String id;
  final String name;
  final String iconKey;
  final bool isSystem;
}

class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.occurredAt,
    required this.categoryId,
    required this.source,
    this.smsSender,
    this.smsSnippet,
    this.note,
    this.parserConfidence,
    this.reviewStatus = TransactionReviewStatus.autoAccepted,
    this.statementBalanceMinor,
  });

  final String id;
  final String accountId;
  final TransactionType type;
  final Money amount;
  final DateTime occurredAt;
  final String categoryId;
  final TransactionSource source;
  final String? smsSender;
  final String? smsSnippet;
  final String? note;
  final double? parserConfidence;
  final TransactionReviewStatus reviewStatus;

  /// Remaining account balance reported in the source SMS (statement balance),
  /// when the message included one. Used to derive real account balances.
  final int? statementBalanceMinor;

  TransactionRecord copyWith({
    String? id,
    String? accountId,
    TransactionType? type,
    Money? amount,
    DateTime? occurredAt,
    String? categoryId,
    TransactionSource? source,
    String? smsSender,
    String? smsSnippet,
    String? note,
    double? parserConfidence,
    TransactionReviewStatus? reviewStatus,
    int? statementBalanceMinor,
  }) {
    return TransactionRecord(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      occurredAt: occurredAt ?? this.occurredAt,
      categoryId: categoryId ?? this.categoryId,
      source: source ?? this.source,
      smsSender: smsSender ?? this.smsSender,
      smsSnippet: smsSnippet ?? this.smsSnippet,
      note: note ?? this.note,
      parserConfidence: parserConfidence ?? this.parserConfidence,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      statementBalanceMinor:
          statementBalanceMinor ?? this.statementBalanceMinor,
    );
  }
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.transactionId,
    required this.accountId,
    required this.delta,
    required this.createdAt,
    required this.source,
  });

  final String id;
  final String transactionId;
  final String accountId;
  final Money delta;
  final DateTime createdAt;
  final TransactionSource source;
}
