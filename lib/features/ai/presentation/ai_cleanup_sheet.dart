import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/features/ai/application/ai_categorization_service.dart';
import 'package:genzeb/features/reports/application/report_service.dart'
    show isInflowType;
import 'package:genzeb/features/transactions/domain/models/categories.dart';

/// Opens the AI cleanup flow: fetch suggestions, let the user pick which to
/// apply, then apply them.
Future<void> showAiCleanupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _AiCleanupSheet(),
  );
}

class _AiCleanupSheet extends ConsumerStatefulWidget {
  const _AiCleanupSheet();

  @override
  ConsumerState<_AiCleanupSheet> createState() => _AiCleanupSheetState();
}

class _AiCleanupSheetState extends ConsumerState<_AiCleanupSheet> {
  late Future<List<AiCategorySuggestion>> _suggestionsFuture;
  final Set<String> _deselected = {};
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _suggestionsFuture =
        ref.read(aiCategorizationServiceProvider).suggestCorrections();
  }

  Future<void> _apply(List<AiCategorySuggestion> all) async {
    final accepted = all
        .where((s) => !_deselected.contains(s.transactionId))
        .toList(growable: false);
    if (accepted.isEmpty) return;
    setState(() => _applying = true);
    try {
      final applied = await ref
          .read(aiCategorizationServiceProvider)
          .applySuggestions(accepted);
      refreshAppData(ref);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fixed $applied transaction${applied == 1 ? '' : 's'}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not apply: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_fix_high_rounded,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'AI category cleanup',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Gemini re-reads your SMS transactions and suggests fixes. '
                'Amounts are never changed — only category and direction.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<AiCategorySuggestion>>(
                  future: _suggestionsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const _SheetMessage(
                        icon: Icons.hourglass_top_rounded,
                        text: 'Asking Genzeb AI to audit your ledger…',
                        showSpinner: true,
                      );
                    }
                    if (snapshot.hasError) {
                      return _SheetMessage(
                        icon: Icons.error_outline_rounded,
                        text: '${snapshot.error}',
                      );
                    }
                    final suggestions = snapshot.data ?? const [];
                    if (suggestions.isEmpty) {
                      return const _SheetMessage(
                        icon: Icons.verified_rounded,
                        text:
                            'Nothing to fix — your categories already look right.',
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: suggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = suggestions[index];
                        final selected =
                            !_deselected.contains(suggestion.transactionId);
                        return _SuggestionTile(
                          suggestion: suggestion,
                          selected: selected,
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _deselected.remove(suggestion.transactionId);
                              } else {
                                _deselected.add(suggestion.transactionId);
                              }
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<AiCategorySuggestion>>(
                future: _suggestionsFuture,
                builder: (context, snapshot) {
                  final suggestions = snapshot.data ?? const [];
                  if (suggestions.isEmpty) return const SizedBox.shrink();
                  final selectedCount = suggestions
                      .where((s) => !_deselected.contains(s.transactionId))
                      .length;
                  return SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _applying || selectedCount == 0
                          ? null
                          : () => _apply(suggestions),
                      child: _applying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.2),
                            )
                          : Text(
                              'Apply $selectedCount fix${selectedCount == 1 ? '' : 'es'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.suggestion,
    required this.selected,
    required this.onChanged,
  });

  final AiCategorySuggestion suggestion;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = categoryInfoFor(suggestion.currentCategoryId);
    final proposed = categoryInfoFor(suggestion.suggestedCategoryId);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: selected
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.5))
            : null,
      ),
      child: CheckboxListTile(
        value: selected,
        onChanged: onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.fromLTRB(8, 6, 14, 10),
        title: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            suggestion.smsSnippet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Chip(label: current.label, color: current.color, faded: true),
                const Icon(Icons.arrow_forward_rounded, size: 14),
                _Chip(label: proposed.label, color: proposed.color),
                if (suggestion.changesDirection)
                  _Chip(
                    label: isInflowType(suggestion.suggestedType)
                        ? '→ Income'
                        : '→ Expense',
                    color: isInflowType(suggestion.suggestedType)
                        ? const Color(0xFF2E9E6B)
                        : const Color(0xFFEF6C5A),
                  ),
                Text(
                  formatMinorEtb(suggestion.amountMinor),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (suggestion.reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                suggestion.reason,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.faded = false});

  final String label;
  final Color color;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: faded ? 0.08 : 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: faded ? color.withValues(alpha: 0.6) : color,
          decoration: faded ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({
    required this.icon,
    required this.text,
    this.showSpinner = false,
  });

  final IconData icon;
  final String text;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showSpinner)
            const CircularProgressIndicator()
          else
            Icon(icon, size: 44, color: theme.colorScheme.primary),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
