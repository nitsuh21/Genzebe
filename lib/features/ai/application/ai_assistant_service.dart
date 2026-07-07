import 'package:genzebet/core/utils/formatters.dart';
import 'package:genzebet/features/ai/ai_config.dart';
import 'package:genzebet/features/ai/data/gemini_client.dart';
import 'package:genzebet/features/budget/application/budget_service.dart';
import 'package:genzebet/features/reports/application/report_service.dart';
import 'package:genzebet/features/transactions/domain/models/categories.dart';
import 'package:genzebet/features/transactions/domain/models/transaction_models.dart';
import 'package:genzebet/features/transactions/domain/repositories/ledger_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiChatMessage {
  const AiChatMessage({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;
}

/// Coordinates the Gemini-powered assistant: stores the API key locally,
/// builds a grounded financial context from real app data, and answers
/// questions / generates insights about reporting, budgeting and planning.
class AiAssistantService {
  AiAssistantService({
    required GeminiClient geminiClient,
    required ReportService reportService,
    required BudgetService budgetService,
    required LedgerRepository ledgerRepository,
  })  : _gemini = geminiClient,
        _reportService = reportService,
        _budgetService = budgetService,
        _ledgerRepository = ledgerRepository;

  final GeminiClient _gemini;
  final ReportService _reportService;
  final BudgetService _budgetService;
  final LedgerRepository _ledgerRepository;

  static const _keyPref = 'gemini_api_key';

  /// Resolves the active Gemini key. The app-provided (bundled) key always wins
  /// so users never need to supply their own; a locally stored key is only used
  /// as an optional advanced override when no bundled key is configured.
  Future<String?> getApiKey() async {
    if (AiConfig.hasBundledKey) return AiConfig.bundledGeminiKey;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyPref)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  /// True when AI is ready to use (app ships the key, or an override is stored).
  Future<bool> isAvailable() async => (await getApiKey()) != null;

  /// Whether the running build already includes an app-provided key.
  bool get hasBundledKey => AiConfig.hasBundledKey;

  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPref, key.trim());
  }

  Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPref);
  }

  /// Answers a free-form question grounded in the user's financial data.
  Future<String> ask(
    List<AiChatMessage> history, {
    Set<String> institutionCodes = const <String>{},
  }) async {
    final deterministic = await _tryAnswerDeterministic(
      history,
      institutionCodes: institutionCodes,
    );
    if (deterministic != null) return deterministic;

    final apiKey = await getApiKey();
    if (apiKey == null) {
      throw GeminiException(
        'AI is not configured in this build yet. Please try again later.',
      );
    }
    final context = await _buildContext(institutionCodes: institutionCodes);
    return _gemini.generate(
      apiKey: apiKey,
      systemInstruction: _systemPrompt(context),
      history: history
          .map((m) => GeminiChatTurn(fromUser: m.fromUser, text: m.text))
          .toList(growable: false),
    );
  }

  /// One-shot insight generation for a specific area of the app.
  Future<String> generateInsight(
    AiInsightKind kind, {
    Set<String> institutionCodes = const <String>{},
  }) async {
    final prompt = switch (kind) {
      AiInsightKind.reports =>
        'Give me 3 concise, specific insights about my spending and income '
            'this month versus last month. Call out the biggest changes and '
            'one concrete action. Use short bullet points.',
      AiInsightKind.budget =>
        'Review my budgets versus actual spend this month. Tell me which '
            'budgets are at risk, where I have room, and suggest one realistic '
            'adjustment. Use short bullet points.',
      AiInsightKind.planning =>
        'Based on my income, expenses and savings rate, suggest a simple, '
            'realistic monthly savings plan and one habit to improve cashflow. '
            'Keep it under 6 short lines.',
    };
    return ask(
      [AiChatMessage(fromUser: true, text: prompt)],
      institutionCodes: institutionCodes,
    );
  }

  String _systemPrompt(String context) {
    return 'You are Genze AI, a friendly, sharp personal-finance assistant '
        'inside an Ethiopian money-tracking app. All amounts are in ETB. '
        'Answer only from the financial snapshot provided; if the data is '
        'insufficient, say so plainly. Be concise, concrete and encouraging. '
        'Never invent numbers. If asked for biggest/lowest/single transaction, '
        'use the "Top single transactions" section directly.\n\n'
        'FINANCIAL SNAPSHOT:\n$context';
  }

  Future<String> _buildContext({
    required Set<String> institutionCodes,
  }) async {
    final insights = await _reportService.generateDashboardInsights(
      institutionCodes: institutionCodes,
    );
    final series = await _reportService.monthlySeries(
      months: 6,
      institutionCodes: institutionCodes,
    );
    final overview = await _budgetService.buildOverview(
      institutionCodes: institutionCodes,
    );
    final accounts = await _ledgerRepository.getAccounts();
    final transactions = await _ledgerRepository.getTransactions();
    final filteredAccountIds = _allowedAccountIds(
      accounts: accounts,
      institutionCodes: institutionCodes,
    );
    final scopedTransactions = transactions
        .where((tx) => filteredAccountIds.contains(tx.accountId))
        .toList(growable: false);

    final buffer = StringBuffer();
    buffer.writeln('This month:');
    buffer.writeln('- Income: ${formatMinorEtb(insights.incomeMinor)}');
    buffer.writeln('- Expense: ${formatMinorEtb(insights.expenseMinor)}');
    buffer.writeln('- Net: ${formatMinorEtb(insights.netMinor)}');
    buffer.writeln('- Total balance: ${formatMinorEtb(insights.totalBalanceMinor)}');
    buffer.writeln('- Savings rate: ${insights.savingsRate.toStringAsFixed(1)}%');
    buffer.writeln('- Net change vs last month: '
        '${insights.monthNetDeltaPercent.toStringAsFixed(1)}%');
    buffer.writeln('- Transactions tracked: ${insights.transactionCount}');

    if (insights.categoryTotalsMinor.isNotEmpty) {
      final sorted = insights.categoryTotalsMinor.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      buffer.writeln('Top spending categories this month:');
      for (final entry in sorted.take(6)) {
        buffer.writeln(
          '- ${categoryInfoFor(entry.key).label}: ${formatMinorEtb(entry.value)}',
        );
      }
    }

    if (insights.accountCards.isNotEmpty) {
      buffer.writeln('Accounts:');
      for (final card in insights.accountCards) {
        buffer.writeln(
          '- ${card.title} (${card.subtitle}): ${formatMinorEtb(card.balanceMinor)}',
        );
      }
    }

    final accountById = {
      for (final account in accounts) account.id: account,
    };
    if (institutionCodes.isEmpty) {
      buffer.writeln('Institution filter: All institutions');
    } else {
      final labels = institutionCodes.map((code) => code.toUpperCase()).toList()
        ..sort();
      buffer.writeln('Institution filter: ${labels.join(', ')}');
    }

    if (scopedTransactions.isNotEmpty) {
      final inflows = scopedTransactions
          .where((t) => isInflowType(t.type))
          .toList();
      final outflows = scopedTransactions
          .where((t) => isOutflowType(t.type))
          .toList();
      inflows.sort((a, b) => b.amount.minorUnits.compareTo(a.amount.minorUnits));
      outflows.sort(
        (a, b) => b.amount.minorUnits.compareTo(a.amount.minorUnits),
      );

      buffer.writeln('Top single transactions (all-time):');
      if (inflows.isNotEmpty) {
        final top = inflows.first;
        buffer.writeln(
          '- Biggest inflow received: ${formatMinorEtb(top.amount.minorUnits)} '
          'on ${formatDay(top.occurredAt)} from '
          '${_sourceLabel(top, accountById[top.accountId])}',
        );
      } else {
        buffer.writeln('- Biggest inflow received: no inflow found.');
      }
      if (outflows.isNotEmpty) {
        final top = outflows.first;
        buffer.writeln(
          '- Biggest outflow sent: ${formatMinorEtb(top.amount.minorUnits)} '
          'on ${formatDay(top.occurredAt)} via '
          '${_sourceLabel(top, accountById[top.accountId])}',
        );
      } else {
        buffer.writeln('- Biggest outflow sent: no outflow found.');
      }

      final recent = List<TransactionRecord>.from(scopedTransactions)
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      buffer.writeln('Recent transactions (latest 10):');
      for (final tx in recent.take(10)) {
        final direction = isInflowType(tx.type) ? 'IN' : 'OUT';
        final category = categoryInfoFor(tx.categoryId).label;
        buffer.writeln(
          '- ${formatDay(tx.occurredAt)} [$direction] '
          '${formatMinorEtb(tx.amount.minorUnits)} '
          '${_sourceLabel(tx, accountById[tx.accountId])} '
          '(category: $category)',
        );
      }
    }

    if (overview.items.isNotEmpty) {
      buffer.writeln('Budgets this month:');
      for (final item in overview.items) {
        final categories = item.budget.categoryIds.isEmpty
            ? 'All categories'
            : item.budget.categoryIds
                .map((id) => categoryInfoFor(id).label)
                .join(', ');
        final institutions = item.budget.institutionCodes.isEmpty
            ? 'All institutions'
            : item.budget.institutionCodes
                .map((code) => code.toUpperCase())
                .join(', ');
        buffer.writeln(
          '- ${item.budget.name} [$categories | $institutions]: spent '
          '${formatMinorEtb(item.spentMinor)} of '
          '${formatMinorEtb(item.budget.limitMinor)} '
          '(${(item.ratio * 100).toStringAsFixed(0)}%)',
        );
      }
      if (overview.unbudgetedSpendMinor > 0) {
        buffer.writeln(
          '- Unbudgeted spend: ${formatMinorEtb(overview.unbudgetedSpendMinor)}',
        );
      }
    } else {
      buffer.writeln('No budgets set yet.');
    }

    buffer.writeln('Last 6 months (income / expense):');
    for (final bucket in series) {
      buffer.writeln(
        '- ${formatShortMonth(bucket.month)}: '
        '${formatMinorEtb(bucket.incomeMinor)} / '
        '${formatMinorEtb(bucket.expenseMinor)}',
      );
    }

    return buffer.toString();
  }

  Future<String?> _tryAnswerDeterministic(
    List<AiChatMessage> history, {
    required Set<String> institutionCodes,
  }) async {
    if (history.isEmpty) return null;
    final latest = history.last;
    if (!latest.fromUser) return null;
    final text = latest.text.toLowerCase();

    final asksBiggest =
        text.contains('biggest') || text.contains('largest') || text.contains('highest');
    if (!asksBiggest) return null;

    final wantsInflow = text.contains('receive') ||
        text.contains('received') ||
        text.contains('income') ||
        text.contains('inflow');
    final wantsOutflow = text.contains('spent') ||
        text.contains('expense') ||
        text.contains('outflow') ||
        text.contains('sent');
    if (!wantsInflow && !wantsOutflow) return null;

    final transactions = await _ledgerRepository.getTransactions();
    final accounts = await _ledgerRepository.getAccounts();
    final accountById = {
      for (final account in accounts) account.id: account,
    };
    final filteredAccountIds = _allowedAccountIds(
      accounts: accounts,
      institutionCodes: institutionCodes,
    );
    final candidates = transactions.where((tx) {
      if (!filteredAccountIds.contains(tx.accountId)) return false;
      if (wantsInflow && isInflowType(tx.type)) return true;
      if (wantsOutflow && isOutflowType(tx.type)) return true;
      return false;
    }).toList();
    if (candidates.isEmpty) {
      return wantsInflow
          ? 'I could not find any received (inflow) transaction yet.'
          : 'I could not find any sent/spent (outflow) transaction yet.';
    }
    candidates.sort((a, b) => b.amount.minorUnits.compareTo(a.amount.minorUnits));
    final top = candidates.first;
    final qualifier = wantsInflow ? 'received' : 'sent/spent';
    return 'Your biggest single $qualifier transaction is '
        '${formatMinorEtb(top.amount.minorUnits)} on ${formatDay(top.occurredAt)} '
        'from ${_sourceLabel(top, accountById[top.accountId])}.';
  }

  String _sourceLabel(TransactionRecord tx, Account? account) {
    if (tx.smsSender != null && tx.smsSender!.trim().isNotEmpty) {
      return tx.smsSender!.trim();
    }
    if (account != null) {
      final institution = account.institutionCode?.trim();
      if (institution != null && institution.isNotEmpty) {
        return institution.toUpperCase();
      }
      return account.name;
    }
    return 'unknown source';
  }

  Set<String> _allowedAccountIds({
    required List<Account> accounts,
    required Set<String> institutionCodes,
  }) {
    if (institutionCodes.isEmpty) {
      return accounts.map((account) => account.id).toSet();
    }
    return accounts
        .where((account) {
          final code = account.institutionCode?.trim().toLowerCase();
          return code != null && institutionCodes.contains(code);
        })
        .map((account) => account.id)
        .toSet();
  }
}

enum AiInsightKind { reports, budget, planning }
