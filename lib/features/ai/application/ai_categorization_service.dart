import 'dart:convert';

import 'package:genzeb/core/logging/app_logger.dart';
import 'package:genzeb/features/ai/application/ai_assistant_service.dart';
import 'package:genzeb/features/ai/data/gemini_client.dart';
import 'package:genzeb/features/reports/application/report_service.dart'
    show isInflowType;
import 'package:genzeb/features/transactions/domain/models/categories.dart';
import 'package:genzeb/features/transactions/domain/models/money.dart';
import 'package:genzeb/features/transactions/domain/models/transaction_models.dart';
import 'package:genzeb/features/transactions/domain/repositories/ledger_repository.dart';

/// A proposed correction for one transaction. AI may only change the
/// category and the direction (income vs expense) — never amounts, dates,
/// or the existence of a transaction.
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
  });

  final String transactionId;
  final String smsSnippet;
  final int amountMinor;
  final String currentCategoryId;
  final String suggestedCategoryId;
  final TransactionType currentType;
  final TransactionType suggestedType;
  final String reason;

  bool get changesCategory => suggestedCategoryId != currentCategoryId;

  bool get changesDirection =>
      isInflowType(suggestedType) != isInflowType(currentType);

  bool get isMeaningful => changesCategory || changesDirection;
}

/// Reviews SMS-sourced transactions with Gemini and suggests category /
/// direction fixes. Deterministic parsing stays the source of truth; this is
/// a second opinion the user applies explicitly.
class AiCategorizationService {
  AiCategorizationService({
    required GeminiClient geminiClient,
    required AiAssistantService assistantService,
    required LedgerRepository ledgerRepository,
  })  : _gemini = geminiClient,
        _assistant = assistantService,
        _ledger = ledgerRepository;

  final GeminiClient _gemini;
  final AiAssistantService _assistant;
  final LedgerRepository _ledger;

  static const _chunkSize = 40;
  static const _maxChunks = 3;

  Future<bool> isAvailable() => _assistant.isAvailable();

  /// Returns suggested corrections for recent SMS transactions,
  /// most recent first. Empty when AI finds nothing to fix.
  Future<List<AiCategorySuggestion>> suggestCorrections() async {
    final apiKey = await _assistant.getApiKey();
    if (apiKey == null) {
      throw GeminiException('Add a Gemini API key in Profile to use AI.');
    }

    final all = await _ledger.getTransactions();
    final candidates = all
        .where((tx) =>
            tx.source == TransactionSource.sms &&
            tx.reviewStatus != TransactionReviewStatus.rejected &&
            (tx.smsSnippet?.trim().isNotEmpty ?? false))
        .toList(growable: false);
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

  /// Applies accepted suggestions. Direction changes also rewrite the ledger
  /// entry so account balances stay correct. Returns how many were applied.
  Future<int> applySuggestions(List<AiCategorySuggestion> accepted) async {
    var applied = 0;
    for (final suggestion in accepted) {
      final tx = await _ledger.getTransactionById(suggestion.transactionId);
      if (tx == null) continue;

      final updated = tx.copyWith(
        categoryId: suggestion.suggestedCategoryId,
        type: suggestion.suggestedType,
      );
      final hadLedgerEntry =
          await _ledger.hasLedgerEntryForTransaction(tx.id);
      // deleteTransaction clears the stale ledger entry (whose sign encodes
      // the old direction); then the transaction is rewritten in place.
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
    AppLogger.info('ai.recat', 'Applied $applied AI category corrections');
    return applied;
  }

  String _systemPrompt() {
    final categoryIds = kCategoryCatalog.keys.join(', ');
    return 'You audit transactions parsed from Ethiopian bank/Telebirr SMS. '
        'For each numbered row decide the best category and money direction. '
        'Valid categories: $categoryIds. '
        'Direction rules: "in" means money arrived to the user (credited, '
        'received, salary, refund, ገቢ); "out" means money left (debited, '
        'paid, sent, purchase, ወጪ). Read the SMS text carefully — Amharic '
        'may appear. '
        'Reply with ONLY a JSON array, no markdown fences, one object per '
        'row that needs a correction (omit rows that are already right): '
        '[{"id": "<row id>", "category": "<category id>", '
        '"direction": "in"|"out", "reason": "<max 10 words>"}]. '
        'If everything is correct, reply [].';
  }

  String _rowsPayload(List<TransactionRecord> chunk) {
    final buffer = StringBuffer('Rows to audit:\n');
    for (final tx in chunk) {
      final direction = isInflowType(tx.type) ? 'in' : 'out';
      final snippet = _truncate(tx.smsSnippet ?? '', 200);
      buffer.writeln(
        'id=${tx.id} | current_category=${tx.categoryId} | '
        'current_direction=$direction | sender=${tx.smsSender ?? '?'} | '
        'sms="$snippet"',
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

  String _truncate(String value, int max) {
    final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.length <= max
        ? collapsed
        : '${collapsed.substring(0, max)}…';
  }
}
