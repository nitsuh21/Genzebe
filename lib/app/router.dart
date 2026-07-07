import 'package:flutter/material.dart';
import 'package:genzebet/features/ai/presentation/ai_assistant_sheet.dart';
import 'package:genzebet/features/budget/presentation/budget_screen.dart';
import 'package:genzebet/features/reports/presentation/reports_screen.dart';
import 'package:genzebet/features/settings/presentation/settings_screen.dart';
import 'package:genzebet/features/transactions/presentation/dashboard_screen.dart';
import 'package:genzebet/features/transactions/presentation/transactions_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final aiFabBottomOffset = 84.0 + safeBottom;
    final pages = <Widget>[
      const DashboardScreen(),
      const TransactionsScreen(),
      const BudgetScreen(),
      const ReportsScreen(),
      const SettingsScreen(),
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
                tooltip: 'Genze AI',
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
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Ledger'),
            NavigationDestination(
                icon: Icon(Icons.savings_outlined), label: 'Budget'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Reports'),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              label: 'Settings',
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
