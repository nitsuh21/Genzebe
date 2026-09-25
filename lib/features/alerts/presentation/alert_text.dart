import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/features/alerts/domain/money_alert.dart';
import 'package:genzeb/features/sms_ingestion/domain/models/institutions.dart';

String alertAmountLabel(MoneyAlert alert, {required bool hidden}) {
  final sign = alert.isIncome ? '+' : '−';
  return hidden
      ? '$sign ETB ••••'
      : '$sign${formatMinorEtb(alert.amountMinor)}';
}

/// "CBE · from Abebe Kebede" / "telebirr · to Shoa Supermarket"
String alertSubtitle(MoneyAlert alert) {
  final institution = institutionInfoForCode(alert.institutionCode).shortName;
  final party = alert.counterparty;
  if (party == null || party.isEmpty) return institution;
  return '$institution · ${alert.isIncome ? 'from' : 'to'} $party';
}
