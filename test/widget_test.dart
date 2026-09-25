import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genzeb/app/app.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/features/alerts/data/money_alert_repositories.dart';
import 'package:genzeb/features/budget/data/in_memory_budget_repository.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_sms_message_repository.dart';
import 'package:genzeb/features/transactions/data/in_memory_ledger_repository.dart';

/// The real app uses on-device SQLite; tests swap in in-memory repositories
/// so no platform channels are needed.
Widget _app() {
  return ProviderScope(
    overrides: [
      ledgerRepositoryProvider.overrideWithValue(InMemoryLedgerRepository()),
      budgetRepositoryProvider.overrideWithValue(InMemoryBudgetRepository()),
      smsMessageRepositoryProvider
          .overrideWithValue(InMemorySmsMessageRepository()),
      moneyAlertRepositoryProvider
          .overrideWithValue(InMemoryMoneyAlertRepository()),
    ],
    child: const GenzebApp(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app loads dashboard', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'intro_seen': true,
      'sms_setup_done': true,
    });
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // No account means no name to greet, so the header leads with the
    // greeting; the nav bar confirms the shell mounted.
    expect(
      find.textContaining(RegExp('^Good (morning|afternoon|evening)')),
      findsOneWidget,
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Ledger'), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('first launch never asks to sign in', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // Straight from the intro to the SMS disclosure — no sign-in step.
    expect(find.text('Connect your SMS'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });

  testWidgets('app starts in light mode', (tester) async {
    SharedPreferences.setMockInitialValues({
      'intro_seen': true,
      'sms_setup_done': true,
    });
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
  });
}
