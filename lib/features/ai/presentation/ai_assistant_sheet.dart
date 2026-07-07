import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/features/ai/application/ai_assistant_service.dart';

Future<void> showAiAssistant(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => const _AiAssistantSheet(),
  );
}

const _promptGroups = <_PromptGroup>[
  _PromptGroup(
    title: 'Quick Answers',
    icon: Icons.flash_on_rounded,
    prompts: [
      'What is my biggest single received transaction?',
      'What is my biggest single expense?',
      'How am I doing this month?',
    ],
  ),
  _PromptGroup(
    title: 'Spending Deep Dive',
    icon: Icons.pie_chart_rounded,
    prompts: [
      'Where am I overspending this month?',
      'Compare this month vs last month by category.',
      'Which transactions are unusual this month?',
    ],
  ),
  _PromptGroup(
    title: 'Budget Coach',
    icon: Icons.flag_rounded,
    prompts: [
      'Am I on track with my budgets?',
      'Which budget is most at risk?',
      'How much can I still spend safely this month?',
    ],
  ),
  _PromptGroup(
    title: 'Planning',
    icon: Icons.trending_up_rounded,
    prompts: [
      'Give me a practical savings plan from my current data.',
      'How can I improve my cashflow in the next 30 days?',
      'Set 3 realistic money goals for next month.',
    ],
  ),
];

class _PromptGroup {
  const _PromptGroup({
    required this.title,
    required this.icon,
    required this.prompts,
  });

  final String title;
  final IconData icon;
  final List<String> prompts;
}

class _AiAssistantSheet extends ConsumerStatefulWidget {
  const _AiAssistantSheet();

  @override
  ConsumerState<_AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends ConsumerState<_AiAssistantSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<AiChatMessage> _messages = [];
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    setState(() {
      _messages.add(AiChatMessage(fromUser: true, text: text));
      _sending = true;
    });
    _scrollToBottom();

    final service = ref.read(aiAssistantServiceProvider);
    final selectedCodes = ref.read(selectedInstitutionCodesProvider);
    try {
      final reply = await service.ask(
        List.of(_messages),
        institutionCodes: selectedCodes,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(AiChatMessage(fromUser: false, text: reply));
        _sending = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          AiChatMessage(fromUser: false, text: error.toString()),
        );
        _sending = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availability = ref.watch(aiAvailableProvider);
    final selectedCodes = ref.watch(selectedInstitutionCodesProvider);
    final institutionOptionsAsync = ref.watch(institutionFilterOptionsProvider);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final height = MediaQuery.of(context).size.height * 0.82;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets),
        child: Column(
          children: [
            _Header(theme: theme),
            const Divider(height: 1),
            _InstitutionScopeBar(
              theme: theme,
              selectedCodes: selectedCodes,
              optionsAsync: institutionOptionsAsync,
              onToggle: (code) => toggleInstitutionFilter(ref, code),
              onSelectAll: () => clearInstitutionFilters(ref),
            ),
            Expanded(
              child: availability.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => _UnavailableView(theme: theme),
                data: (available) {
                  if (!available) return _UnavailableView(theme: theme);
                  if (_messages.isEmpty) {
                    return _EmptyChat(theme: theme, onPrompt: _send);
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _messages.length) {
                        return const _TypingBubble();
                      }
                      return _MessageBubble(message: _messages[index]);
                    },
                  );
                },
              ),
            ),
            availability.maybeWhen(
              data: (available) => available
                  ? _Composer(
                      controller: _controller,
                      sending: _sending,
                      onSend: _send,
                    )
                  : const SizedBox.shrink(),
              orElse: () => const SizedBox.shrink(),
            ),
            SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.tertiary,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Genzeb AI',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Grounded in your real transactions',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InstitutionScopeBar extends StatelessWidget {
  const _InstitutionScopeBar({
    required this.theme,
    required this.selectedCodes,
    required this.optionsAsync,
    required this.onToggle,
    required this.onSelectAll,
  });

  final ThemeData theme;
  final Set<String> selectedCodes;
  final AsyncValue<List<InstitutionFilterOption>> optionsAsync;
  final ValueChanged<String> onToggle;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Institution scope',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: selectedCodes.isEmpty,
                  onSelected: (_) => onSelectAll(),
                ),
                const SizedBox(width: 8),
                ...optionsAsync.maybeWhen(
                  data: (options) => [
                    for (final option in options) ...[
                      FilterChip(
                        label: Text(option.label),
                        selected: selectedCodes.contains(option.code),
                        onSelected: (_) => onToggle(option.code),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                  orElse: () => const <Widget>[],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.theme, required this.onPrompt});
  final ThemeData theme;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      children: [
        Icon(
          Icons.tips_and_updates_outlined,
          size: 44,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          'Ask anything about your money',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Use organized prompts for fast, accurate insights.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        for (final group in _promptGroups) ...[
          Row(
            children: [
              Icon(group.icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                group.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final prompt in group.prompts)
                ActionChip(
                  label: Text(prompt),
                  onPressed: () => onPrompt(prompt),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 4),
        Text(
          'Tip: Ask in plain language (for example, "show biggest transfer I received this year").',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final AiChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromUser = message.fromUser;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: fromUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(fromUser ? 16 : 4),
            bottomRight: Radius.circular(fromUser ? 4 : 16),
          ),
        ),
        child: Text(
          message.text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: fromUser
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: onSend,
              decoration: InputDecoration(
                hintText: 'Ask Genzeb AI…',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: sending ? null : () => onSend(controller.text),
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

class _UnavailableView extends StatelessWidget {
  const _UnavailableView({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'AI is warming up',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Genzeb AI isn\'t reachable right now. Check your connection and '
            'try again in a moment.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
