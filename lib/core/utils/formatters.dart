import 'package:intl/intl.dart';

final _moneyFormat = NumberFormat.currency(symbol: 'ETB ', decimalDigits: 2);
final _plainFormat = NumberFormat('#,##0.00');
final _dayFormat = DateFormat('EEE, MMM d');
final _monthFormat = DateFormat('MMMM yyyy');
final _shortMonthFormat = DateFormat('MMM');
final _timeFormat = DateFormat('h:mm a');

/// Formats minor units (cents) as `ETB 1,234.56`.
String formatMinorEtb(int minor) => _moneyFormat.format(minor / 100.0);

/// Formats minor units without the currency symbol: `1,234.56`.
String formatMinorPlain(int minor) => _plainFormat.format(minor / 100.0);

/// Formats with a leading sign, e.g. `+ETB 50.00` / `-ETB 50.00`.
String formatSignedMinorEtb(int minor) {
  final sign = minor < 0 ? '-' : '+';
  return '$sign${formatMinorEtb(minor.abs())}';
}

/// Compact representation for tight UI: `ETB 12.5K`, `ETB 1.2M`.
String formatCompactEtb(int minor) {
  final major = minor / 100.0;
  final absVal = major.abs();
  final sign = major < 0 ? '-' : '';
  if (absVal >= 1000000) {
    return '${sign}ETB ${(absVal / 1000000).toStringAsFixed(absVal >= 10000000 ? 0 : 1)}M';
  }
  if (absVal >= 1000) {
    return '${sign}ETB ${(absVal / 1000).toStringAsFixed(absVal >= 100000 ? 0 : 1)}K';
  }
  return '${sign}ETB ${absVal.toStringAsFixed(0)}';
}

String formatDay(DateTime date) => _dayFormat.format(date);

String formatMonth(DateTime date) => _monthFormat.format(date);

String formatShortMonth(DateTime date) => _shortMonthFormat.format(date);

String formatTime(DateTime date) => _timeFormat.format(date);

/// Human friendly day grouping label.
String relativeDayLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = today.difference(target).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7 && diff > 0) return DateFormat('EEEE').format(date);
  return _dayFormat.format(date);
}
