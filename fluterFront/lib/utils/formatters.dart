import 'package:intl/intl.dart';

/// Formats an ISO month string (e.g. "2026-08") to a localized short month-year label
/// using `DateFormat.yMMM(locale)` (e.g. "Aug 2026" in EN, "ago 2026" in ES).
///
/// If [raw] is not a parseable ISO month, it returns [raw] unchanged.
String formatChartMonth(String raw, [String? locale]) {
  try {
    final trimmed = raw.trim();
    final parts = trimmed.split('-');
    if (parts.length == 2 && parts[0].length == 4) {
      final y = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      return DateFormat.yMMM(locale).format(DateTime(y, m));
    }
    final dt = DateTime.parse(trimmed.length == 7 ? '$trimmed-01' : trimmed);
    return DateFormat.yMMM(locale).format(dt);
  } catch (_) {
    return raw;
  }
}
