import 'package:intl/intl.dart';

final _naira = NumberFormat('#,##0', 'en');
final _nairaKobo = NumberFormat('#,##0.00', 'en');
final _day = DateFormat('EEE d MMM');
final _dayLong = DateFormat('EEEE d MMMM');
final _time = DateFormat('h:mma');

/// ₦120,000
String naira(int amount) => '₦${_naira.format(amount)}';

/// ₦10,000.00, for receipts.
String nairaExact(int amount) => '₦${_nairaKobo.format(amount)}';

/// Fri 3 Oct
String shortDate(DateTime d) => _day.format(d);

/// Friday 3 October
String longDate(DateTime d) => _dayLong.format(d);

/// 9:12am
String clockTime(DateTime d) => _time.format(d).toLowerCase();

/// "today", "tomorrow", "in 3 days", "2 days ago"
String relativeDay(DateTime d, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final diff = _dateOnly(d).difference(today).inDays;
  return switch (diff) {
    0 => 'today',
    1 => 'tomorrow',
    -1 => 'yesterday',
    > 1 => 'in $diff days',
    _ => '${-diff} days ago',
  };
}

/// Nigerian mobile numbers: 0803..., 234803..., +234803... -> +234803...
String? normalisePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (RegExp(r'^0[789][01]\d{8}$').hasMatch(digits)) return '+234${digits.substring(1)}';
  if (RegExp(r'^[789][01]\d{8}$').hasMatch(digits)) return '+234$digits';
  if (RegExp(r'^234[789][01]\d{8}$').hasMatch(digits)) return '+$digits';
  return null;
}

/// +2348031234567 -> 0803 123 4567
String displayPhone(String e164) {
  if (!e164.startsWith('+234') || e164.length != 14) return e164;
  final local = '0${e164.substring(4)}';
  return '${local.substring(0, 4)} ${local.substring(4, 7)} ${local.substring(7)}';
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
