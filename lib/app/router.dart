import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genzeb/app/providers.dart';
import 'package:genzeb/features/account/presentation/profile_screen.dart';
import 'package:genzeb/features/budget/presentation/budget_screen.dart';
import 'package:genzeb/features/reports/presentation/reports_screen.dart';
import 'package:genzeb/features/transactions/presentation/dashboard_screen.dart';
import 'package:genzeb/features/transactions/presentation/transactions_screen.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final index = ref.watch(homeTabProvider);
    final pendingReview =
        ref.watch(reviewQueueProvider).valueOrNull?.length ?? 0;

    return Scaffold(
      // IndexedStack keeps every tab alive, so filters and scroll positions
      // survive switching tabs instead of resetting on each visit.
      body: SafeArea(
        top: true,
        bottom: false,
        child: IndexedStack(
          index: index,
          children: const [
            DashboardScreen(),
            TransactionsScreen(),
            BudgetScreen(),
            ReportsScreen(),
            ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) =>
              ref.read(homeTabProvider.notifier).state = i,
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
              icon: Badge.count(
                count: pendingReview,
                isLabelVisible: pendingReview > 0,
                child: const Icon(Icons.person_outline_rounded),
              ),
              label: strings.navProfile,
            ),
          ],
        ),
      ),
    );
  }
}
