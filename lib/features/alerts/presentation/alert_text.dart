import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/features/alerts/domain/money_alert.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';
import 'package:genzeb/features/transactions/domain/models/categories.dart';

String alertAmountLabel(MoneyAlert alert, {required bool hidden}) {
  final sign = alert.isIncome ? '+' : '−';
  return hidden
      ? '$sign ETB ••••'
      : '$sign${formatMinorEtb(alert.amountMinor)}';
}

/// Who the money came from or went to, falling back to the bank/wallet.
String alertParty(MoneyAlert alert) {
  final party = alert.counterparty?.trim();
  if (party != null && party.isNotEmpty) return party;
  return institutionInfoForCode(alert.institutionCode).shortName;
}

/// Headline: "Elias Y. · +ETB 1,000.00".
String alertHeadline(MoneyAlert alert, {required bool hidden}) =>
    '${alertParty(alert)} · ${alertAmountLabel(alert, hidden: hidden)}';

/// "Money in · Transfer in · CBE" — direction, transaction type, account.
String alertDetail(
  MoneyAlert alert, {
  required String moneyIn,
  required String moneyOut,
}) {
  final direction = alert.isIncome ? moneyIn : moneyOut;
  final institution = institutionInfoForCode(alert.institutionCode).shortName;
  final categoryId = alert.categoryId;
  final type = categoryId == null ? null : kCategoryCatalog[categoryId]?.label;
  // "Money in · Income" says nothing twice; skip generic buckets.
  final showType =
      type != null && categoryId != 'income' && categoryId != 'expense';
  return [direction, if (showType) type, institution].join(' · ');
}
