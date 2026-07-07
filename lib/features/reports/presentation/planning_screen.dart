import 'package:flutter/material.dart';
import 'package:genzebet/core/utils/formatters.dart';
import 'package:genzebet/features/reports/domain/models/planning_models.dart';

class PlanningScreen extends StatelessWidget {
  const PlanningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final budgets = const [
      BudgetEnvelope(
          id: 'b1', categoryId: 'food', limitMinor: 250000, spentMinor: 170500),
      BudgetEnvelope(
          id: 'b2',
          categoryId: 'transport',
          limitMinor: 80000,
          spentMinor: 72000),
    ];
    final bills = [
      BillReminder(
        id: 'bill1',
        title: 'Internet',
        amountMinor: 120000,
        dueDate: DateTime.now().add(const Duration(days: 4)),
        isPaid: false,
      ),
      BillReminder(
        id: 'bill2',
        title: 'Rent',
        amountMinor: 1800000,
        dueDate: DateTime.now().add(const Duration(days: 9)),
        isPaid: false,
      ),
    ];
    final goals = [
      SavingsGoal(
        id: 'g1',
        title: 'Emergency Fund',
        targetMinor: 5000000,
        savedMinor: 2200000,
        targetDate: DateTime.now().add(const Duration(days: 160)),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const Text(
            'Planning',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text('Budget envelopes'),
          const SizedBox(height: 8),
          ...budgets.map(
            (budget) => Card(
              child: ListTile(
                title: Text(budget.categoryId),
                subtitle: Text(
                  'Spent ${formatMinorEtb(budget.spentMinor)} of ${formatMinorEtb(budget.limitMinor)}',
                ),
                trailing: Text(
                  '${((budget.spentMinor / budget.limitMinor) * 100).toStringAsFixed(0)}%',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Bill reminders'),
          const SizedBox(height: 8),
          ...bills.map(
            (bill) => Card(
              child: ListTile(
                title: Text(bill.title),
                subtitle: Text('Due ${bill.dueDate.toLocal()}'),
                trailing: Text(formatMinorEtb(bill.amountMinor)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Savings goals'),
          const SizedBox(height: 8),
          ...goals.map(
            (goal) => Card(
              child: ListTile(
                title: Text(goal.title),
                subtitle: Text(
                  'Saved ${formatMinorEtb(goal.savedMinor)} of ${formatMinorEtb(goal.targetMinor)}',
                ),
                trailing: Text(
                  '${((goal.savedMinor / goal.targetMinor) * 100).toStringAsFixed(0)}%',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
