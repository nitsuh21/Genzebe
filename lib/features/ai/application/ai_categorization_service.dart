import 'dart:convert';

import 'package:genzeb/core/logging/app_logger.dart';
import 'package:genzeb/features/ai/application/ai_assistant_service.dart';
import 'package:genzeb/features/ai/data/gemini_client.dart';
import 'package:genzeb/features/reports/application/report_service.dart'
    show isInflowType;
import 'package:genzeb/features/sms_ingestion/domain/models/sms_models.dart';
import 'package:genzeb/features/sms_ingestion/domain/repositories/category_rule_repository.dart';
import 'package:genzeb/features/sms_ingestion/domain/services/sms_parser.dart';
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:genzeb/features/transactions/domain/models/money.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/domain/repositories/ledger_repository.dart';

/// A proposed correction for one transaction. AI may only change the
/// category, the direction (income vs expense), and — for transactions
/// stranded in the generic wallet — the institution account. Never amounts,
/// dates, or the existence of a transaction.
class AiCategorySuggestion {
  const AiCategorySuggestion({
    required this.transactionId,
    required this.smsSnippet,
    required this.amountMinor,
    required this.currentCategoryId,
    required this.suggestedCategoryId,
    required this.currentType,
    required this.suggestedType,
    required this.reason,
    this.currentAccountId,
    this.suggestedInstitution,
  });

  final String transactionId;
  final String smsSnippet;
  final int amountMinor;
  final String currentCategoryId;
  final String suggestedCategoryId;
  final TransactionType currentType;
  final TransactionType suggestedType;
  final String reason;
  final String? currentAccountId;

  /// Institution code (cbe, telebirr, ...) for transactions currently in the
  /// generic wallet; applied only when the current account is the fallback.
  final String? suggestedInstitution;

  bool get changesCategory => suggestedCategoryId != currentCategoryId;

  bool get changesDirection =>
      isInflowType(suggestedType) != isInflowType(currentType);

  bool get changesAccount =>
      suggestedInstitution != null && currentAccountId == 'main-wallet';

  bool get isMeaningful => changesCategory || changesDirection || changesAccount;
}

/// Reviews SMS-sourced transactions with Gemini and suggests category /
/// direction / account fixes. Deterministic parsing stays the source of
/// truth for amounts; user-taught rules always outrank the AI.
class AiCategorizationService {
  AiCategorizationService({
    required GeminiClient geminiClient,
    required AiAssistantService assistantService,
    required LedgerRepository ledgerRepository,
    required CategoryRuleRepository categoryRuleRepository,
  })  : _gemini = geminiClient,
        _assistant = assistantService,
        _ledger = ledgerRepository,
        _categoryRules = categoryRuleRepository;

  final GeminiClient _gemini;
  final AiAssistantService _assistant;
  final LedgerRepository _ledger;
  final CategoryRuleRepository _categoryRules;

  static const _chunkSize = 40;
  static const _maxChunks = 3;

  Future<bool> isAvailable() => _assistant.isAvailable();

  /// Returns suggested corrections for SMS transactions (optionally limited
  /// to [onlyTransactionIds]), most recent first. Transactions whose merchant
  /// the user has already taught a rule for are left alone — the user is the
  /// highest authority, not the AI.
  Future<List<AiCategorySuggestion>> suggestCorrections({
    Set<String>? onlyTransactionIds,
  }) async {
    final apiKey = await _assistant.getApiKey();
    if (apiKey == null) {
      throw GeminiException('Add a Gemini API key in Profile to use AI.');
    }

    final all = await _ledger.getTransactions();
    final candidates = <TransactionRecord>[];
    for (final tx in all) {
      if (tx.source != TransactionSource.sms) continue;
      if (tx.reviewStatus == TransactionReviewStatus.rejected) continue;
      if (tx.smsSnippet?.trim().isNotEmpty != true) continue;
      if (onlyTransactionIds != null && !onlyTransactionIds.contains(tx.id)) {
        continue;
      }
      if (await _hasUserRule(tx)) continue;
      candidates.add(tx);
    }
    if (candidates.isEmpty) return const [];

    final byId = {for (final tx in candidates) tx.id: tx};
    final suggestions = <AiCategorySuggestion>[];
    for (var i = 0;
        i < candidates.length && i ~/ _chunkSize < _maxChunks;
        i += _chunkSize) {
      final chunk = candidates.skip(i).take(_chunkSize).toList();
      final raw = await _gemini.generate(
        apiKey: apiKey,
        systemInstruction: _systemPrompt(),
        history: [GeminiChatTurn(fromUser: true, text: _rowsPayload(chunk))],
      );
      suggestions.addAll(_parseSuggestions(raw, byId));
    }
    return suggestions.where((s) => s.isMeaningful).toList(growable: false);
  }

  /// Applies accepted suggestions. Direction changes rewrite the ledger
  /// entry; account moves re-home the transaction into the institution's
  /// account. Returns how many were applied.
  Future<int> applySuggestions(List<AiCategorySuggestion> accepted) async {
    var applied = 0;
    for (final suggestion in accepted) {
      final tx = await _ledger.getTransactionById(suggestion.transactionId);
      if (tx == null) continue;

      var accountId = tx.accountId;
      if (suggestion.suggestedInstitution != null &&
          tx.accountId == 'main-wallet') {
        final institution = EthiopianInstitution.values.firstWhere(
          (value) => value.name == suggestion.suggestedInstitution,
          orElse: () => EthiopianInstitution.unknown,
        );
        if (institution != EthiopianInstitution.unknown) {
          accountId = '${institution.name}-main';
          await _ledger.upsertAccount(
            Account(
              id: accountId,
              name: _institutionDisplayName(institution),
              kind: 'bank-account',
              createdAt: DateTime.now(),
              institutionCode: institution.name,
            ),
          );
        }
      }

      final updated = tx.copyWith(
        categoryId: suggestion.suggestedCategoryId,
        type: suggestion.suggestedType,
        accountId: accountId,
      );
      final hadLedgerEntry =
          await _ledger.hasLedgerEntryForTransaction(tx.id);
      // deleteTransaction clears the stale ledger entry (whose sign/account
      // encode the old state); then the transaction is rewritten in place.
      await _ledger.deleteTransaction(tx.id);
      await _ledger.saveTransaction(updated);
      if (hadLedgerEntry) {
        await _ledger.appendLedgerEntry(
          LedgerEntry(
            id: 'ledger-${updated.id}',
            transactionId: updated.id,
            accountId: updated.accountId,
            delta: Money(
              minorUnits: isInflowType(updated.type)
                  ? updated.amount.minorUnits
                  : -updated.amount.minorUnits,
              currency: updated.amount.currency,
            ),
            createdAt: DateTime.now(),
            source: updated.source,
          ),
        );
      }
      applied += 1;
    }
    AppLogger.info('ai.recat', 'Applied $applied AI corrections');
    return applied;
  }

  Future<bool> _hasUserRule(TransactionRecord tx) async {
    final snippet = tx.smsSnippet;
    if (snippet == null) return false;
    final merchant = extractMerchant(
      snippet,
      isExpense: tx.type == TransactionType.expense ||
          tx.type == TransactionType.transferOut,
    );
    if (merchant == null) return false;
    return await _categoryRules
            .categoryForMerchant(normalizeMerchant(merchant)) !=
        null;
  }

  String _systemPrompt() {
    final categoryIds = kCategoryCatalog.keys.join(', ');
    return 'You audit transactions parsed from Ethiopian bank/Telebirr SMS. '
        'For each numbered row decide the best category, money direction, '
        'and (when obvious from the sender or text) the institution. '
        'Valid categories: $categoryIds. '
        'Valid institutions: cbe, awash, telebirr, boa, hibret, dashen. '
        'Direction rules: "in" means money arrived to the user (credited, '
        'received, salary, refund, ገቢ); "out" means money left (debited, '
        'paid, sent, purchase, ወጪ). The message describes the USER\'s side '
        'of the transaction — a note that the recipient "has received" the '
        'money still means "out" for the user. Amharic may appear. '
        'Reply with ONLY a JSON array, no markdown fences, one object per '
        'row that needs a correction (omit rows that are already right): '
        '[{"id": "<row id>", "category": "<category id>", '
        '"direction": "in"|"out", "institution": "<code or omit>", '
        '"reason": "<max 10 words>"}]. '
        'If everything is correct, reply [].';
  }

  String _rowsPayload(List<TransactionRecord> chunk) {
    final buffer = StringBuffer('Rows to audit:\n');
    for (final tx in chunk) {
      final direction = isInflowType(tx.type) ? 'in' : 'out';
      final snippet = _truncate(tx.smsSnippet ?? '', 200);
      buffer.writeln(
        'id=${tx.id} | current_category=${tx.categoryId} | '
        'current_direction=$direction | account=${tx.accountId} | '
        'sender=${tx.smsSender ?? '?'} | sms="$snippet"',
      );
    }
    return buffer.toString();
  }

  List<AiCategorySuggestion> _parseSuggestions(
    String raw,
    Map<String, TransactionRecord> byId,
  ) {
    final cleaned = raw
        .replaceAll(RegExp(r'^```(json)?', multiLine: true), '')
        .replaceAll('```', '')
        .trim();
    dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (error) {
      AppLogger.info('ai.recat', 'Unparseable AI response: $error');
      return const [];
    }
    if (decoded is! List) return const [];

    const validInstitutions = {
      'cbe',
      'awash',
      'telebirr',
      'boa',
      'hibret',
      'dashen',
    };
    final results = <AiCategorySuggestion>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final tx = byId[item['id']];
      if (tx == null) continue;
      final category = item['category'] as String?;
      final direction = item['direction'] as String?;
      if (category == null || !kCategoryCatalog.containsKey(category)) {
        continue;
      }
      if (direction != 'in' && direction != 'out') continue;
      final institution = item['institution'] as String?;
      results.add(
        AiCategorySuggestion(
          transactionId: tx.id,
          smsSnippet: tx.smsSnippet ?? '',
          amountMinor: tx.amount.minorUnits,
          currentCategoryId: tx.categoryId,
          suggestedCategoryId: category,
          currentType: tx.type,
          suggestedType: _typeFor(category: category, inflow: direction == 'in'),
          reason: (item['reason'] as String?)?.trim() ?? '',
          currentAccountId: tx.accountId,
          suggestedInstitution:
              validInstitutions.contains(institution) ? institution : null,
        ),
      );
    }
    return results;
  }

  TransactionType _typeFor({required String category, required bool inflow}) {
    if (inflow) {
      return category == 'transfer_in'
          ? TransactionType.transferIn
          : TransactionType.income;
    }
    return category == 'transfer_out'
        ? TransactionType.transferOut
        : TransactionType.expense;
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

  String _truncate(String value, int max) {
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.length <= max
        ? collapsed
        : '${collapsed.substring(0, max)}…';
  }
}
