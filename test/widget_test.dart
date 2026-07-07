// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genzebet/app/app.dart';
import 'package:genzebet/app/providers.dart';
import 'package:genzebet/features/budget/data/in_memory_budget_repository.dart';
import 'package:genzebet/features/transactions/data/in_memory_ledger_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('app loads dashboard', (WidgetTester tester) async {
    // The real app uses on-device SQLite; in tests we swap in in-memory
    // repositories so no platform channels are needed.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ledgerRepositoryProvider.overrideWithValue(InMemoryLedgerRepository()),
          budgetRepositoryProvider
              .overrideWithValue(InMemoryBudgetRepository()),
        ],
        child: const GenzeBetApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GenzeBet'), findsOneWidget);
  });
}
