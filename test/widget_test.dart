// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genzeb/app/app.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/features/budget/data/in_memory_budget_repository.dart';
import 'package:genzeb/features/sms_ingestion/data/in_memory_sms_message_repository.dart';
import 'package:genzeb/features/transactions/data/in_memory_ledger_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Skip onboarding: offline mode already chosen, SMS setup done.
  SharedPreferences.setMockInitialValues({
    'sms_setup_done': true,
    'account_local_mode': true,
  });

  testWidgets('app loads dashboard', (WidgetTester tester) async {
    // The real app uses on-device SQLite; in tests we swap in in-memory
    // repositories so no platform channels are needed.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ledgerRepositoryProvider.overrideWithValue(InMemoryLedgerRepository()),
          budgetRepositoryProvider
              .overrideWithValue(InMemoryBudgetRepository()),
          smsMessageRepositoryProvider
              .overrideWithValue(InMemorySmsMessageRepository()),
        ],
        child: const GenzebApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Genzeb'), findsOneWidget);
  });
}
