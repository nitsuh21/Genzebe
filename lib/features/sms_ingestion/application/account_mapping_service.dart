import 'dart:convert';

import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/domain/repositories/ledger_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountMapping {
  const AccountMapping({
    required this.senderPattern,
    required this.accountId,
    required this.accountName,
    required this.institution,
  });

  final String senderPattern;
  final String accountId;
  final String accountName;
  final EthiopianInstitution institution;
}

class AccountMappingService {
  AccountMappingService(this._ledgerRepository);

  final LedgerRepository _ledgerRepository;
  static const _prefsKey = 'account_mappings_v1';
  final List<AccountMapping> _rules = [];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList(_prefsKey) ?? const [];
    _rules
      ..clear()
      ..addAll(
        rows
            .map((row) =>
                _decodeMapping(jsonDecode(row) as Map<String, dynamic>))
            .toList(growable: false),
      );
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = _rules
        .map((rule) => jsonEncode(_encodeMapping(rule)))
        .toList(growable: false);
    await prefs.setStringList(_prefsKey, rows);
  }

  Future<void> saveMapping(AccountMapping mapping) async {
    await _ensureLoaded();
    _rules.removeWhere(
      (rule) =>
          rule.senderPattern.toLowerCase() ==
          mapping.senderPattern.toLowerCase(),
    );
    _rules.add(mapping);
    await _ledgerRepository.upsertAccount(
      Account(
        id: mapping.accountId,
        name: mapping.accountName,
        kind: 'bank-account',
        createdAt: DateTime.now(),
        institutionCode: mapping.institution.name,
      ),
    );
    await _persist();
  }

  Future<void> deleteMapping(String senderPattern) async {
    await _ensureLoaded();
    _rules.removeWhere(
      (rule) =>
          rule.senderPattern.toLowerCase() == senderPattern.toLowerCase(),
    );
    await _persist();
  }

  Future<List<AccountMapping>> getMappings() async {
    await _ensureLoaded();
    return List<AccountMapping>.unmodifiable(_rules);
  }

  Future<String> resolveAccountId({
    required SmsMessage sms,
    required ParsedSmsTransaction parsed,
    String defaultAccountId = 'main-wallet',
  }) async {
    await _ensureLoaded();
    final sender = sms.sender;
    for (final rule in _rules) {
      if (_senderMatchesPattern(sender, rule.senderPattern)) {
        // The ledger repository is in-memory and resets each launch, while
        // mappings persist. Re-materialize the mapped account so its
        // institution code is always available for filters and balances.
        await _ledgerRepository.upsertAccount(
          Account(
            id: rule.accountId,
            name: rule.accountName,
            kind: 'bank-account',
            createdAt: DateTime.now(),
            institutionCode: rule.institution.name,
            maskedAccount: parsed.accountNumberHint,
          ),
        );
        return rule.accountId;
      }
    }

    final inferredAccountId = '${parsed.institution.name}-main';
    await _ledgerRepository.upsertAccount(
      Account(
        id: inferredAccountId,
        name: _institutionDisplayName(parsed.institution),
        kind: 'bank-account',
        createdAt: DateTime.now(),
        institutionCode: parsed.institution.name,
        maskedAccount: parsed.accountNumberHint,
      ),
    );
    return parsed.institution == EthiopianInstitution.unknown
        ? defaultAccountId
        : inferredAccountId;
  }

  String _institutionDisplayName(EthiopianInstitution institution) {
    switch (institution) {
      case EthiopianInstitution.cbe:
        return 'Commercial Bank of Ethiopia';
      case EthiopianInstitution.awash:
        return 'Awash Bank';
      case EthiopianInstitution.telebirr:
        return 'Telebirr Wallet';
      case EthiopianInstitution.boa:
        return 'Bank of Abyssinia';
      case EthiopianInstitution.hibret:
        return 'Hibret Bank';
      case EthiopianInstitution.dashen:
        return 'Dashen Bank';
      case EthiopianInstitution.unknown:
        return 'Main Wallet';
    }
  }

  Map<String, dynamic> _encodeMapping(AccountMapping mapping) {
    return {
      'senderPattern': mapping.senderPattern,
      'accountId': mapping.accountId,
      'accountName': mapping.accountName,
      'institution': mapping.institution.name,
    };
  }

  AccountMapping _decodeMapping(Map<String, dynamic> json) {
    final institutionName = (json['institution'] as String?) ?? 'unknown';
    final institution = EthiopianInstitution.values.firstWhere(
      (value) => value.name == institutionName,
      orElse: () => EthiopianInstitution.unknown,
    );
    return AccountMapping(
      senderPattern: (json['senderPattern'] as String?) ?? '',
      accountId: (json['accountId'] as String?) ?? 'main-wallet',
      accountName: (json['accountName'] as String?) ?? 'Main Wallet',
      institution: institution,
    );
  }

  bool _senderMatchesPattern(String sender, String pattern) {
    final lowerSender = sender.toLowerCase();
    final lowerPattern = pattern.toLowerCase();
    if (lowerSender.contains(lowerPattern)) return true;

    final normalizedSender = _normalizeSenderToken(lowerSender);
    final normalizedPattern = _normalizeSenderToken(lowerPattern);
    if (normalizedPattern.isEmpty) return false;
    return normalizedSender.contains(normalizedPattern);
  }

  String _normalizeSenderToken(String value) {
    return value.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
