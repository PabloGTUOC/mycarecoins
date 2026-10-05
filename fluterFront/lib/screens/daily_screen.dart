import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/json.dart';
import '../widgets/absence_dialog.dart';
import '../widgets/personal_time_dialog.dart';
import '../widgets/coach_marks.dart';
import '../widgets/ui.dart';

/// Wide layout: Task Library side panel (drag source) + 6:00–24:00 hour-grid
/// timeline with chips positioned by start time and sized by duration,
/// overlap offsets, red now-line, drop-to-schedule (30-min snapping) and
/// drag-out-to-unschedule. Narrow layout: timeline list with gap indicators,
/// day-swipe, swipe-to-remove and the task bottom sheet.
class DailyScreen extends StatefulWidget {
  final String date; // yyyy-MM-dd
  const DailyScreen({super.key, required this.date});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

const int kStartHour = 6;
const int kTotalHours = 18;
const double kGridHeight = 18 * 64.0;

/// Localized free-time gap between timeline cards. Reuses the duration keys so
/// gaps read the same way as activity durations across the app.
String formatGap(AppLocalizations l, int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return l.durMins('$m');
  if (m == 0) return l.durHours(h);
  return l.durHoursMins(h, m);
}

bool get _isTouchDevice =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

/// A plain [Draggable] grabs the pointer immediately, which makes lists and
/// the hour grid unscrollable by touch (a scroll gesture starting on a chip
/// becomes a drag). On touch devices use long-press to start dragging.
Widget touchAwareDraggable({
  required Map<String, dynamic> data,
  VoidCallback? onDragStarted,
  void Function(DraggableDetails)? onDragEnd,
  required Widget feedback,
  Widget? childWhenDragging,
  required Widget child,
}) {
  if (_isTouchDevice) {
    return LongPressDraggable<Map<String, dynamic>>(
      data: data,
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      child: child,
    );
  }
  return Draggable<Map<String, dynamic>>(
    data: data,
    onDragStarted: onDragStarted,
    onDragEnd: onDragEnd,
    feedback: feedback,
    childWhenDragging: childWhenDragging,
    child: child,
  );
}

class _DailyScreenState extends State<DailyScreen> {
  List<Map<String, dynamic>> _activities = [];
  List<Map<String, dynamic>> _absences = [];
  List<Map<String, dynamic>> _requests = [];
  double? _doubleTapDy;
  bool _loading = true;
  bool _error = false;
  late DateTime _day;
  bool _draggingScheduled = false;
  final _gridScroll = ScrollController();
  final _gridKey = GlobalKey();

  final _tourDateKey = GlobalKey();
  final _tourAddKey = GlobalKey();
  final _tourAbsenceKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _day = DateTime.parse(widget.date);
    _load();
  }

  @override
  void dispose() {
    _gridScroll.dispose();
    super.dispose();
  }

  void _maybeTour() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading) return;
      final l = AppLocalizations.of(context);
      maybeShowTour(context, 'daily', [
        CoachMark(
          targetKey: _tourDateKey,
          title: l.tourDayTitle,
          body: l.tourDayBody,
        ),
        CoachMark(
          targetKey: _tourAddKey,
          title: l.tourAddTitle,
          body: l.tourAddBody,
        ),
        CoachMark(
          targetKey: _tourAbsenceKey,
          title: l.tourAwayTitle,
          body: l.tourAwayBody,
        ),
      ]);
    });
  }

  bool get _isToday => _sameDay(DateTime.now(), _day);

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final results = await Future.wait([
        app.api.get('/api/activities?familyId=${app.familyId}'),
        app.api.get('/api/absences?familyId=${app.familyId}'),
        // Defensive: Future.wait fails fast, and a hiccup on the newest
        // endpoint should not blank out the whole day.
        app.api
            .get('/api/personal-time?familyId=${app.familyId}')
            .catchError((_) => <String, dynamic>{'requests': []}),
      ]);
      final acts = results[0] is List
          ? results[0] as List
          : (results[0]['activities'] as List? ?? []);
      final abs = results[1] is List
          ? results[1] as List
          : (results[1]['absences'] as List? ?? []);
      if (mounted) {
        setState(() {
          _activities =
              acts.cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
          _absences =
              abs.cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
          _requests = ((results[2]['requests'] as List?) ?? [])
              .cast<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList();
          _loading = false;
          _error = false;
        });
        _scrollToNow();
        _maybeTour();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  void _scrollToNow() {
    if (!_isToday) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_gridScroll.hasClients) return;
      final top = _nowLineTop;
      if (top == null) return;
      final target = (top / 100 * kGridHeight) -
          _gridScroll.position.viewportDimension / 2;
      _gridScroll
          .jumpTo(target.clamp(0.0, _gridScroll.position.maxScrollExtent));
    });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime? _startsAt(Map<String, dynamic> a) =>
      DateTime.tryParse(a['starts_at']?.toString() ?? '')?.toLocal();

  /// Today's scheduled activities, sorted, each annotated with overlapCount
  /// and gapBeforeMinutes.
  List<Map<String, dynamic>> get _scheduledToday {
    final acts = _activities.where((a) {
      if (a['is_template'] == true) return false;
      final ts = _startsAt(a);
      return ts != null && _sameDay(ts, _day);
    }).toList();

    acts.sort((a, b) {
      final tA = _startsAt(a)!.millisecondsSinceEpoch;
      final tB = _startsAt(b)!.millisecondsSinceEpoch;
      if (tA != tB) return tA.compareTo(tB);
      return toNum(b['duration_minutes'])
          .compareTo(toNum(a['duration_minutes']));
    });

    final positioned = <Map<String, dynamic>>[];
    for (var i = 0; i < acts.length; i++) {
      final a = Map<String, dynamic>.from(acts[i]);
      final startA = _startsAt(a)!.millisecondsSinceEpoch;
      var overlapCount = 0;
      for (var j = 0; j < i; j++) {
        final b = positioned[j];
        final startB = _startsAt(b)!.millisecondsSinceEpoch;
        final durA = toNum(a['duration_minutes']).toInt();
        final durB = toNum(b['duration_minutes']).toInt();
        final endA = startA + (durA < 60 ? 60 : durA) * 60000;
        final endB = startB + (durB < 60 ? 60 : durB) * 60000;
        if ((startA > startB ? startA : startB) < (endA < endB ? endA : endB)) {
          overlapCount++;
        }
      }

      final int prevEnd;
      if (i == 0) {
        prevEnd = DateTime(_day.year, _day.month, _day.day, kStartHour)
            .millisecondsSinceEpoch;
      } else {
        final prev = positioned[i - 1];
        prevEnd = _startsAt(prev)!.millisecondsSinceEpoch +
            toNum(prev['duration_minutes']).toInt() * 60000;
      }
      final gap = ((startA - prevEnd) / 60000).round();
      a['_overlapCount'] = overlapCount;
      a['_gapBeforeMinutes'] = gap > 0 ? gap : 0;
      positioned.add(a);
    }
    return positioned;
  }

  List<Map<String, dynamic>> get _completedToday =>
      _scheduledToday.where((a) => a['status'] == 'completed').toList();

  num get _todayCoins =>
      _completedToday.fold<num>(0, (sum, a) => sum + toNum(a['coin_value']));

  double? get _nowLineTop {
    final now = DateTime.now();
    final hour = now.hour + now.minute / 60;
    if (hour < kStartHour || hour > kStartHour + kTotalHours) return null;
    return ((hour - kStartHour) / kTotalHours) * 100;
  }

  List<Map<String, dynamic>> get _dayAbsences => _absences.where((a) {
        final start = DateTime.tryParse(a['start_time']?.toString() ?? '');
        final end = DateTime.tryParse(a['end_time']?.toString() ?? '');
        if (start == null) return false;
        final dayStart = DateTime(_day.year, _day.month, _day.day);
        final dayEnd = dayStart.add(const Duration(days: 1));
        return start.isBefore(dayEnd) && (end ?? start).isAfter(dayStart);
      }).toList();

  /// Requests still waiting on an answer that touch the day being shown. They
  /// are not activities yet — nothing is booked until someone accepts — so they
  /// ride alongside absences rather than in the timeline itself.
  List<Map<String, dynamic>> get _dayRequests => _requests.where((r) {
        if (r['status'] != 'pending') return false;
        final start = DateTime.tryParse(r['starts_at']?.toString() ?? '');
        final end = DateTime.tryParse(r['ends_at']?.toString() ?? '');
        if (start == null) return false;
        final dayStart = DateTime(_day.year, _day.month, _day.day);
        final dayEnd = dayStart.add(const Duration(days: 1));
        return start.toLocal().isBefore(dayEnd) &&
            (end ?? start).toLocal().isAfter(dayStart);
      }).toList();

  List<Map<String, dynamic>> get _templates => _activities
      .where((a) => a['is_template'] == true && a['status'] == 'approved')
      .toList();

  void _changeDay(int delta) {
    setState(() => _day = _day.add(Duration(days: delta)));
    _scrollToNow();
  }

  // ── Actions ─────────────────────────────────────────────────────

  Future<void> _validate(dynamic id) async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    await app.runAction(() async {
      await app.api.post('/api/activities/$id/validate');
      await _load();
    }, l.toastValidated);
  }

  Future<void> _unschedule(dynamic id, {required bool series}) async {
    // Reached after the awaited remove-confirmation dialog; the State may be
    // gone (session expiry, family switch) by the time the user confirms.
    if (!mounted) return;
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    await app.runAction(() async {
      await app.api
          .delete('/api/activities/$id${series ? '?series=true' : ''}');
      await _load();
    }, series ? l.toastSeriesRemoved : l.toastActivityRemoved);
  }

  Future<void> _removeFlow(Map<String, dynamic> a) async {
    if (a['is_recurrent'] == true) {
      final l = AppLocalizations.of(context);
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg)),
          title: Text(l.removeRecurringTitle,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Text(l.removeRecurringBody((a['title'] ?? '').toString())),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'single'),
                child: Text(l.removeThisOne)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'series'),
                child: Text(l.removeWholeSeries,
                    style: const TextStyle(color: AppColors.danger))),
          ],
        ),
      );
      if (choice == null) return;
      await _unschedule(a['id'], series: choice == 'series');
    } else {
      await _unschedule(a['id'], series: false);
    }
  }

  Future<void> _openBountyDialog(Map<String, dynamic> a) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text(l.bountyDialogTitle,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.bountyDialogBody((a['title'] ?? '').toString()),
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            VInput(
                controller: controller,
                label: l.bountyLabel,
                placeholder: l.bountyHint,
                keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(controller.text)),
              child: Text(l.offerBounty)),
        ],
      ),
    );
    if (amount == null || amount <= 0) return;
    if (!mounted) return;
    final app = context.read<AppState>();
    await app.runAction(() async {
      await app.api
          .post('/api/activities/${a['id']}/bounty', {'bountyAmount': amount});
      await _load();
    }, l.toastBountyAdded);
  }

  Future<void> _acceptBounty(Map<String, dynamic> a) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text(l.takeOverTitle,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(l.takeOverBody(
            (a['title'] ?? '').toString(), '${a['bounty_amount']}')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.takeOver)),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    final app = context.read<AppState>();
    await app.runAction(() async {
      await app.api.post('/api/activities/${a['id']}/accept-bounty');
      await app.fetchUserData();
      await _load();
    }, l.toastTaskTaken);
  }

  /// Tapping a completed card explains why nothing happens: validated
  /// activities are locked on the schedule (no recurrence); undoing one
  /// means reverting its coin entry from the ledger in the Personal Area.
  Future<void> _showCompletedLockedDialog() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg)),
          title: Text(AppLocalizations.of(ctx).completedLockedTitle,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Text(AppLocalizations.of(ctx).completedLockedBody,
              style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.of(ctx).gotIt)),
          ],
        ),
      );

  Future<void> _openRecurrenceDialog(Map<String, dynamic> a) async {
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    var frequency = 'daily';
    DateTime? until = _day.add(const Duration(days: 1));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg)),
          title: Text(l.recurrenceTitle,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.recurrenceBody((a['title'] ?? '').toString()),
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: frequency,
                decoration: InputDecoration(labelText: l.frequency),
                items: [
                  DropdownMenuItem(value: 'daily', child: Text(l.freqDaily)),
                  DropdownMenuItem(
                      value: 'weekdays', child: Text(l.freqWeekdays)),
                  DropdownMenuItem(value: 'weekly', child: Text(l.freqWeekly)),
                ],
                onChanged: (v) => setLocal(() => frequency = v ?? 'daily'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: until ?? _day.add(const Duration(days: 7)),
                    firstDate: _day,
                    lastDate: _day.add(const Duration(days: 365)),
                  );
                  if (picked != null) setLocal(() => until = picked);
                },
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(until == null
                    ? l.pickUntilDate
                    : l.untilDate(
                        DateFormat('d MMM yyyy', loc).format(until!))),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.cancel)),
            TextButton(
                onPressed:
                    until == null ? null : () => Navigator.pop(ctx, true),
                child: Text(l.createCopies)),
          ],
        ),
      ),
    );
    if (confirmed != true || until == null) return;
    if (!mounted) return;
    final app = context.read<AppState>();
    await app.runAction(() async {
      final res = await app.api.post('/api/activities/${a['id']}/recurrence', {
        'frequency': frequency,
        'untilDate': DateFormat('yyyy-MM-dd').format(until!),
      });
      await _load();
      app.setSuccess(l.toastCreatedInstances(toNum(res['created']).toInt()));
    });
  }

  Future<void> _openAbsenceDialog() async {
    final created = await showLogAbsenceDialog(context, day: _day);
    if (created && mounted) await _load();
  }

  Future<void> _absenceDetail(Map<String, dynamic> abs) async {
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    final delete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text('✈️ ${abs['title']}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
            '${l.absenceAway((abs['user_alias'] ?? abs['user_name'] ?? l.fallbackACaregiver).toString())}\n'
            '${DateFormat('d MMM HH:mm', loc).format(DateTime.parse(abs['start_time'].toString()).toLocal())}'
            ' → ${DateFormat('d MMM HH:mm', loc).format(DateTime.parse(abs['end_time'].toString()).toLocal())}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(l.close)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.remove,
                  style: const TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (delete != true) return;
    if (!mounted) return;
    final app = context.read<AppState>();
    await app.runAction(() async {
      await app.api.delete('/api/absences/${abs['id']}');
      await _load();
    }, l.toastTimeOffRemoved);
  }

  // ── Scheduling (hour/minute selects, 06:00–23:30, like DailyModals) ──

  Future<void> _openScheduleDialog(Map<String, dynamic> activity,
      {int? hour, int? minute}) async {
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    var h = (hour ?? DateTime.now().hour).clamp(kStartHour, 23);
    var m = (minute ?? (DateTime.now().minute >= 30 ? 30 : 0)) >= 30 ? 30 : 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg)),
          title: Text(l.scheduleTaskTitle,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  l.scheduleTaskBody((activity['title'] ?? '').toString(),
                      DateFormat('EEEE, MMM d', loc).format(_day)),
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: h,
                      decoration: InputDecoration(labelText: l.hourLabel),
                      items: [
                        for (var i = kStartHour; i <= 23; i++)
                          DropdownMenuItem(
                              value: i,
                              child: Text(i.toString().padLeft(2, '0'))),
                      ],
                      onChanged: (v) => setLocal(() => h = v ?? h),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: m,
                      decoration: InputDecoration(labelText: l.minuteLabel),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('00')),
                        DropdownMenuItem(value: 30, child: Text('30')),
                      ],
                      onChanged: (v) => setLocal(() => m = v ?? m),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.cancel)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l.scheduleAction)),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await _confirmSchedule(
        activity['id'], DateTime(_day.year, _day.month, _day.day, h, m));
  }

  Future<void> _confirmSchedule(dynamic activityId, DateTime startsAt) async {
    // Reached after the awaited schedule dialog; guard against the State being
    // disposed while it was open (matches the other post-dialog flows here).
    if (!mounted) return;
    final app = context.read<AppState>();
    // Block scheduling inside your own absence.
    final activityEnd = startsAt.add(const Duration(hours: 1));
    final overlaps = _dayAbsences.any((abs) {
      if (abs['user_id']?.toString() != app.userId?.toString()) return false;
      final s = DateTime.tryParse(abs['start_time']?.toString() ?? '');
      final e = DateTime.tryParse(abs['end_time']?.toString() ?? '');
      if (s == null || e == null) return false;
      return s.isBefore(activityEnd) && e.isAfter(startsAt);
    });
    final l = AppLocalizations.of(context);
    if (overlaps) {
      app.setError(l.errScheduleDuringAbsence);
      return;
    }
    await app.runAction(() async {
      await app.api.post('/api/activities/$activityId/schedule',
          {'startsAt': startsAt.toUtc().toIso8601String()});
      await _load();
    }, l.toastScheduled);
  }

  /// Double-tap an empty stretch of the grid to claim it for yourself. Uses the
  /// same dy → 30-minute-slot maths as a drag drop, so both gestures land on the
  /// same times.
  Future<void> _openPersonalTime([double? localDy, DateTime? at]) async {
    var start = at;
    if (start == null) {
      final pct = ((localDy ?? 0) / kGridHeight).clamp(0.0, 1.0);
      var h = kStartHour + pct * kTotalHours;
      h = ((h * 2).round() / 2).clamp(kStartHour.toDouble(), 23.5);
      start = DateTime(
          _day.year, _day.month, _day.day, h.floor(), h % 1 == 0.5 ? 30 : 0);
    }
    final created = await showPersonalTimeSheet(context, start: start);
    if (created && mounted) await _load();
  }

  /// Accept, decline or withdraw a pending request.
  Future<void> _openRequest(Map<String, dynamic> r) async {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    final loc = l.localeName;
    final mine = r['requester_id']?.toString() == app.userId?.toString();
    final start = DateTime.parse(r['starts_at'].toString()).toLocal();
    final end = DateTime.parse(r['ends_at'].toString()).toLocal();
    final pays = toNum(r['baseline_coins']) + toNum(r['sweetener_coins']);

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text(
            '${personalTimeTypeGlyph(r['type']?.toString() ?? '')} ${r['title']}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.ptCoverCardBody(
                (r['requester_name'] ?? '').toString(),
                '${DateFormat('EEE d MMM', loc).format(start)} '
                '${DateFormat('HH:mm').format(start)}–${DateFormat('HH:mm').format(end)}',
                (r['title'] ?? '').toString())),
            if ((r['description'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(r['description'].toString(),
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(l.ptCoverPays(pays),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: AppColors.success)),
              ),
          ],
        ),
        actions: mine
            ? [
                TextButton(
                    onPressed: () => Navigator.pop(ctx), child: Text(l.close)),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, 'withdraw'),
                    child: Text(l.withdrawAction,
                        style: const TextStyle(color: AppColors.danger))),
              ]
            : [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, 'decline'),
                    child: Text(l.declineAction)),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, 'accept'),
                    child: Text(l.acceptAction,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.success))),
              ],
      ),
    );
    if (action == null || !mounted) return;

    final (path, method, toast) = switch (action) {
      'accept' => (
          '/api/personal-time/${r['id']}/accept',
          'post',
          l.toastCoverageAccepted
        ),
      'decline' => (
          '/api/personal-time/${r['id']}/decline',
          'post',
          l.toastCoverageDeclined
        ),
      _ => (
          '/api/personal-time/${r['id']}',
          'delete',
          l.toastPersonalTimeWithdrawn
        ),
    };
    // Accepting a repeating request books what works and skips what does not,
    // so the toast reports the count rather than claiming a clean sweep.
    Map? answer;
    final ok = await app.runAction(() async {
      if (method == 'post') {
        final res = await app.api.post(path);
        if (res is Map) answer = res;
      } else {
        await app.api.delete(path);
      }
      await _load();
    });
    if (!ok || !mounted) return;
    app.setSuccess(_coverageToast(l, answer) ?? toast);
  }

  /// The count, but only when there is something the plain toast would hide.
  String? _coverageToast(AppLocalizations l, Map? answer) {
    final skipped = toNum(answer?['skipped'] ?? 0).toInt();
    if (skipped == 0) return null;
    final created = toNum(answer?['created'] ?? 0).toInt();
    return l.toastCoverageAcceptedSeries(created, created + skipped);
  }

  /// Drop on the hour grid: local dy → 30-min slot (mirror of dropOnTimeline).
  void _onGridDrop(Map<String, dynamic> payload, double localDy) {
    final pct = (localDy / kGridHeight).clamp(0.0, 1.0);
    var h = kStartHour + pct * kTotalHours;
    h = ((h * 2).round() / 2).clamp(kStartHour.toDouble(), 23.5);
    final activity = payload['activity'] as Map<String, dynamic>;
    _openScheduleDialog(activity,
        hour: h.floor(), minute: h % 1 == 0.5 ? 30 : 0);
  }

  Future<void> _openScheduleSheet() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _TaskSheet(templates: _templates),
    );
    if (picked == null || !mounted) return;
    if (picked['__personalTime'] == true) {
      final now = DateTime.now();
      final hour = _isToday ? (now.hour + 1).clamp(kStartHour, 22) : 9;
      return _openPersonalTime(
          null, DateTime(_day.year, _day.month, _day.day, hour));
    }
    await _openScheduleDialog(picked);
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wide = isWideLayout(context);
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    final items = _scheduledToday;
    final done = _completedToday.length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 4),
            if (wide)
              Text(l.dailyTitle,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(
                onPressed: () => _changeDay(-1),
                tooltip: l.prevDay,
                icon: const Icon(Icons.chevron_left_rounded)),
            Text(
                DateFormat(wide ? 'EEEE, MMM d' : 'EEE, MMM d', loc)
                    .format(_day),
                key: _tourDateKey,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            IconButton(
                onPressed: () => _changeDay(1),
                tooltip: l.nextDay,
                icon: const Icon(Icons.chevron_right_rounded)),
            const Spacer(),
          ],
        ),
        actions: [
          TextButton.icon(
            key: _tourAbsenceKey,
            onPressed: _openAbsenceDialog,
            icon: const Icon(Icons.flight_takeoff_rounded,
                size: 17, color: AppColors.textSecondary),
            label: Text(wide ? l.timeOffLong : l.timeOffShort,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: wide
          ? null
          : FloatingActionButton.extended(
              key: _tourAddKey,
              onPressed: _openScheduleSheet,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(l.addTask,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error && _activities.isEmpty
              ? LoadErrorState(onRetry: () {
                  setState(() => _loading = true);
                  _load();
                })
              : Column(
                  children: [
                    // Day progress: "X / Y done · 🪙 Zcc"
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(AppRadii.pill),
                              child: LinearProgressIndicator(
                                value: items.isEmpty ? 0 : done / items.length,
                                minHeight: 6,
                                backgroundColor: AppColors.border,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${l.doneProgress('$done', '${items.length}')}'
                            '${_todayCoins > 0 ? ' · 🪙 ${_todayCoins}cc' : ''}',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                        child: wide ? _buildWide(items) : _buildNarrow(items)),
                  ],
                ),
    );
  }

  // ── Wide: Task Library panel + hour grid ────────────────────────

  Widget _buildWide(List<Map<String, dynamic>> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 300,
            child: DragTarget<Map<String, dynamic>>(
              onWillAcceptWithDetails: (d) => d.data['type'] == 'scheduled',
              onAcceptWithDetails: (d) =>
                  _removeFlow(d.data['activity'] as Map<String, dynamic>),
              builder: (context, candidates, _) => Container(
                decoration: BoxDecoration(
                  color: candidates.isNotEmpty
                      ? AppColors.dangerSoft
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: _draggingScheduled
                      ? Border.all(color: AppColors.danger)
                      : null,
                ),
                child: _draggingScheduled
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.delete_outline_rounded,
                                size: 34, color: AppColors.danger),
                            const SizedBox(height: 8),
                            Text(AppLocalizations.of(context).dropToUnschedule,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.danger)),
                          ],
                        ),
                      )
                    : _TaskLibraryPanel(
                        templates: _templates,
                        onSchedule: (a) => _openScheduleDialog(a),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  if (_dayAbsences.isNotEmpty || _dayRequests.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final r in _dayRequests) _requestChip(r),
                            for (final abs in _dayAbsences)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Tappable(
                                  onTap: () => _absenceDetail(abs),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.dangerSoft,
                                      borderRadius:
                                          BorderRadius.circular(AppRadii.sm),
                                    ),
                                    child: Text(
                                      '✈️ ${abs['user_alias'] ?? abs['user_name'] ?? ''} · ${abs['title']}',
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.danger),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(child: _buildHourGrid(items)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourGrid(List<Map<String, dynamic>> items) {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        controller: _gridScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        child: DragTarget<Map<String, dynamic>>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (details) {
            final box =
                _gridKey.currentContext?.findRenderObject() as RenderBox?;
            if (box == null) return;
            final local = box.globalToLocal(details.offset);
            _onGridDrop(details.data, local.dy);
          },
          builder: (context, candidates, _) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            // onDoubleTapDown lands first and carries the position; onDoubleTap
            // fires without one, so the slot is remembered between them.
            onDoubleTapDown: (d) => _doubleTapDy = d.localPosition.dy,
            onDoubleTap: () => _openPersonalTime(_doubleTapDy),
            child: Container(
              key: _gridKey,
              height: kGridHeight,
              color: candidates.isNotEmpty
                  ? AppColors.primarySoft.withValues(alpha: 0.4)
                  : Colors.transparent,
              child: Stack(
                children: [
                  // Hour lines + labels
                  for (var h = 0; h <= kTotalHours; h++)
                    Positioned(
                      top: h / kTotalHours * kGridHeight,
                      left: 0,
                      right: 0,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 62,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                _hourLabel(kStartHour + h),
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          ),
                          const Expanded(
                              child:
                                  Divider(height: 1, color: AppColors.border)),
                        ],
                      ),
                    ),
                  // Now line
                  if (_isToday && _nowLineTop != null)
                    Positioned(
                      top: _nowLineTop! / 100 * kGridHeight,
                      left: 60,
                      right: 10,
                      child: IgnorePointer(
                        child: Row(
                          children: [
                            Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: AppColors.danger,
                                    shape: BoxShape.circle)),
                            Expanded(
                                child: Container(
                                    height: 2, color: AppColors.danger)),
                          ],
                        ),
                      ),
                    ),
                  // Scheduled chips
                  for (final a in items) _buildChip(a),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A request nobody has answered yet: dashed, muted, and tappable. Nothing is
  /// booked until someone accepts, so it deliberately does not look like a
  /// scheduled activity.
  Widget _requestChip(Map<String, dynamic> r) {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    final mine = r['requester_id']?.toString() == app.userId?.toString();
    final label = mine
        ? (r['requested_of_name'] == null
            ? l.ptAwaitingAnyone
            : l.ptAwaiting(r['requested_of_name'].toString()))
        : l.ptAskedYouToCover((r['requester_name'] ?? '').toString());
    final start =
        DateTime.tryParse(r['starts_at']?.toString() ?? '')?.toLocal();

    return Tappable(
      onTap: () => _openRequest(r),
      child: Container(
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border.all(color: AppColors.inputBorder),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Text(
          '${personalTimeTypeGlyph(r['type']?.toString() ?? '')} '
          '${r['title']} · $label'
          '${start == null ? '' : ' · ${DateFormat('HH:mm').format(start)}'}',
          style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary),
        ),
      ),
    );
  }

  // 24-hour labels, consistent with the HH:mm format on every chip/card.
  String _hourLabel(int h24) => '${(h24 % 24).toString().padLeft(2, '0')}:00';

  Widget _buildChip(Map<String, dynamic> a) {
    final ts = _startsAt(a)!;
    final hour = ts.hour + ts.minute / 60;
    final clamped = hour < kStartHour ? kStartHour.toDouble() : hour;
    final top = (clamped - kStartHour) / kTotalHours * kGridHeight;
    final durMin = toNum(a['duration_minutes']).toDouble();
    final durH = (durMin < 60 ? 60 : durMin) / 60;
    final visibleH = durH < (24 - clamped) ? durH : (24 - clamped);
    final height =
        (visibleH / kTotalHours * kGridHeight).clamp(46.0, kGridHeight);
    final overlap = (a['_overlapCount'] as int?) ?? 0;
    final cappedOverlap = overlap > 4 ? 4 : overlap;
    final left = 70.0 + cappedOverlap * 45.0;
    final status = a['status']?.toString() ?? 'pending';
    final completed = status == 'completed';
    final isCare = a['type'] == 'care';
    final isSelf = isSelfActivity(a);
    // Personal time earns nothing, so it never gets the filled "completed work"
    // treatment — it reads as a claim on the day, not as a contribution.
    final filled = completed && !isSelf;

    final (bg, fg, border) = status == 'rejected'
        ? (AppColors.dangerSoft, AppColors.danger, AppColors.dangerSoft)
        : filled
            ? (
                isCare ? AppColors.success : AppColors.warning,
                Colors.white,
                Colors.transparent
              )
            : isSelf
                ? (AppColors.bg, AppColors.textSecondary, AppColors.inputBorder)
                : (AppColors.surface, AppColors.textPrimary, AppColors.border);

    final chip = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadii.md),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(
                  alpha: overlap > 0 ? 0.2 + 0.1 * cappedOverlap : 0.12),
              blurRadius: 15,
              offset: overlap > 0 ? const Offset(-5, 5) : const Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child:
                Text(_activityEmoji(a), style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                if (status == 'rejected') const TextSpan(text: '⚠️ '),
                TextSpan(text: (a['title'] ?? '').toString()),
                if (a['is_recurrent'] == true) const TextSpan(text: '  🔁'),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w800, color: fg),
            ),
          ),
          const SizedBox(width: 6),
          AssigneeBadge(item: a, compact: true),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color:
                  filled ? Colors.black.withValues(alpha: 0.15) : AppColors.bg,
              border: filled ? null : Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(DateFormat('HH:mm').format(ts),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: filled ? Colors.white : AppColors.textSecondary)),
          ),
          const SizedBox(width: 6),
          _ActivityAction(
            item: a,
            compact: true,
            onValidate: () => _validate(a['id']),
            onDelegate: () => _openBountyDialog(a),
            onTakeOver: () => _acceptBounty(a),
          ),
        ],
      ),
    );

    final interactive = Tappable(
      onTap: completed
          ? _showCompletedLockedDialog
          : (a['is_recurrent'] == true ? () => _openRecurrenceDialog(a) : null),
      child: chip,
    );

    return Positioned(
      top: top,
      left: left,
      right: 10,
      child: completed
          ? interactive
          : touchAwareDraggable(
              data: {'type': 'scheduled', 'activity': a},
              onDragStarted: () => setState(() => _draggingScheduled = true),
              onDragEnd: (_) => setState(() => _draggingScheduled = false),
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                    width: 320, child: Opacity(opacity: 0.85, child: chip)),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: chip),
              child: interactive,
            ),
    );
  }

  // ── Narrow: timeline list with gaps + swipe ─────────────────────

  Widget _buildNarrow(List<Map<String, dynamic>> items) {
    final l = AppLocalizations.of(context);
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) _changeDay(1);
        if (v > 300) _changeDay(-1);
      },
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            for (final abs in _dayAbsences)
              Tappable(
                onTap: () => _absenceDetail(abs),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Row(
                    children: [
                      const Text('✈️', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${abs['user_alias'] ?? abs['user_name'] ?? AppLocalizations.of(context).absAway} · ${abs['title']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_dayRequests.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(children: [
                  for (final r in _dayRequests) _requestChip(r),
                ]),
              ),
            if (items.isEmpty)
              Tappable(
                onTap: _openScheduleSheet,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 28, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      Text(AppLocalizations.of(context).emptyDayTitle,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(AppLocalizations.of(context).emptyDayAction,
                          style: const TextStyle(color: AppColors.primary)),
                    ],
                  ),
                ),
              )
            else
              for (final a in items) ...[
                if (((a['_gapBeforeMinutes'] as int?) ?? 0) >= 30)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, left: 52),
                    child: Tappable(
                      // Double-tap is invisible; a free gap that says what it is
                      // for gives the gesture somewhere discoverable to live.
                      onTap: () => _openPersonalTime(
                          null,
                          _startsAt(a)!.subtract(Duration(
                              minutes: (a['_gapBeforeMinutes'] as int?) ?? 0))),
                      child: Row(
                        children: [
                          const Expanded(
                              child: Divider(color: AppColors.border)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                                '${formatGap(l, (a['_gapBeforeMinutes'] as int?) ?? 0)} · ${l.personalTimeGapHint}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary)),
                          ),
                          const Expanded(
                              child: Divider(color: AppColors.border)),
                        ],
                      ),
                    ),
                  ),
                _buildDismissibleCard(a),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildDismissibleCard(Map<String, dynamic> a) {
    final status = a['status']?.toString() ?? 'pending';
    final card = _TimelineCard(
      item: a,
      onValidate: () => _validate(a['id']),
      onDelegate: () => _openBountyDialog(a),
      onTakeOver: () => _acceptBounty(a),
      onRecurrence: () => _openRecurrenceDialog(a),
      onCompletedInfo: _showCompletedLockedDialog,
    );
    if (status == 'completed') return card;
    return Dismissible(
      key: ValueKey('act-${a['id']}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _removeFlow(a);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 12, left: 52),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_rounded, color: AppColors.danger),
            const SizedBox(width: 6),
            Text(AppLocalizations.of(context).remove,
                style: const TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      child: card,
    );
  }
}

/// Shared action decision tree for timeline cards.
class _ActivityAction extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool compact;
  final VoidCallback onValidate;
  final VoidCallback onDelegate;
  final VoidCallback onTakeOver;

  const _ActivityAction({
    required this.item,
    required this.onValidate,
    required this.onDelegate,
    required this.onTakeOver,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final status = item['status']?.toString() ?? 'pending';
    final bounty = toNum(item['bounty_amount']);
    final mine = item['assigned_to']?.toString() == app.userId?.toString();

    Widget pill(String text, Color color, Color bg, [VoidCallback? onTap]) {
      final w = Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 9 : 12, vertical: compact ? 3 : 6),
        decoration: BoxDecoration(
          color: bg,
          border: onTap != null ? Border.all(color: color) : null,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: compact ? 10.5 : 12,
                fontWeight: FontWeight.w800,
                color: color)),
      );
      if (onTap == null) return w;
      // Pad the tap area toward the 44dp guideline without growing the
      // visual pill; the compact grid chips have no vertical room to spare.
      return Tappable(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: compact
            ? w
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                child: w),
      );
    }

    // Personal time is nobody's to validate, delegate or take over; its own
    // accept/decline flow arrives with the requests (plan Phase 5).
    if (isSelfActivity(item)) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);
    if (status == 'pending_validation') {
      return (!mine && app.isCaregiver)
          ? pill(l.pillValidate, AppColors.primary, AppColors.primarySoft,
              onValidate)
          : pill(l.pillAwaiting, AppColors.warning, AppColors.warningSoft);
    }
    if (status == 'completed') {
      return pill(l.pillDone, Colors.white, Colors.black26);
    }
    if (status == 'rejected') {
      return pill(l.pillRejected, AppColors.danger, AppColors.dangerSoft);
    }
    // pending / approved
    if (mine && bounty == 0 && app.isCaregiver) {
      return pill(
          l.pillDelegate, AppColors.warning, AppColors.warningSoft, onDelegate);
    }
    if (mine && bounty > 0) {
      return pill(
          l.pillOffering('$bounty'), AppColors.warning, AppColors.warningSoft);
    }
    if (!mine && bounty > 0 && app.isCaregiver) {
      return pill(l.pillTakeOver('$bounty'), AppColors.success,
          AppColors.successSoft, onTakeOver);
    }
    // Assignee is shown by _AssigneeBadge on every chip/card; no action here.
    return const SizedBox.shrink();
  }
}

/// Timeline glyph for an activity, by subclass and type. Coverage is care work
/// but reads differently — it is time held for someone else — so it gets its
/// own mark rather than sharing the care heart.
String _activityEmoji(Map<String, dynamic> item) {
  if (isSelfActivity(item)) return '🧘';
  return switch (item['type']) {
    'coverage' => '🏠',
    'care' => '❤️',
    _ => '🍽️',
  };
}

/// Desktop Task Library panel:
/// search, category filters, grouped rows that are drag sources.
class _TaskLibraryPanel extends StatefulWidget {
  final List<Map<String, dynamic>> templates;
  final void Function(Map<String, dynamic>) onSchedule;

  const _TaskLibraryPanel({required this.templates, required this.onSchedule});

  @override
  State<_TaskLibraryPanel> createState() => _TaskLibraryPanelState();
}

class _TaskLibraryPanelState extends State<_TaskLibraryPanel> {
  final _search = TextEditingController();
  int _filter = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.toLowerCase();
    final filtered = widget.templates.where((t) {
      if (_filter == 1 && t['type'] != 'care') return false;
      if (_filter == 2 && t['type'] != 'household') return false;
      if (q.isNotEmpty &&
          !(t['title']?.toString().toLowerCase().contains(q) ?? false)) {
        return false;
      }
      return true;
    }).toList();

    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text(l.taskLibrary,
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        ),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: l.searchTasks,
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedTabs(
          tabs: [l.filterAll, l.filterCare, l.filterHousehold],
          selected: _filter,
          onChanged: (i) => setState(() => _filter = i),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            children: [
              for (final cat in ['care', 'household'])
                if (filtered.any((t) => t['type'] == cat)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                    child: Row(
                      children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: cat == 'care'
                                    ? AppColors.success
                                    : AppColors.warning,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 7),
                        Text(cat == 'care' ? l.careWellness : l.filterHousehold,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  for (final t in filtered.where((t) => t['type'] == cat))
                    _libraryRow(t, cat),
                ],
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(l.noTasksFiltered,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _libraryRow(Map<String, dynamic> t, String cat) {
    final row = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: cat == 'care'
                    ? AppColors.successSoft
                    : AppColors.warningSoft,
                shape: BoxShape.circle),
            child: Text(cat == 'care' ? '❤️' : '🧹',
                style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((t['title'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800)),
                Text(
                    '${cat == 'care' ? AppLocalizations.of(context).filterCare : AppLocalizations.of(context).categoryCleaning} · 🪙 ${t['coin_value'] ?? 0}cc',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const Icon(Icons.drag_indicator_rounded,
              size: 18, color: AppColors.inputBorder),
        ],
      ),
    );

    return touchAwareDraggable(
      data: {'type': 'template', 'activity': t},
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 280, child: Opacity(opacity: 0.9, child: row)),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: row),
      child: Tappable(onTap: () => widget.onSchedule(t), child: row),
    );
  }
}

/// Bottom sheet task library with search + category filter (mobile task sheet).
class _TaskSheet extends StatefulWidget {
  final List<Map<String, dynamic>> templates;
  const _TaskSheet({required this.templates});

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  final _search = TextEditingController();
  int _filter = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.toLowerCase();
    final filtered = widget.templates.where((t) {
      if (_filter == 1 && t['type'] != 'care') return false;
      if (_filter == 2 && t['type'] != 'household') return false;
      if (q.isNotEmpty &&
          !(t['title']?.toString().toLowerCase().contains(q) ?? false)) {
        return false;
      }
      return true;
    }).toList();

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context).sheetAddTask,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).searchTasks,
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.bg,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            borderSide:
                                const BorderSide(color: AppColors.border)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Personal time is not in the task library — it is not a
                    // family task — but this is where people look for "add".
                    Tappable(
                      onTap: () =>
                          Navigator.of(context).pop({'__personalTime': true}),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Row(
                          children: [
                            const Text('🧘', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                  AppLocalizations.of(context)
                                      .personalTimeEntry,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary)),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                size: 20, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedTabs(
                      tabs: [
                        AppLocalizations.of(context).filterAll,
                        AppLocalizations.of(context).filterCare,
                        AppLocalizations.of(context).filterHousehold,
                      ],
                      selected: _filter,
                      onChanged: (i) => setState(() => _filter = i),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  children: [
                    for (final t in filtered)
                      ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.md)),
                        leading: Text(t['type'] == 'care' ? '❤️' : '🍽️',
                            style: const TextStyle(fontSize: 20)),
                        title: Text((t['title'] ?? '').toString(),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        trailing: PillBadge(text: '${t['coin_value'] ?? 0} cc'),
                        onTap: () => Navigator.of(context).pop(t),
                      ),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                              AppLocalizations.of(context).noMatchingTasks,
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onValidate;
  final VoidCallback onDelegate;
  final VoidCallback onTakeOver;
  final VoidCallback onRecurrence;
  final VoidCallback onCompletedInfo;

  const _TimelineCard({
    required this.item,
    required this.onValidate,
    required this.onDelegate,
    required this.onTakeOver,
    required this.onRecurrence,
    required this.onCompletedInfo,
  });

  @override
  Widget build(BuildContext context) {
    final status = item['status']?.toString() ?? 'pending';
    final isCare = item['type'] == 'care';
    final isSelf = isSelfActivity(item);
    final ts =
        DateTime.tryParse(item['starts_at']?.toString() ?? '')?.toLocal();
    final bounty = toNum(item['bounty_amount']);
    final isRecurrent = item['is_recurrent'] == true;
    final completed = status == 'completed';
    final filled = completed && !isSelf;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(ts != null ? DateFormat('HH:mm').format(ts) : '—',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary)),
          ),
        ),
        Expanded(
          child: Tappable(
            onTap: completed
                ? onCompletedInfo
                : (isRecurrent ? onRecurrence : null),
            onLongPress: completed ? onCompletedInfo : onRecurrence,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: filled
                    ? (isCare ? AppColors.success : AppColors.warning)
                    : AppColors.surface,
                border: Border.all(
                    color: filled
                        ? Colors.transparent
                        : (isSelf ? AppColors.inputBorder : AppColors.border)),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(_activityEmoji(item),
                          style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            if (status == 'rejected')
                              const TextSpan(text: '⚠️ '),
                            TextSpan(text: (item['title'] ?? '').toString()),
                            if (isRecurrent) const TextSpan(text: '  🔁'),
                          ]),
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: filled
                                  ? Colors.white
                                  : AppColors.textPrimary),
                        ),
                      ),
                      if (bounty > 0 && !completed)
                        PillBadge(text: '+${bounty}cc'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: AssigneeBadge(item: item)),
                      const SizedBox(width: 8),
                      _ActivityAction(
                        item: item,
                        onValidate: onValidate,
                        onDelegate: onDelegate,
                        onTakeOver: onTakeOver,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
