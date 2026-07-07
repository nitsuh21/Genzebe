import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/features/account/presentation/profile_screen.dart';
import 'package:genzeb/features/ai/presentation/ai_assistant_sheet.dart';
import 'package:genzeb/features/budget/presentation/budget_screen.dart';
import 'package:genzeb/features/reports/presentation/reports_screen.dart';
import 'package:genzeb/features/transactions/presentation/dashboard_screen.dart';
import 'package:genzeb/features/transactions/presentation/transactions_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final aiFabBottomOffset = 84.0 + safeBottom;
    final pages = <Widget>[
      const DashboardScreen(),
      const TransactionsScreen(),
      const BudgetScreen(),
      const ReportsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: SafeArea(top: true, bottom: false, child: pages[_index]),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _index == 1
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: aiFabBottomOffset),
              child: FloatingActionButton.small(
                onPressed: () => _openAiAssistant(context),
                tooltip: 'Genzeb AI',
                child: const Icon(Icons.smart_toy_outlined),
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) {
            setState(() => _index = index);
          },
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.home_outlined), label: strings.navHome),
            NavigationDestination(
                icon: const Icon(Icons.swap_horiz), label: strings.navLedger),
            NavigationDestination(
                icon: const Icon(Icons.savings_outlined),
                label: strings.navBudget),
            NavigationDestination(
                icon: const Icon(Icons.bar_chart), label: strings.navReports),
            NavigationDestination(
              icon: const Icon(Icons.person_outline_rounded),
              label: strings.navProfile,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAiAssistant(BuildContext context) async {
    await showAiAssistant(context);
  }
}
