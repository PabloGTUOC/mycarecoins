import '../l10n/app_localizations.dart';

/// Formats the user-facing title of an activity.
///
/// The server names coverage rows "Covering for {title}" in English for every
/// language. When [activity] is a coverage item (`type == 'coverage'`) and its
/// title starts with `"Covering for "`, this returns `l.coveringFor(rest)` in
/// the current locale. Otherwise it returns the activity's title unchanged.
String displayTitle(AppLocalizations l, Map<String, dynamic> activity) {
  final rawTitle = (activity['title'] ?? activity['activity_title'] ?? '').toString();
  final type = (activity['type'] ?? activity['activity_type'])?.toString();
  final reason = activity['reason']?.toString();
  final isCoverage = type == 'coverage' ||
      (type == null && reason != null && reason.startsWith('coverage'));

  if (isCoverage) {
    const prefix = 'Covering for ';
    if (rawTitle.startsWith(prefix)) {
      final rest = rawTitle.substring(prefix.length).trim();
      return l.coveringFor(rest);
    }
  }
  return rawTitle;
}
