import 'package:genzebet/features/profile/domain/models/subscription_models.dart';

class ReminderService {
  const ReminderService();

  List<DateTime> buildTrialReminderSchedule(Entitlement entitlement) {
    if (entitlement.type != EntitlementType.trial) return const [];
    return _relativeReminderDays(entitlement.expiresAt, const [14, 7, 3, 1, 0]);
  }

  List<DateTime> buildPremiumReminderSchedule(Entitlement entitlement) {
    if (entitlement.type != EntitlementType.premium) return const [];
    return _relativeReminderDays(
      entitlement.expiresAt,
      const [30, 14, 7, 3, 1, 0],
    );
  }

  List<DateTime> _relativeReminderDays(DateTime end, List<int> days) {
    return days
        .map((day) => end.subtract(Duration(days: day)))
        .where((date) => date.isAfter(DateTime.now()))
        .toList(growable: false);
  }
}
