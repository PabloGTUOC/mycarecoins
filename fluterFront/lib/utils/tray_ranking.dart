/// Most templates shown in the collapsed tray once the user has a habit.
const int kTrayQuickMax = 8;

/// Distinct used templates needed before the tray stops listing everything.
const int kTrayQuickMin = 3;

const Duration _lookBack = Duration(days: 60);
const Duration _lookAhead = Duration(days: 14);

/// Ranks [templates] by how often *this user* scheduled them recently.
///
/// An instance belongs to a template when title AND type match (instances
/// carry no template id). Only the user's own care instances count, within the
/// last 60 days (and up to 14 days ahead), so an old habit fades out.
///
/// `ordered` is every template: count desc, most recent use desc, title
/// (case-insensitive); unused ones last, by title. `quick` is the collapsed
/// tray set: with [kTrayQuickMin] or more distinct used templates, only the
/// used ones (at most [kTrayQuickMax]); otherwise the full ordered list.
({List<Map<String, dynamic>> ordered, List<Map<String, dynamic>> quick})
    rankTemplates({
  required List<Map<String, dynamic>> templates,
  required List<Map<String, dynamic>> activities,
  required String? userId,
  required DateTime now,
}) {
  String key(Map<String, dynamic> m) =>
      '${(m['title'] ?? '').toString()}\u0000${(m['type'] ?? '').toString()}';

  final nowUtc = now.toUtc();
  final from = nowUtc.subtract(_lookBack);
  final to = nowUtc.add(_lookAhead);
  final counts = <String, int>{};
  final latest = <String, DateTime>{};

  if (userId != null) {
    for (final a in activities) {
      if (a['is_template'] == true) continue;
      if (a['assigned_to']?.toString() != userId) continue;
      final category = (a['category'] ?? '').toString().toLowerCase();
      if (category != 'care') continue;
      final type = (a['type'] ?? '').toString().toLowerCase();
      if (type == 'coverage' || type == 'self') continue;
      final status = (a['status'] ?? '').toString().toLowerCase();
      if (status == 'rejected') continue;
      final rawTs = DateTime.tryParse(a['starts_at']?.toString() ?? '');
      if (rawTs == null) continue;
      final ts = rawTs.toUtc();
      if (ts.isBefore(from) || ts.isAfter(to)) continue;
      final k = key(a);
      counts[k] = (counts[k] ?? 0) + 1;
      final prev = latest[k];
      if (prev == null || ts.isAfter(prev)) latest[k] = ts;
    }
  }

  int byTitle(Map<String, dynamic> a, Map<String, dynamic> b) {
    final tA = (a['title'] ?? '').toString().toLowerCase();
    final tB = (b['title'] ?? '').toString().toLowerCase();
    final cmp = tA.compareTo(tB);
    if (cmp != 0) return cmp;
    return (a['type'] ?? '')
        .toString()
        .toLowerCase()
        .compareTo((b['type'] ?? '').toString().toLowerCase());
  }

  final ordered = List<Map<String, dynamic>>.from(templates);
  ordered.sort((a, b) {
    final cA = counts[key(a)] ?? 0;
    final cB = counts[key(b)] ?? 0;
    if (cA != cB) return cB.compareTo(cA);
    if (cA > 0) {
      final byRecent = latest[key(b)]!.compareTo(latest[key(a)]!);
      if (byRecent != 0) return byRecent;
    }
    return byTitle(a, b);
  });

  final used = ordered.where((t) => (counts[key(t)] ?? 0) > 0).toList();
  final distinctCount = used.map(key).toSet().length;
  final quick = distinctCount >= kTrayQuickMin
      ? used.take(kTrayQuickMax).toList()
      : List<Map<String, dynamic>>.from(ordered);
  return (ordered: ordered, quick: quick);
}
