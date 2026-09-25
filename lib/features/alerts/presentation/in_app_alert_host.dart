import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/design_system/institution_avatar.dart';
import 'package:genzeb/features/alerts/application/auto_sync_controller.dart';
import 'package:genzeb/features/alerts/domain/money_alert.dart';
import 'package:genzeb/features/alerts/presentation/alert_text.dart';
import 'package:genzeb/features/alerts/presentation/alert_widgets.dart';
import 'package:genzeb/features/alerts/presentation/notification_permission.dart';
import 'package:genzeb/features/transactions/presentation/transaction_detail_sheet.dart';

/// Drives auto-sync for the signed-in-or-not home experience and shows a
/// slide-down banner for every money-in / money-out SMS that arrives:
/// on launch, on returning to the app, and live while it is open.
class InAppAlertHost extends ConsumerStatefulWidget {
  const InAppAlertHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InAppAlertHost> createState() => _InAppAlertHostState();
}

class _InAppAlertHostState extends ConsumerState<InAppAlertHost>
    with WidgetsBindingObserver {
  static const _visibleFor = Duration(seconds: 5);

  late final AutoSyncController _autoSync;
  StreamSubscription<List<MoneyAlert>>? _subscription;
  StreamSubscription<String>? _taps;
  Timer? _hideTimer;
  MoneyAlert? _current;
  int _more = 0;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoSync = ref.read(autoSyncControllerProvider);
    _subscription = _autoSync.newAlerts.listen(_show);
    _autoSync.start();
    final bridge = ref.read(notificationBridgeProvider);
    _taps = bridge.taps.listen(_openTransaction);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // A big inbox makes the first refresh slow; neither the tapped
      // notification (already booked in the background) nor the permission
      // prompt should wait for it.
      unawaited(_autoSync.refresh());
      final launched = await bridge.takeLaunchTransaction();
      if (launched != null) await _openTransaction(launched);
      await askForNotificationPermissionOnce();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _autoSync.foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      // Messages booked by the background receiver while we were away.
      refreshAppData(ref);
      _autoSync.refresh();
    }
  }

  /// A system notification was tapped: show that transaction.
  Future<void> _openTransaction(String transactionId) async {
    final record = await ref
        .read(ledgerRepositoryProvider)
        .getTransactionById(transactionId);
    if (record == null || !mounted) return;
    await ref.read(moneyAlertServiceProvider).markRead('alert-$transactionId');
    refreshAppData(ref);
    if (!mounted) return;
    await showTransactionDetail(context, ref, record);
  }

  void _show(List<MoneyAlert> alerts) {
    if (!mounted || alerts.isEmpty) return;
    _hideTimer?.cancel();
    setState(() {
      _current = alerts.first;
      _more = alerts.length - 1;
      _visible = true;
    });
    _hideTimer = Timer(_visibleFor, _hide);
  }

  void _hide() {
    if (!mounted) return;
    setState(() => _visible = false);
  }

  void _onTap() {
    final alert = _current;
    _hide();
    if (alert == null) return;
    if (_more > 0) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
      );
    } else {
      openAlertTransaction(context, ref, alert);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _subscription?.cancel();
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alert = _current;
    return Stack(
      children: [
        widget.child,
        // Bottom, just above the tab bar: the top of the screen is where
        // the SMS app's own heads-up for the very same message appears,
        // which would hide this banner exactly when it matters.
        if (alert != null)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            left: 12,
            right: 12,
            bottom: _visible ? 12 : -160,
            child: GestureDetector(
              onTap: _onTap,
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 0) _hide();
              },
              child: _AlertBanner(alert: alert, more: _more),
            ),
          ),
      ],
    );
  }
}

class _AlertBanner extends ConsumerWidget {
  const _AlertBanner({required this.alert, required this.more});

  final MoneyAlert alert;
  final int more;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = ref.watch(stringsProvider);
    final hidden = ref.watch(amountsHiddenProvider);
    final color =
        alert.isIncome ? const Color(0xFF2E9E6B) : const Color(0xFFD9534F);
    return Material(
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      color: theme.cardTheme.color,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        child: Row(
          children: [
            InstitutionAvatar.forCode(alert.institutionCode, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${alert.isIncome ? strings.alertMoneyIn : strings.alertMoneyOut}'
                    ' · ${alertAmountLabel(alert, hidden: hidden)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    more > 0
                        ? '${alertSubtitle(alert)} · +$more more'
                        : alert.needsReview
                            ? '${alertSubtitle(alert)} · ${strings.alertNeedsReview}'
                            : alertSubtitle(alert),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
