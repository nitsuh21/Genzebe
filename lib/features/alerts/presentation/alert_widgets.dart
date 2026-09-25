import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/core/utils/formatters.dart';
import 'package:genzeb/design_system/institution_avatar.dart';
import 'package:genzeb/features/alerts/domain/money_alert.dart';
import 'package:genzeb/features/alerts/presentation/alert_text.dart';
import 'package:genzeb/features/transactions/presentation/transaction_detail_sheet.dart';

const _incomeColor = Color(0xFF2E9E6B);
const _expenseColor = Color(0xFFD9534F);

Future<void> openAlertTransaction(
  BuildContext context,
  WidgetRef ref,
  MoneyAlert alert,
) async {
  await ref.read(moneyAlertServiceProvider).markRead(alert.id);
  ref.invalidate(moneyAlertsProvider);
  final record = await ref
      .read(ledgerRepositoryProvider)
      .getTransactionById(alert.transactionId);
  if (record == null || !context.mounted) return;
  await showTransactionDetail(context, ref, record);
}

/// Bell with an unread-count badge; opens the notifications screen.
class AlertBellButton extends ConsumerWidget {
  const AlertBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadAlertCountProvider);
    final strings = ref.watch(stringsProvider);
    return IconButton.filledTonal(
      tooltip: strings.alertsTitle,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
      ),
      icon: Badge.count(
        count: unread,
        isLabelVisible: unread > 0,
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final alertsAsync = ref.watch(moneyAlertsProvider);
    final hidden = ref.watch(amountsHiddenProvider);
    final unread = ref.watch(unreadAlertCountProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.alertsTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () async {
                await ref.read(moneyAlertServiceProvider).markAllRead();
                ref.invalidate(moneyAlertsProvider);
              },
              child: Text(strings.alertsMarkRead),
            ),
        ],
      ),
      body: alertsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (alerts) {
          if (alerts.isEmpty) {
            return _EmptyAlerts(text: strings.alertsEmpty);
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              24 + MediaQuery.of(context).viewPadding.bottom,
            ),
            itemCount: alerts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final alert = alerts[index];
              return MoneyAlertTile(
                alert: alert,
                hidden: hidden,
                onTap: () => openAlertTransaction(context, ref, alert),
              );
            },
          );
        },
      ),
    );
  }
}

class MoneyAlertTile extends ConsumerWidget {
  const MoneyAlertTile({
    super.key,
    required this.alert,
    required this.hidden,
    this.onTap,
  });

  final MoneyAlert alert;
  final bool hidden;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = ref.watch(stringsProvider);
    final color = alert.isIncome ? _incomeColor : _expenseColor;
    return Material(
      color: theme.cardTheme.color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              InstitutionAvatar.forCode(alert.institutionCode, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          alert.isIncome
                              ? Icons.south_west_rounded
                              : Icons.north_east_rounded,
                          size: 15,
                          color: color,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            alertParty(alert),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!alert.isRead) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alertDetail(
                        alert,
                        moneyIn: strings.alertMoneyIn,
                        moneyOut: strings.alertMoneyOut,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (alert.needsReview)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          strings.alertNeedsReview,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFFE8833A),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    alertAmountLabel(alert, hidden: hidden),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${relativeDayLabel(alert.occurredAt)} · '
                    '${formatTime(alert.occurredAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAlerts extends StatelessWidget {
  const _EmptyAlerts({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
