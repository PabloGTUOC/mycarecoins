import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/json.dart';
import '../widgets/absence_dialog.dart';
import '../widgets/help_sheet.dart';
import '../widgets/personal_time_dialog.dart';
import '../widgets/coach_marks.dart';
import '../widgets/ui.dart';

/// Wide layout: Task Library side panel (drag source) + 6:00–24:00 hour-grid
/// timeline with chips positioned by start time and sized by duration,
/// overlap offsets, red now-line, drop-to-schedule (30-min snapping) and
/// drag-out-to-unschedule. Narrow layout: timeline list with gap indicators,
/// day-swipe, swipe-to-remove and the task bottom sheet.
class DailyScreen extends StatefulWidget {
  final String? date; // yyyy-MM-dd, defaults to today
  final bool isTab;
  final bool active;
  final ValueChanged<bool>? onNeedsYouChanged;
  final VoidCallback? onOpenWallet;
  final DateTime? now;

  const DailyScreen({
    super.key,
    this.date,
    this.isTab = false,
    this.active = false,
    this.onNeedsYouChanged,
    this.onOpenWallet,
    this.now,
  });

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

const int kStartHour = 6;
const int kTotalHours = 18;
const double kGridHeight = 18 * 64.0;

/// Collapsed height of the phone task tray, as a fraction of the screen: the
/// handle, the header row with "All tasks", and one row of chips.
const double kTrayCollapsed = 0.21;

/// Tray size while a block is dragged, so the grid is free to drop on.
const double kTrayDragging = 0.04;

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

/// Personal time (category 'self') can only be cancelled by the person taking it
/// (assigned_to == current user), whatever their role. A coverage shift (type
/// 'coverage') can never be removed on its own by anyone; it ends only when its
/// personal time is cancelled.
bool canRemoveActivity(Map<String, dynamic> a, AppState app) {
  if (a['type'] == 'coverage') return false;
  if (isSelfActivity(a)) {
    return a['assigned_to']?.toString() == app.userId?.toString();
  }
  return a['assigned_to']?.toString() == app.userId?.toString() ||
      app.isCaregiver;
}

bool canMoveActivity(Map<String, dynamic> a, AppState app) {
  if (a['type'] == 'coverage') return false;
  final status = a['status']?.toString() ?? 'pending';
  if (status != 'approved') return false;
  final mine = a['assigned_to']?.toString() == app.userId?.toString();
  if (isSelfActivity(a)) {
    if (!mine) return false;
    if (a['counterpart_activity_id'] != null) return false;
    return true;
  }
  if (!mine && !app.isCaregiver) return false;
  return true;
}

class _DailyScreenState extends State<DailyScreen> {
  List<Map<String, dynamic>> _activities = [];
  List<Map<String, dynamic>> _absences = [];
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _pendingMembers = [];
  bool _needsYouExpanded = false;
  bool _loading = true;
  bool _error = false;
  late DateTime _day;
  bool _draggingScheduled = false;
  final _gridScroll = ScrollController();
  final _trayController = DraggableScrollableController();
  final _gridStateKey = GlobalKey<_DayHourGridState>();

  final _tourDateKey = GlobalKey();
  final _tourAddKey = GlobalKey();
  final _tourAbsenceKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _day = widget.date != null
        ? DateTime.parse(widget.date!)
        : (widget.now ?? DateTime.now());
    _load();
  }

  @override
  void didUpdateWidget(covariant DailyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.date != oldWidget.date && widget.date != null) {
      final newDay = DateTime.parse(widget.date!);
      if (!_sameDay(_day, newDay)) {
        setState(() {
          _day = newDay;
        });
        _scrollToNow();
      }
    }
    if (widget.active && !oldWidget.active) {
      _load();
    }
  }

  @override
  void dispose() {
    _gridScroll.dispose();
    _trayController.dispose();
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

  bool get _isToday => _sameDay((widget.now ?? DateTime.now()).toLocal(), _day);

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
        if (app.isCaregiver && app.familyId != 0)
          app.api
              .get('/api/dashboard/${app.familyId}')
              .catchError((_) => <String, dynamic>{'members': []})
        else
          Future.value(<String, dynamic>{'members': []}),
      ]);
      final acts = results[0] is List
          ? results[0] as List
          : (results[0]['activities'] as List? ?? []);
      final abs = results[1] is List
          ? results[1] as List
          : (results[1]['absences'] as List? ?? []);
      final dash = results[3] is Map ? results[3] as Map : <String, dynamic>{};
      final membersList = (dash['members'] as List?) ?? [];
      final pendingMems = membersList
          .cast<Map>()
          .map((m) => m.cast<String, dynamic>())
          .where((m) => m['status'] == 'pending')
          .toList();
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
          _pendingMembers = pendingMems;
          _loading = false;
          _error = false;
        });
        final items = _getNeedsItems(app);
        widget.onNeedsYouChanged?.call(items.isNotEmpty);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_gridScroll.hasClients) return;
      if (_isToday && _nowLineTop != null) {
        final target = (_nowLineTop! / 100 * kGridHeight) -
            _gridScroll.position.viewportDimension / 3;
        _gridScroll
            .jumpTo(target.clamp(0.0, _gridScroll.position.maxScrollExtent));
      } else {
        // Other days open at their first activity, an hour above it, so a
        // day whose plans are all in the evening does not open on an empty
        // morning. An empty day opens at kStartHour.
        final starts = _scheduledToday
            .map((a) => DateTime.tryParse(a['starts_at']?.toString() ?? '')
                ?.toLocal())
            .whereType<DateTime>()
            .toList()
          ..sort();
        var target = 0.0;
        if (starts.isNotEmpty) {
          final hour = starts.first.hour + starts.first.minute / 60 - 1;
          target = (hour - kStartHour) / kTotalHours * kGridHeight;
        }
        _gridScroll
            .jumpTo(target.clamp(0.0, _gridScroll.position.maxScrollExtent));
      }
    });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime? _startsAt(Map<String, dynamic> a) =>
      DateTime.tryParse(a['starts_at']?.toString() ?? '')?.toLocal();

  /// Today's scheduled activities, sorted, each annotated with colIndex,
  /// colCount, and gapBeforeMinutes.
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
    var cluster = <Map<String, dynamic>>[];
    DateTime? clusterMaxEnd;

    void processCluster(List<Map<String, dynamic>> cl) {
      if (cl.isEmpty) return;
      final colEndTimes = <DateTime>[];
      for (final a in cl) {
        final start = _startsAt(a)!;
        final durMin = toNum(a['duration_minutes']).toDouble();
        final safeDur = durMin <= 0 ? 30.0 : durMin;
        final end = start.add(Duration(minutes: safeDur.round()));

        int col = -1;
        for (var c = 0; c < colEndTimes.length; c++) {
          if (!start.isBefore(colEndTimes[c])) {
            col = c;
            colEndTimes[c] = end;
            break;
          }
        }
        if (col == -1) {
          col = colEndTimes.length;
          colEndTimes.add(end);
        }
        a['_colIndex'] = col;
      }
      final numCols = colEndTimes.length;
      for (final a in cl) {
        a['_colCount'] = numCols;
        a['_overlapCount'] = a['_colIndex'];
        positioned.add(a);
      }
    }

    for (var i = 0; i < acts.length; i++) {
      final a = Map<String, dynamic>.from(acts[i]);
      final start = _startsAt(a)!;
      final durMin = toNum(a['duration_minutes']).toDouble();
      final safeDur = durMin <= 0 ? 30.0 : durMin;
      final end = start.add(Duration(minutes: safeDur.round()));

      if (cluster.isEmpty) {
        cluster.add(a);
        clusterMaxEnd = end;
      } else {
        if (start.isBefore(clusterMaxEnd!)) {
          cluster.add(a);
          if (end.isAfter(clusterMaxEnd)) {
            clusterMaxEnd = end;
          }
        } else {
          processCluster(cluster);
          cluster = [a];
          clusterMaxEnd = end;
        }
      }
    }
    processCluster(cluster);

    for (var i = 0; i < positioned.length; i++) {
      final a = positioned[i];
      final startA = _startsAt(a)!.millisecondsSinceEpoch;
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
      a['_gapBeforeMinutes'] = gap > 0 ? gap : 0;
    }
    return positioned;
  }

  List<Map<String, dynamic>> get _completedToday =>
      _scheduledToday.where((a) => a['status'] == 'completed').toList();

  num get _todayCoins =>
      _completedToday.fold<num>(0, (sum, a) => sum + toNum(a['coin_value']));

  double? get _nowLineTop {
    final now = (widget.now ?? DateTime.now()).toLocal();
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

  bool get _isPastDay {
    final now = (widget.now ?? DateTime.now()).toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(_day.year, _day.month, _day.day);
    return day.isBefore(today);
  }

  List<Map<String, dynamic>> get _sortedTemplates {
    final counts = <String, int>{};
    for (final a in _activities) {
      if (a['is_template'] == true) continue;
      final title = (a['title'] ?? '').toString();
      if (title.isNotEmpty) {
        counts[title] = (counts[title] ?? 0) + 1;
      }
    }

    final list = List<Map<String, dynamic>>.from(_templates);
    list.sort((a, b) {
      final titleA = (a['title'] ?? '').toString();
      final titleB = (b['title'] ?? '').toString();
      final cA = counts[titleA] ?? 0;
      final cB = counts[titleB] ?? 0;
      if (cA != cB) {
        return cB.compareTo(cA);
      }
      return titleA.toLowerCase().compareTo(titleB.toLowerCase());
    });
    return list;
  }

  bool _isSlotConflicted(DateTime start, DateTime end, AppState app) {
    final now = (widget.now ?? DateTime.now()).toLocal();
    if (start.isBefore(now)) return true;

    final hasAbsence = _dayAbsences.any((abs) {
      if (abs['user_id']?.toString() != app.userId?.toString()) return false;
      final s =
          DateTime.tryParse(abs['start_time']?.toString() ?? '')?.toLocal();
      final e = DateTime.tryParse(abs['end_time']?.toString() ?? '')?.toLocal();
      if (s == null || e == null) return false;
      return s.isBefore(end) && e.isAfter(start);
    });
    if (hasAbsence) return true;

    final hasOverlap = _scheduledToday.any((act) {
      if (act['is_template'] == true) return false;
      if (act['type'] == 'coverage') return false;
      if (act['assigned_to']?.toString() != app.userId?.toString()) {
        return false;
      }
      final status = act['status']?.toString();
      if (status == 'cancelled' || status == 'rejected') return false;

      final s = _startsAt(act);
      if (s == null) return false;
      final dur = toNum(act['duration_minutes']).toInt();
      final safeDur = dur <= 0 ? 30 : dur;
      final e = act['ends_at'] != null
          ? DateTime.tryParse(act['ends_at'].toString())?.toLocal() ??
              s.add(Duration(minutes: safeDur))
          : s.add(Duration(minutes: safeDur));

      return s.isBefore(end) && e.isAfter(start);
    });
    return hasOverlap;
  }

  TimeOfDay _sensibleInitialTime([Map<String, dynamic>? template]) {
    if (!_isToday) {
      return const TimeOfDay(hour: 9, minute: 0);
    }

    final app = context.read<AppState>();
    final now = (widget.now ?? DateTime.now()).toLocal();
    int nextMin = ((now.minute / 15.0).ceil() * 15);
    int nextHour = now.hour;
    if (nextMin >= 60) {
      nextHour += nextMin ~/ 60;
      nextMin = nextMin % 60;
    }
    if (nextHour < kStartHour) {
      nextHour = kStartHour;
      nextMin = 0;
    }

    final durMin =
        template != null ? toNum(template['duration_minutes']).toInt() : 30;
    final safeDur = durMin <= 0 ? 30 : durMin;

    var candidate =
        DateTime(_day.year, _day.month, _day.day, nextHour, nextMin);
    while (candidate.hour < 24) {
      final candEnd = candidate.add(Duration(minutes: safeDur));
      if (!_isSlotConflicted(candidate, candEnd, app)) {
        return TimeOfDay(hour: candidate.hour, minute: candidate.minute);
      }
      candidate = candidate.add(const Duration(minutes: 15));
    }

    return TimeOfDay(hour: nextHour.clamp(kStartHour, 23), minute: nextMin);
  }

  void _selectDay(DateTime day) {
    setState(() {
      _day = DateTime(day.year, day.month, day.day);
      _needsYouExpanded = false;
    });
    if (_trayController.isAttached && _trayController.size > kTrayCollapsed) {
      _trayController.jumpTo(kTrayCollapsed);
    }
    _scrollToNow();
  }

  void _changeDay(int delta) {
    _selectDay(DateTime(_day.year, _day.month, _day.day + delta));
  }

  void _changeWeek(int delta) {
    _selectDay(DateTime(_day.year, _day.month, _day.day + delta * 7));
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

  Future<void> _approveMember(dynamic userId) async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    await app.runAction(() async {
      await app.api
          .post('/api/families/${app.familyId}/members/$userId/approve');
      await _load();
    }, l.toastMemberApproved);
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

  bool _canRemoveActivity(Map<String, dynamic> a, {AppState? appState}) {
    final app = appState ?? context.read<AppState>();
    return canRemoveActivity(a, app);
  }

  bool _canMoveActivity(Map<String, dynamic> a, {AppState? appState}) {
    final app = appState ?? context.read<AppState>();
    return canMoveActivity(a, app);
  }

  /// Accepted personal time points at its coverage shift.
  bool _hasCounterpart(Map<String, dynamic> a) =>
      a['counterpart_activity_id'] != null;

  Future<void> _removeFlow(Map<String, dynamic> a) async {
    final app = context.read<AppState>();
    if (!_canRemoveActivity(a, appState: app)) return;

    if (isSelfActivity(a)) {
      if (_hasCounterpart(a)) {
        final l = AppLocalizations.of(context);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg)),
            title: Text(
                (a['title'] ?? '').toString().isNotEmpty
                    ? (a['title'] ?? '').toString()
                    : l.personalTimeEntry,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            content: Text(
              l.cancelPersonalTimeWithCoverage,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l.cancel)),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(l.remove,
                      style: const TextStyle(color: AppColors.danger))),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      await _unschedule(a['id'], series: false);
      return;
    }

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
    final h = (hour ?? DateTime.now().hour).clamp(kStartHour, 23);
    final m = (minute ?? (DateTime.now().minute >= 30 ? 30 : 0)) >= 30 ? 30 : 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
    );
    if (picked == null) return;
    await _confirmSchedule(
        activity['id'], DateTime(_day.year, _day.month, _day.day, picked.hour, picked.minute));
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

  Future<void> _scheduleImmediately(
      Map<String, dynamic> template, DateTime startsAt) async {
    if (!mounted) return;
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final templateId = template['id'];
    final title = (template['title'] ?? '').toString();

    // Block scheduling inside your own absence (matches _confirmSchedule)
    final durMin = toNum(template['duration_minutes']).toInt();
    final safeDur = durMin <= 0 ? 30 : durMin;
    final activityEnd = startsAt.add(Duration(minutes: safeDur));

    final overlapsAbsence = _dayAbsences.any((abs) {
      if (abs['user_id']?.toString() != app.userId?.toString()) return false;
      final s =
          DateTime.tryParse(abs['start_time']?.toString() ?? '')?.toLocal();
      final e = DateTime.tryParse(abs['end_time']?.toString() ?? '')?.toLocal();
      if (s == null || e == null) return false;
      return s.isBefore(activityEnd) && e.isAfter(startsAt);
    });
    if (overlapsAbsence) {
      app.setError(l.errScheduleDuringAbsence);
      return;
    }

    try {
      final res = await app.api.post(
        '/api/activities/$templateId/schedule',
        {'startsAt': startsAt.toUtc().toIso8601String()},
      );
      await _load();

      // POST /schedule answers { activity: {...}, warning }.
      final created = (res is Map) ? res['activity'] : null;
      final newId = (created is Map) ? created['id'] : null;
      final timeStr = DateFormat('HH:mm').format(startsAt);
      final msg = l.scheduledAtTime(title, timeStr);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            action: newId != null
                ? SnackBarAction(
                    label: l.actionUndo,
                    onPressed: () async {
                      try {
                        await app.api.delete('/api/activities/$newId');
                        await _load();
                      } catch (_) {}
                    },
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = app.errorTextFor(e);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    }
  }

  Future<void> _onTapTrayChip(Map<String, dynamic> template) async {
    if (_isPastDay) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).dayHasPassed)),
      );
      return;
    }

    final initial = _sensibleInitialTime(template);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;

    final startsAt =
        DateTime(_day.year, _day.month, _day.day, picked.hour, picked.minute);
    await _scheduleImmediately(template, startsAt);
  }

  Future<void> _onTapTimeForMe() async {
    if (_isPastDay) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).dayHasPassed)),
      );
      return;
    }

    final initial = _sensibleInitialTime();
    final start =
        DateTime(_day.year, _day.month, _day.day, initial.hour, initial.minute);
    await _openPersonalTime(null, start);
  }

  /// Drop on the hour grid: snapped to 15 minutes.
  void _onGridDrop(Map<String, dynamic> payload, double localDy) {
    final pct = (localDy / kGridHeight).clamp(0.0, 1.0);
    var h = kStartHour + pct * kTotalHours;
    h = ((h * 4).round() / 4.0).clamp(kStartHour.toDouble(), 23.75);
    final hour = h.floor();
    final minute = ((h - hour) * 60).round();
    final startsAt = DateTime(_day.year, _day.month, _day.day, hour, minute);

    final activity = payload['activity'] as Map<String, dynamic>;
    if (payload['type'] == 'template') {
      if (isWideLayout(context)) {
        _openScheduleDialog(activity, hour: hour, minute: minute);
      } else {
        _scheduleImmediately(activity, startsAt);
      }
    } else if (payload['type'] == 'scheduled') {
      _moveActivity(activity, startsAt);
    }
  }

  Future<void> _moveActivity(
      Map<String, dynamic> a, DateTime startsAt) async {
    if (!mounted) return;
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final actId = a['id'];
    final rawTitle = (a['title'] ?? '').toString();
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : (isSelfActivity(a) ? l.personalTimeEntry : '');
    final oldStart = _startsAt(a);

    try {
      await app.api.patch(
        '/api/activities/$actId/time',
        {'startsAt': startsAt.toUtc().toIso8601String()},
      );
      await _load();

      final timeStr = DateFormat('HH:mm').format(startsAt);
      final msg = l.scheduledAtTime(title, timeStr);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            action: oldStart != null
                ? SnackBarAction(
                    label: l.actionUndo,
                    onPressed: () async {
                      try {
                        await app.api.patch(
                          '/api/activities/$actId/time',
                          {'startsAt': oldStart.toUtc().toIso8601String()},
                        );
                        await _load();
                      } catch (e) {
                        if (mounted) {
                          final undoErr = app.errorTextFor(e);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(undoErr)),
                          );
                        }
                      }
                    },
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errMsg = app.errorTextFor(e);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errMsg)),
        );
      }
    }
  }

  Future<void> _moveViaTimePicker(Map<String, dynamic> a) async {
    final current = _startsAt(a) ?? DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    final newStart =
        DateTime(_day.year, _day.month, _day.day, picked.hour, picked.minute);
    await _moveActivity(a, newStart);
  }

  void _handleGridTap(double localDy) {
    final now = widget.now ?? DateTime.now();
    final isPastDay = _day.year < now.year ||
        (_day.year == now.year && _day.month < now.month) ||
        (_day.year == now.year && _day.month == now.month && _day.day < now.day);
    if (isPastDay) return;

    final pct = (localDy / kGridHeight).clamp(0.0, 1.0);
    var h = kStartHour + pct * kTotalHours;
    h = (h * 4).floor() / 4.0;
    h = h.clamp(kStartHour.toDouble(), 23.75);
    final hour = h.floor();
    final minute = ((h - hour) * 60).round();
    final slotStart = DateTime(_day.year, _day.month, _day.day, hour, minute);

    final isToday = _day.year == now.year &&
        _day.month == now.month &&
        _day.day == now.day;
    if (isToday && slotStart.isBefore(now)) return;

    _openQuickAddSheet(slotStart);
  }

  Future<void> _openQuickAddSheet(DateTime slotStart) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _QuickAddSheet(
        startsAt: slotStart,
        templates: _sortedTemplates,
        onTapTemplate: (template) {
          Navigator.pop(ctx);
          _scheduleImmediately(template, slotStart);
        },
        onTapTimeForMe: () {
          Navigator.pop(ctx);
          _openPersonalTime(null, slotStart);
        },
      ),
    );
  }

  Future<void> _openActivitySheet(Map<String, dynamic> a) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ActivityDetailsSheet(
        activity: a,
        onValidate: () {
          Navigator.pop(ctx);
          _validate(a['id']);
        },
        onDelegate: () {
          Navigator.pop(ctx);
          _openBountyDialog(a);
        },
        onTakeOver: () {
          Navigator.pop(ctx);
          _acceptBounty(a);
        },
        onRepeat: () {
          Navigator.pop(ctx);
          _openRecurrenceDialog(a);
        },
        onMove: () {
          Navigator.pop(ctx);
          _moveViaTimePicker(a);
        },
        onRemove: () {
          Navigator.pop(ctx);
          _removeFlow(a);
        },
      ),
    );
  }

  Future<void> _openScheduleSheet() async {
    if (isWideLayout(context)) return;
    if (_trayController.isAttached) {
      await _trayController.animateTo(
        0.7,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wide = isWideLayout(context);
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    final items = _scheduledToday;
    final done = _completedToday.length;

    final app = context.watch<AppState>();
    final family = app.family;
    final alias =
        (family?['alias'] ?? app.profile?['display_name'] ?? 'C').toString();
    final balance = family?['coin_balance']?.toString() ?? '0';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: wide ? AppColors.bg : null,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: !widget.isTab,
        titleSpacing: 0,
        title: Row(
          children: [
            if (wide) ...[
              const SizedBox(width: 4),
              Text(l.dailyTitle,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
            ],
            const Spacer(),
            IconButton(
                onPressed: () => _changeDay(-1),
                tooltip: l.prevDay,
                visualDensity: VisualDensity.compact,
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
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded)),
            const Spacer(),
          ],
        ),
        actions: [
          if (!wide) ...[
            IconButton(
              onPressed: () => showHelpSheet(context),
              tooltip: l.helpTooltip,
              icon: const Icon(Icons.help_outline_rounded,
                  size: 22, color: AppColors.textSecondary),
            ),
            if (app.hasFamilies)
              CoinBalancePill(
                alias: alias,
                balance: balance,
                onTap: widget.onOpenWallet,
              ),
            PopupMenuButton<String>(
              key: _tourAbsenceKey,
              tooltip: l.timeOffLong,
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) {
                if (v == 'time_off') _openAbsenceDialog();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'time_off',
                  child: Row(
                    children: [
                      const Icon(Icons.flight_takeoff_rounded,
                          size: 20, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(l.timeOffLong),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ] else ...[
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
        ],
      ),
      // No FAB on phones: the tray is the way to add, and a floating button
      // sat on top of its chips. "All tasks" in the tray header expands it.
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error && _activities.isEmpty
              ? LoadErrorState(onRetry: () {
                  setState(() => _loading = true);
                  _load();
                })
              : Column(
                  children: [
                    if (!wide)
                      WeekStrip(
                        selectedDay: _day,
                        onSelectDay: _selectDay,
                        onWeekChange: _changeWeek,
                        today: widget.now,
                      ),
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

  // ── Needs you ────────────────────────────────────────────────────

  List<_NeedsItem> _getNeedsItems(AppState app) {
    final items = <_NeedsItem>[];

    // 1. Validations they can give (pending_validation, not theirs, user is caregiver)
    if (app.isCaregiver) {
      for (final a in _activities) {
        if (a['is_template'] == true) continue;
        if (a['status'] == 'pending_validation' &&
            a['assigned_to']?.toString() != app.userId?.toString()) {
          items.add(_NeedsValidation(a));
        }
      }
    }

    // 2. Cover requests asked of them or of anyone (status pending, not their own)
    for (final r in _requests) {
      if (r['status'] == 'pending' &&
          r['requester_id']?.toString() != app.userId?.toString()) {
        final reqOf = r['requested_of'];
        if (reqOf == null || reqOf.toString() == app.userId?.toString()) {
          items.add(_NeedsCoverRequest(r));
        }
      }
    }

    // 3. Pending member approvals (caregivers only)
    if (app.isCaregiver) {
      for (final m in _pendingMembers) {
        if (m['status'] == 'pending') {
          items.add(_NeedsMemberApproval(m));
        }
      }
    }

    // 4. Open offers they could take (caregivers only, bounty > 0, not completed/rejected, not mine)
    if (app.isCaregiver) {
      for (final a in _activities) {
        if (a['is_template'] == true) continue;
        // A coverage shift's bounty is the requester's sweetener, not an offer.
        if (a['type'] == 'coverage' || isSelfActivity(a)) continue;
        if (toNum(a['bounty_amount']) > 0 &&
            a['status'] != 'completed' &&
            a['status'] != 'rejected' &&
            a['status'] != 'cancelled' &&
            a['status'] != 'pending_validation' &&
            a['assigned_to']?.toString() != app.userId?.toString()) {
          items.add(_NeedsTakeOverOffer(a));
        }
      }
    }

    return items;
  }

  String _needsItemLabel(_NeedsItem item, AppLocalizations l) {
    switch (item) {
      case _NeedsValidation(:final activity):
        final title = (activity['title'] ?? '').toString();
        final assignee = (activity['assigned_alias'] ??
                activity['assigned_to_name'] ??
                '')
            .toString()
            .trim();
        return assignee.isNotEmpty
            ? l.needsValidateTask(title, assignee)
            : l.needsValidateTaskNoAssignee(title);

      case _NeedsCoverRequest(:final request):
        final name = (request['requester_name'] ?? '').toString().trim();
        final title = (request['title'] ?? '').toString();
        return l.needsCoverRequest(
            name.isNotEmpty ? name : l.fallbackACaregiver, title);

      case _NeedsMemberApproval(:final member):
        final name = (member['name'] ??
                l.fallbackUser(
                    (member['user_id'] ?? member['id'] ?? '').toString()))
            .toString();
        return l.needsApproveMember(name);

      case _NeedsTakeOverOffer(:final activity):
        final title = (activity['title'] ?? '').toString();
        final bounty = toNum(activity['bounty_amount']).toInt();
        return l.needsTakeOverOffer(title, bounty);
    }
  }

  Widget _buildNeedsYou(AppLocalizations l, {required bool isNarrow}) {
    final app = context.watch<AppState>();
    final items = _getNeedsItems(app);
    if (items.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                size: 18, color: AppColors.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.needsYouEmpty,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isNarrow && !_needsYouExpanded) {
      final firstLabel = _needsItemLabel(items.first, l);
      final collapsedText = items.length == 1
          ? firstLabel
          : l.needsYouFolded(firstLabel, items.length - 1);

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: () => setState(() => _needsYouExpanded = true),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.pending_actions_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    collapsedText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l.dashTitle,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onPressed: () => setState(() => _needsYouExpanded = true),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.needsYouTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (isNarrow)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    onPressed: () => setState(() => _needsYouExpanded = false),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(
                  height: 1, indent: 16, endIndent: 16, color: AppColors.border),
            _buildNeedsYouItem(items[i], l),
          ],
        ],
      ),
    );
  }

  Widget _buildNeedsYouItem(_NeedsItem item, AppLocalizations l) {
    final label = _needsItemLabel(item, l);
    switch (item) {
      case _NeedsValidation(:final activity):
        final coins = toNum(activity['coin_value']).toInt();
        return _NeedsRow(
          icon: Icons.verified_outlined,
          iconColor: AppColors.primary,
          iconBg: AppColors.primarySoft,
          label: label,
          badge: coins > 0 ? '+${coins}cc' : null,
          badgeColor: AppColors.primaryInk,
          badgeBg: AppColors.primarySoft,
          actionLabel: l.pillValidate,
          onTap: () => _validate(activity['id']),
        );

      case _NeedsCoverRequest(:final request):
        final sweetener = toNum(request['sweetener_coins']).toInt();
        return _NeedsRow(
          icon: Icons.swap_horiz_rounded,
          iconColor: AppColors.warning,
          iconBg: AppColors.warningSoft,
          label: label,
          badge: sweetener > 0 ? '+${sweetener}cc' : null,
          badgeColor: AppColors.warningInk,
          badgeBg: AppColors.warningSoft,
          actionLabel: l.acceptAction,
          onTap: () => _openRequest(request),
        );

      case _NeedsMemberApproval(:final member):
        return _NeedsRow(
          icon: Icons.person_add_outlined,
          iconColor: AppColors.indigo,
          iconBg: AppColors.primarySoft,
          label: label,
          badge: null,
          actionLabel: l.approve,
          onTap: () => _approveMember(member['user_id'] ?? member['id']),
        );

      case _NeedsTakeOverOffer(:final activity):
        final bounty = toNum(activity['bounty_amount']).toInt();
        return _NeedsRow(
          icon: Icons.bolt_rounded,
          iconColor: AppColors.success,
          iconBg: AppColors.successSoft,
          label: label,
          badge: '+$bounty cc',
          badgeColor: AppColors.successInk,
          badgeBg: AppColors.successSoft,
          actionLabel: l.takeOver,
          onTap: () => _acceptBounty(activity),
        );
    }
  }

  // ── Wide: Task Library panel + hour grid ────────────────────────

  Widget _buildWide(List<Map<String, dynamic>> items) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNeedsYou(l, isNarrow: false),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 300,
                  child: DragTarget<Map<String, dynamic>>(
                    onWillAcceptWithDetails: (d) =>
                        d.data['type'] == 'scheduled' &&
                        _canRemoveActivity(
                            d.data['activity'] as Map<String, dynamic>),
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
                                      size: 34, color: AppColors.dangerInk),
                                  const SizedBox(height: 8),
                                  Text(
                                    AppLocalizations.of(context)
                                        .dropToUnschedule,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.dangerInk,
                                    ),
                                  ),
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
                    child: _DayHourGrid(
                      items: items,
                      absences: _dayAbsences,
                      requests: _dayRequests,
                      day: _day,
                      now: widget.now,
                      isToday: _isToday,
                      nowLineTop: _nowLineTop,
                      isNarrow: false,
                      scrollController: _gridScroll,
                      onRefresh: _load,
                      onGridDrop: _onGridDrop,
                      onDoubleTap: (dy) => _openPersonalTime(dy),
                      onAbsenceTap: _absenceDetail,
                      onRequestTap: _openRequest,
                      onValidate: _validate,
                      onBounty: _openBountyDialog,
                      onTakeOver: _acceptBounty,
                      onRecurrence: _openRecurrenceDialog,
                      onCompletedInfo: _showCompletedLockedDialog,
                      canRemove: (a) => _canRemoveActivity(a),
                      canMove: (a) => _canMoveActivity(a),
                      onGridTap: _handleGridTap,
                      onActivityTap: _openActivitySheet,
                      onDragStarted: () =>
                          setState(() => _draggingScheduled = true),
                      onDragEnd: () =>
                          setState(() => _draggingScheduled = false),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Narrow: shared hour grid + folded Needs you ──────────────────

  Widget _buildNarrow(List<Map<String, dynamic>> items) {
    final l = AppLocalizations.of(context);
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildNeedsYou(l, isNarrow: true),
            ),
            Expanded(
              child: _DayHourGrid(
                key: _gridStateKey,
                items: items,
                absences: _dayAbsences,
                requests: _dayRequests,
                day: _day,
                now: widget.now,
                isToday: _isToday,
                nowLineTop: _nowLineTop,
                isNarrow: true,
                scrollController: _gridScroll,
                onRefresh: _load,
                onGridDrop: _onGridDrop,
                onDoubleTap: (dy) => _openPersonalTime(dy),
                onGridTap: _handleGridTap,
                onActivityTap: _openActivitySheet,
                onAbsenceTap: _absenceDetail,
                onRequestTap: _openRequest,
                onValidate: _validate,
                onBounty: _openBountyDialog,
                onTakeOver: _acceptBounty,
                onRecurrence: _openRecurrenceDialog,
                onCompletedInfo: _showCompletedLockedDialog,
                canRemove: (a) => _canRemoveActivity(a),
                canMove: (a) => _canMoveActivity(a),
                onDragStarted: () {
                  HapticFeedback.selectionClick();
                  if (_trayController.isAttached) {
                    _trayController.jumpTo(kTrayDragging);
                  }
                  setState(() => _draggingScheduled = true);
                },
                onDragEnd: () {
                  _gridStateKey.currentState?.clearHover();
                  if (_trayController.isAttached) {
                    _trayController.animateTo(
                      kTrayCollapsed,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                  }
                  setState(() => _draggingScheduled = false);
                },
              ),
            ),
          ],
        ),
        _TaskTray(
          controller: _trayController,
          templates: _sortedTemplates,
          isPastDay: _isPastDay,
          onTapChip: _onTapTrayChip,
          onTapTimeForMe: _onTapTimeForMe,
          onExpand: _openScheduleSheet,
          expandKey: _tourAddKey,
          onDragStarted: () {
            HapticFeedback.selectionClick();
            if (_trayController.isAttached) {
              _trayController.jumpTo(kTrayDragging);
            }
          },
          onDragEnd: () {
            _gridStateKey.currentState?.clearHover();
            if (_trayController.isAttached) {
              _trayController.animateTo(
                kTrayCollapsed,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          },
        ),
      ],
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color)),
      );
      if (onTap == null) return w;
      // Pad the tap area toward the 44dp guideline without growing the
      // visual pill; the compact grid chips have no vertical room to spare.
      return Semantics(
        button: true,
        label: text,
        child: Tappable(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: compact
              ? ExcludeSemantics(child: w)
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                  child: ExcludeSemantics(child: w)),
        ),
      );
    }

    // Personal time is nobody's to validate, delegate or take over; its own
    // accept/decline flow arrives with the requests (plan Phase 5).
    if (isSelfActivity(item)) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);
    if (status == 'pending_validation') {
      return (!mine && app.isCaregiver)
          ? pill(l.pillValidate, AppColors.primaryInk, AppColors.primarySoft,
              onValidate)
          : pill(l.pillAwaiting, AppColors.warningInk, AppColors.warningSoft);
    }
    if (status == 'completed') {
      return pill(l.pillDone, Colors.white, Colors.black26);
    }
    if (status == 'rejected') {
      return pill(l.pillRejected, AppColors.dangerInk, AppColors.dangerSoft);
    }
    // pending / approved
    // Coverage is an agreement to cover one person's time, and its bounty
    // fields hold their sweetener: never delegated, never taken over.
    if (item['type'] == 'coverage') return const SizedBox.shrink();
    if (mine && bounty == 0 && app.isCaregiver) {
      return pill(
          l.pillDelegate, AppColors.warningInk, AppColors.warningSoft, onDelegate);
    }
    if (mine && bounty > 0) {
      return pill(
          l.pillOffering('$bounty'), AppColors.warningInk, AppColors.warningSoft);
    }
    if (!mine && bounty > 0 && app.isCaregiver) {
      return pill(l.pillTakeOver('$bounty'), AppColors.successInk,
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

String _activityTypeName(AppLocalizations l, Map<String, dynamic> item) {
  if (isSelfActivity(item)) {
    return personalTimeTypeLabel(l, item['type']?.toString() ?? '');
  }
  return switch (item['type']) {
    'coverage' => l.a11yTypeCoverage,
    'care' => l.a11yTypeCare,
    _ => l.a11yTypeHousehold,
  };
}

String _activityStatusLabel(AppLocalizations l, String? status) => switch (status) {
      'completed' => l.statusCompleted,
      'approved' => l.statusApproved,
      'pending_validation' => l.statusPendingValidation,
      'rejected' => l.statusRejected,
      _ => l.statusPending,
    };

String _activitySemanticsLabel({
  required AppLocalizations l,
  required Map<String, dynamic> item,
  required AppState app,
}) {
  final parts = <String>[];
  final title = (item['title'] ?? '').toString().trim();
  if (title.isNotEmpty) parts.add(title);

  final typeName = _activityTypeName(l, item);
  if (typeName.isNotEmpty) parts.add(typeName);

  final ts = DateTime.tryParse(item['starts_at']?.toString() ?? '')?.toLocal();
  final durMin = toNum(item['duration_minutes']).toInt();
  final end = item['ends_at'] != null
      ? DateTime.tryParse(item['ends_at'].toString())?.toLocal()
      : ts?.add(Duration(minutes: durMin));

  if (ts != null && end != null) {
    parts.add(l.a11yTimeRange(
      DateFormat('HH:mm').format(ts),
      DateFormat('HH:mm').format(end),
    ));
  } else if (ts != null) {
    parts.add(DateFormat('HH:mm').format(ts));
  }

  final mine = item['assigned_to']?.toString() == app.userId?.toString();
  final name = (item['assigned_alias'] ?? item['assigned_to_name'] ?? '')
      .toString()
      .trim();
  final assignee = mine ? l.assigneeYou : name;
  if (assignee.isNotEmpty) parts.add(assignee);

  if (!isSelfActivity(item)) {
    final coins = toNum(item['coin_value']).toInt();
    parts.add(l.a11yCoins(coins));
  }

  final status = item['status']?.toString();
  parts.add(_activityStatusLabel(l, status));

  return parts.join(', ');
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
                                fontSize: 12,
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
                        fontSize: 12, color: AppColors.textSecondary)),
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

class _TaskTray extends StatefulWidget {
  final DraggableScrollableController controller;
  final List<Map<String, dynamic>> templates;
  final bool isPastDay;
  final ValueChanged<Map<String, dynamic>> onTapChip;
  final VoidCallback onTapTimeForMe;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;
  final VoidCallback onExpand;
  final Key? expandKey;

  const _TaskTray({
    required this.controller,
    required this.templates,
    required this.isPastDay,
    required this.onTapChip,
    required this.onTapTimeForMe,
    required this.onDragStarted,
    required this.onDragEnd,
    required this.onExpand,
    this.expandKey,
  });

  @override
  State<_TaskTray> createState() => _TaskTrayState();
}

class _TaskTrayState extends State<_TaskTray> {
  final _search = TextEditingController();
  int _filter = 0;
  bool _isDragging = false;
  bool _wasExpanded = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _handleDragStarted() {
    setState(() {
      _isDragging = true;
      _wasExpanded =
          (widget.controller.isAttached ? widget.controller.size : kTrayCollapsed) > 0.25;
    });
    widget.onDragStarted();
  }

  void _handleDragEnd() {
    setState(() {
      _isDragging = false;
    });
    widget.onDragEnd();
  }

  Widget _buildTrayChip(Map<String, dynamic> t, AppLocalizations l) {
    final title = (t['title'] ?? '').toString();
    final isCare = t['type'] == 'care';
    final coins = toNum(t['coin_value']).toInt();

    final chipWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(isCare ? '❤️' : '🍽️', style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (coins > 0) ...[
            const SizedBox(width: 6),
            Text(
              '🪙 ${coins}cc',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );

    final semanticsLabel = l.trayChipSemantics(title);

    final interactive = Semantics(
      button: true,
      label: semanticsLabel,
      child: Tappable(
        onTap: () => widget.onTapChip(t),
        child: chipWidget,
      ),
    );

    if (widget.isPastDay) {
      return interactive;
    }

    return touchAwareDraggable(
      data: {'type': 'template', 'activity': t},
      onDragStarted: _handleDragStarted,
      onDragEnd: (_) => _handleDragEnd(),
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.9,
          child: chipWidget,
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: chipWidget,
      ),
      child: interactive,
    );
  }

  Widget _buildExpandedTaskRow(Map<String, dynamic> t, AppLocalizations l) {
    final title = (t['title'] ?? '').toString();
    final isCare = t['type'] == 'care';
    final coins = toNum(t['coin_value']).toInt();

    final rowWidget = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
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
              color: isCare ? AppColors.successSoft : AppColors.warningSoft,
              shape: BoxShape.circle,
            ),
            child: Text(isCare ? '❤️' : '🍽️', style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                Text(
                  '${isCare ? l.filterCare : l.filterHousehold}'
                  '${coins > 0 ? ' · 🪙 ${coins}cc' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(Icons.drag_indicator_rounded, size: 18, color: AppColors.inputBorder),
        ],
      ),
    );

    final semanticsLabel = l.trayChipSemantics(title);

    final interactive = Semantics(
      button: true,
      label: semanticsLabel,
      child: Tappable(
        onTap: () => widget.onTapChip(t),
        child: rowWidget,
      ),
    );

    if (widget.isPastDay) {
      return interactive;
    }

    return touchAwareDraggable(
      data: {'type': 'template', 'activity': t},
      onDragStarted: _handleDragStarted,
      onDragEnd: (_) => _handleDragEnd(),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 280,
          child: Opacity(opacity: 0.9, child: rowWidget),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: rowWidget),
      child: interactive,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return DraggableScrollableSheet(
      controller: widget.controller,
      initialChildSize: kTrayCollapsed,
      minChildSize: 0.04,
      maxChildSize: 0.7,
      snap: true,
      snapSizes: [0.04, kTrayCollapsed, 0.7],
      builder: (context, scrollController) {
        return ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final size = widget.controller.isAttached
                ? widget.controller.size
                : kTrayCollapsed;
            final isExpanded = _isDragging ? _wasExpanded : size > 0.25;
            final isCollapsed = !isExpanded;

            final q = _search.text.trim().toLowerCase();
            final filtered = widget.templates.where((t) {
              if (_filter == 1 && t['type'] != 'care') return false;
              if (_filter == 2 && t['type'] != 'household') return false;
              if (q.isNotEmpty &&
                  !(t['title']?.toString().toLowerCase().contains(q) ?? false)) {
                return false;
              }
              return true;
            }).toList();

            if (isCollapsed &&
                scrollController.hasClients &&
                scrollController.offset != 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (scrollController.hasClients &&
                    scrollController.offset != 0) {
                  scrollController.jumpTo(0.0);
                }
              });
            }

            return Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                physics: isCollapsed
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Centered drag handle
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      if (isCollapsed) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.trayHeaderLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              key: widget.expandKey,
                              onPressed: widget.onExpand,
                              icon: const Icon(Icons.expand_less_rounded,
                                  size: 18),
                              label: Text(l.trayAllTasks),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final t in widget.templates) ...[
                                _buildTrayChip(t, l),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: l.searchTasks,
                            isDense: true,
                            filled: true,
                            fillColor: AppColors.bg,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 9),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadii.pill),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadii.pill),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SegmentedTabs(
                          tabs: [l.filterAll, l.filterCare, l.filterHousehold],
                          selected: _filter,
                          onChanged: (i) => setState(() => _filter = i),
                        ),
                        const SizedBox(height: 12),
                        // "Time for me" as first row
                        Semantics(
                          button: true,
                          label: l.timeForMe,
                          child: Tappable(
                            onTap: widget.onTapTimeForMe,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.primarySoft,
                                borderRadius:
                                    BorderRadius.circular(AppRadii.md),
                                border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Text('🧘',
                                      style: TextStyle(fontSize: 18)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      l.timeForMe,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded,
                                      size: 20, color: AppColors.primary),
                                ],
                              ),
                            ),
                          ),
                        ),
                        for (final t in filtered) _buildExpandedTaskRow(t, l),
                        if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                l.noTasksFiltered,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  static const double strokeWidth = 1.5;
  static const double dash = 5.0;
  static const double gap = 3.0;

  _DashedBorderPainter({
    required this.color,
    this.radius = 8.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashedPath = Path();

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final length = (distance + dash < metric.length)
            ? dash
            : metric.length - distance;
        dashedPath.addPath(
          metric.extractPath(distance, distance + length),
          Offset.zero,
        );
        distance += dash + gap;
      }
    }
    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}

class _DayHourGrid extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> absences;
  final List<Map<String, dynamic>> requests;
  final DateTime day;
  final DateTime? now;
  final bool isToday;
  final double? nowLineTop;
  final bool isNarrow;
  final ScrollController scrollController;
  final RefreshCallback onRefresh;
  final void Function(Map<String, dynamic> data, double dy) onGridDrop;
  final void Function(double dy) onDoubleTap;
  final void Function(double dy)? onGridTap;
  final void Function(Map<String, dynamic> a)? onActivityTap;
  final void Function(Map<String, dynamic> abs) onAbsenceTap;
  final void Function(Map<String, dynamic> req) onRequestTap;
  final void Function(dynamic id) onValidate;
  final void Function(Map<String, dynamic> a) onBounty;
  final void Function(Map<String, dynamic> a) onTakeOver;
  final void Function(Map<String, dynamic> a) onRecurrence;
  final VoidCallback onCompletedInfo;
  final bool Function(Map<String, dynamic> a) canRemove;
  final bool Function(Map<String, dynamic> a)? canMove;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;

  const _DayHourGrid({
    super.key,
    required this.items,
    required this.absences,
    required this.requests,
    required this.day,
    this.now,
    required this.isToday,
    required this.nowLineTop,
    required this.isNarrow,
    required this.scrollController,
    required this.onRefresh,
    required this.onGridDrop,
    required this.onDoubleTap,
    this.onGridTap,
    this.onActivityTap,
    required this.onAbsenceTap,
    required this.onRequestTap,
    required this.onValidate,
    required this.onBounty,
    required this.onTakeOver,
    required this.onRecurrence,
    required this.onCompletedInfo,
    required this.canRemove,
    this.canMove,
    required this.onDragStarted,
    required this.onDragEnd,
  });

  @override
  State<_DayHourGrid> createState() => _DayHourGridState();
}

class _DayHourGridState extends State<_DayHourGrid> {
  final _gridKey = GlobalKey();
  double _doubleTapDy = 0.0;
  double _tapDy = 0.0;
  Map<String, dynamic>? _hoverTemplate;
  DateTime? _hoverSlotStart;
  DateTime? _hoverSlotEnd;
  String? _refusalReason;
  DateTime? _lastAnnouncedSlot;
  Timer? _autoScrollTimer;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  void clearHover() {
    _stopAutoScroll();
    _clearHover();
  }

  void _clearHover() {
    if (_hoverTemplate != null || _refusalReason != null) {
      setState(() {
        _hoverTemplate = null;
        _hoverSlotStart = null;
        _hoverSlotEnd = null;
        _refusalReason = null;
        _lastAnnouncedSlot = null;
      });
    }
  }

  String? _checkRefusal(
      Map<String, dynamic> candidate, DateTime start, DateTime end,
      {bool isScheduled = false}) {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    final now = (widget.now ?? DateTime.now()).toLocal();

    // 1. Time has passed
    if (start.isBefore(now)) {
      return l.refusalTimePassed;
    }

    final targetUserId = isScheduled
        ? (candidate['assigned_to']?.toString() ?? app.userId?.toString())
        : app.userId?.toString();

    // 2. Target user has an absence then
    final hasAbsence = widget.absences.any((abs) {
      if (abs['user_id']?.toString() != targetUserId) return false;
      final s =
          DateTime.tryParse(abs['start_time']?.toString() ?? '')?.toLocal();
      final e = DateTime.tryParse(abs['end_time']?.toString() ?? '')?.toLocal();
      if (s == null || e == null) return false;
      return s.isBefore(end) && e.isAfter(start);
    });
    if (hasAbsence) {
      return l.refusalUserAbsent;
    }

    // 3. Target user already has a non-coverage activity overlapping window
    final hasOverlap = widget.items.any((act) {
      if (act['is_template'] == true) return false;
      if (act['type'] == 'coverage') return false;
      if (isScheduled && act['id']?.toString() == candidate['id']?.toString()) {
        return false;
      }
      if (act['assigned_to']?.toString() != targetUserId) {
        return false;
      }
      final status = act['status']?.toString();
      if (status == 'cancelled' || status == 'rejected') return false;

      final s = _startsAt(act);
      if (s == null) return false;
      final dur = toNum(act['duration_minutes']).toInt();
      final safeDur = dur <= 0 ? 30 : dur;
      final e = act['ends_at'] != null
          ? DateTime.tryParse(act['ends_at'].toString())?.toLocal() ??
              s.add(Duration(minutes: safeDur))
          : s.add(Duration(minutes: safeDur));

      return s.isBefore(end) && e.isAfter(start);
    });
    if (hasOverlap) {
      return l.refusalAlreadyBusy;
    }

    return null;
  }

  /// A scheduled block lands on the grid only if it may be moved; on wide
  /// layouts a remove-only block is still draggable, to the unschedule panel.
  bool _canMoveHere(Map<String, dynamic> data) =>
      data['type'] != 'scheduled' ||
      canMoveActivity(
          data['activity'] as Map<String, dynamic>, context.read<AppState>());

  void _updateHover(Map<String, dynamic> data, Offset globalOffset) {
    if (data['type'] != 'template' && data['type'] != 'scheduled') {
      _clearHover();
      return;
    }

    final template = data['activity'] as Map<String, dynamic>;
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalOffset);

    final pct = (local.dy / kGridHeight).clamp(0.0, 1.0);
    var h = kStartHour + pct * kTotalHours;
    h = ((h * 4).round() / 4.0).clamp(kStartHour.toDouble(), 23.75);
    final hour = h.floor();
    final minute = ((h - hour) * 60).round();

    final slotStart = DateTime(
        widget.day.year, widget.day.month, widget.day.day, hour, minute);
    final durMin = toNum(template['duration_minutes']).toInt();
    final safeDur = durMin <= 0 ? 30 : durMin;
    final slotEnd = slotStart.add(Duration(minutes: safeDur));

    final isScheduled = data['type'] == 'scheduled';
    final refusal = _checkRefusal(template, slotStart, slotEnd,
        isScheduled: isScheduled);

    if (_hoverSlotStart != slotStart ||
        _hoverTemplate != template ||
        _refusalReason != refusal) {
      setState(() {
        _hoverTemplate = template;
        _hoverSlotStart = slotStart;
        _hoverSlotEnd = slotEnd;
        _refusalReason = refusal;
      });

      if (_lastAnnouncedSlot != slotStart) {
        _lastAnnouncedSlot = slotStart;
        final l = AppLocalizations.of(context);
        final rangeStr = l.a11yTimeRange(
          DateFormat('HH:mm').format(slotStart),
          DateFormat('HH:mm').format(slotEnd),
        );
        try {
          final view = View.of(context);
          SemanticsService.sendAnnouncement(
              view, rangeStr, ui.TextDirection.ltr);
        } catch (_) {
          // ignore: deprecated_member_use
          SemanticsService.announce(rangeStr, ui.TextDirection.ltr);
        }
      }
    }

    _handleAutoScroll(globalOffset);
  }

  void _handleAutoScroll(Offset globalOffset) {
    final viewportBox = context.findRenderObject() as RenderBox?;
    if (viewportBox == null) return;
    final local = viewportBox.globalToLocal(globalOffset);
    const threshold = 48.0;

    if (local.dy < threshold) {
      _startAutoScroll(-12.0);
    } else if (local.dy > viewportBox.size.height - threshold) {
      _startAutoScroll(12.0);
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll(double delta) {
    if (_autoScrollTimer != null) return;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!widget.scrollController.hasClients) return;
      final newOffset = (widget.scrollController.offset + delta).clamp(
        0.0,
        widget.scrollController.position.maxScrollExtent,
      );
      if (newOffset != widget.scrollController.offset) {
        widget.scrollController.jumpTo(newOffset);
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  DateTime? _startsAt(Map<String, dynamic> a) =>
      DateTime.tryParse(a['starts_at']?.toString() ?? '')?.toLocal();

  String _hourLabel(int h24) => '${(h24 % 24).toString().padLeft(2, '0')}:00';

  Widget _buildGhostBlock(
      double leftHourWidth, double availableWidth, AppLocalizations l) {
    final hour = _hoverSlotStart!.hour + _hoverSlotStart!.minute / 60.0;
    final clamped = hour < kStartHour ? kStartHour.toDouble() : hour;
    final top = (clamped - kStartHour) / kTotalHours * kGridHeight;
    final durMin =
        _hoverSlotEnd!.difference(_hoverSlotStart!).inMinutes.toDouble();
    final durH = (durMin <= 0 ? 30.0 : durMin) / 60.0;
    final isRefusal = _refusalReason != null;
    final height = (durH / kTotalHours * kGridHeight)
        .clamp(isRefusal ? 56.0 : 44.0, kGridHeight);

    final rangeStr = l.a11yTimeRange(
      DateFormat('HH:mm').format(_hoverSlotStart!),
      DateFormat('HH:mm').format(_hoverSlotEnd!),
    );

    return Positioned(
      top: top,
      left: leftHourWidth + 4,
      width: availableWidth,
      height: height,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isRefusal
                ? AppColors.dangerSoft.withValues(alpha: 0.85)
                : AppColors.primarySoft.withValues(alpha: 0.85),
            border: Border.all(
              color: isRefusal ? AppColors.danger : AppColors.primary,
              width: 2.0,
            ),
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ((_hoverTemplate!['title'] ?? '').toString().isNotEmpty
                          ? (_hoverTemplate!['title'] ?? '').toString()
                          : (isSelfActivity(_hoverTemplate!) ? l.timeForMe : '')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color:
                            isRefusal ? AppColors.dangerInk : AppColors.primaryInk,
                      ),
                    ),
                  ),
                  Text(
                    rangeStr,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color:
                          isRefusal ? AppColors.dangerInk : AppColors.primaryInk,
                    ),
                  ),
                ],
              ),
              if (isRefusal) ...[
                const SizedBox(height: 2),
                Text(
                  _refusalReason!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dangerInk,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = context.watch<AppState>();

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: SingleChildScrollView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: widget.isNarrow ? 180.0 : 0.0),
        child: DragTarget<Map<String, dynamic>>(
          onWillAcceptWithDetails: (details) {
            if (!_canMoveHere(details.data)) return false;
            if (details.data['type'] == 'template' ||
                details.data['type'] == 'scheduled') {
              _updateHover(details.data, details.offset);
              return _refusalReason == null;
            }
            return true;
          },
          onMove: (details) {
            if (!_canMoveHere(details.data)) return;
            if (details.data['type'] == 'template' ||
                details.data['type'] == 'scheduled') {
              _updateHover(details.data, details.offset);
            }
          },
          onLeave: (_) {
            _clearHover();
            _stopAutoScroll();
          },
          onAcceptWithDetails: (details) {
            _stopAutoScroll();
            _clearHover();
            if (!_canMoveHere(details.data)) return;
            final box =
                _gridKey.currentContext?.findRenderObject() as RenderBox?;
            if (box == null) return;
            final local = box.globalToLocal(details.offset);
            if (details.data['type'] == 'template' ||
                details.data['type'] == 'scheduled') {
              final act = details.data['activity'] as Map<String, dynamic>;
              final pct = (local.dy / kGridHeight).clamp(0.0, 1.0);
              var h = kStartHour + pct * kTotalHours;
              h = ((h * 4).round() / 4.0).clamp(kStartHour.toDouble(), 23.75);
              final hour = h.floor();
              final minute = ((h - hour) * 60).round();
              final slotStart = DateTime(widget.day.year, widget.day.month,
                  widget.day.day, hour, minute);
              final durMin = toNum(act['duration_minutes']).toInt();
              final safeDur = durMin <= 0 ? 30 : durMin;
              final slotEnd = slotStart.add(Duration(minutes: safeDur));
              final isScheduled = details.data['type'] == 'scheduled';
              final refusal = _checkRefusal(act, slotStart, slotEnd,
                  isScheduled: isScheduled);
              if (refusal != null) {
                return;
              }
            }
            widget.onGridDrop(details.data, local.dy);
          },
          builder: (context, candidates, rejected) {
            final hasDrag = candidates.isNotEmpty || rejected.isNotEmpty;
            return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) => _tapDy = d.localPosition.dy,
            onTap: () => widget.onGridTap?.call(_tapDy),
            onDoubleTapDown: (d) => _doubleTapDy = d.localPosition.dy,
            onDoubleTap: () => widget.onDoubleTap(_doubleTapDy),
            child: Container(
              key: _gridKey,
              height: kGridHeight,
              color: candidates.isNotEmpty
                  ? AppColors.primarySoft.withValues(alpha: 0.4)
                  : Colors.transparent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final leftHourWidth = widget.isNarrow ? 44.0 : 62.0;
                  final availableWidth =
                      (constraints.maxWidth - leftHourWidth - 10.0)
                          .clamp(100.0, 5000.0);

                  return Stack(
                    children: [
                      // 1. Hour lines + labels
                      for (var h = 0; h <= kTotalHours; h++)
                        Positioned(
                          top: h / kTotalHours * kGridHeight,
                          left: 0,
                          right: 0,
                          child: Row(
                            children: [
                              SizedBox(
                                width: leftHourWidth,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                      left: widget.isNarrow ? 4 : 8),
                                  child: Text(
                                    _hourLabel(kStartHour + h),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              const Expanded(
                                child: Divider(
                                  height: 1,
                                  color: AppColors.border,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // 2. Absence bands across the grid
                      for (final abs in widget.absences)
                        _buildAbsenceBand(abs, leftHourWidth, l),

                      // 3. Past hours muted on today
                      if (widget.isToday && widget.nowLineTop != null)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: (widget.nowLineTop! / 100 * kGridHeight)
                              .clamp(0.0, kGridHeight),
                          child: IgnorePointer(
                            child: Container(
                              color: AppColors.bg.withValues(alpha: 0.45),
                            ),
                          ),
                        ),

                      // 4. NOW line
                      if (widget.isToday && widget.nowLineTop != null)
                        Positioned(
                          top: widget.nowLineTop! / 100 * kGridHeight,
                          left: leftHourWidth - 2,
                          right: 10,
                          child: IgnorePointer(
                            child: Row(
                              children: [
                                Container(
                                  key: const ValueKey('now-line-dot'),
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.danger,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    height: 2,
                                    color: AppColors.danger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // 5. Pending personal-time requests (dashed blocks)
                      for (final req in widget.requests)
                        _buildRequestBlock(req, leftHourWidth, l, app),

                      // 6. Scheduled activity chips
                      for (final a in widget.items)
                        _buildChip(a, availableWidth, leftHourWidth, l, app),

                      // 7. Ghost block
                      if (_hoverTemplate != null &&
                          _hoverSlotStart != null &&
                          _hoverSlotEnd != null &&
                          hasDrag)
                        _buildGhostBlock(leftHourWidth, availableWidth, l),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    ),
  );
}

  Widget _buildAbsenceBand(
      Map<String, dynamic> abs, double leftHourWidth, AppLocalizations l) {
    final start =
        DateTime.tryParse(abs['start_time']?.toString() ?? '')?.toLocal();
    final end =
        DateTime.tryParse(abs['end_time']?.toString() ?? '')?.toLocal();
    if (start == null) return const SizedBox.shrink();
    final dayStart =
        DateTime(widget.day.year, widget.day.month, widget.day.day, kStartHour);
    final dayEnd = DateTime(
        widget.day.year, widget.day.month, widget.day.day, kStartHour + kTotalHours);

    final safeEnd = end ?? start.add(const Duration(hours: 24));
    if (safeEnd.isBefore(dayStart) || start.isAfter(dayEnd)) {
      return const SizedBox.shrink();
    }

    final effStart = start.isBefore(dayStart) ? dayStart : start;
    final effEnd = safeEnd.isAfter(dayEnd) ? dayEnd : safeEnd;

    final sHour = effStart.hour + effStart.minute / 60.0;
    final eHour = (effEnd.day > effStart.day || effEnd.isAfter(dayEnd))
        ? (kStartHour + kTotalHours).toDouble()
        : (effEnd.hour + effEnd.minute / 60.0);

    final top =
        ((sHour - kStartHour) / kTotalHours * kGridHeight).clamp(0.0, kGridHeight);
    final bottom =
        ((eHour - kStartHour) / kTotalHours * kGridHeight).clamp(0.0, kGridHeight);
    final h = (bottom - top).clamp(28.0, kGridHeight);

    final who =
        (abs['user_alias'] ?? abs['user_name'] ?? l.absAway).toString();
    final label = l.absenceBandAway(who);

    return Positioned(
      top: top,
      left: leftHourWidth + 4,
      right: 10,
      height: h,
      child: Semantics(
        label: label,
        child: Tappable(
          onTap: () => widget.onAbsenceTap(abs),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft.withValues(alpha: 0.65),
              border:
                  Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dangerInk,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestBlock(Map<String, dynamic> req, double leftHourWidth,
      AppLocalizations l, AppState app) {
    final start =
        DateTime.tryParse(req['starts_at']?.toString() ?? '')?.toLocal();
    final end = DateTime.tryParse(req['ends_at']?.toString() ?? '')?.toLocal();
    if (start == null) return const SizedBox.shrink();
    final hour = start.hour + start.minute / 60.0;
    final clamped = hour < kStartHour ? kStartHour.toDouble() : hour;
    final top = (clamped - kStartHour) / kTotalHours * kGridHeight;
    final durMin =
        (end != null ? end.difference(start).inMinutes : 60).toDouble();
    final durH = (durMin <= 0 ? 30.0 : durMin) / 60.0;
    final visibleH = durH < (24 - clamped) ? durH : (24 - clamped);
    final height =
        (visibleH / kTotalHours * kGridHeight).clamp(52.0, kGridHeight);

    final mine = req['requester_id']?.toString() == app.userId?.toString();
    final requester =
        (req['requester_alias'] ?? req['requester_name'] ?? '').toString();
    final reqState = mine
        ? (req['requested_of_name'] == null
            ? l.ptAwaitingAnyone
            : l.ptAwaiting(req['requested_of_name'].toString()))
        : l.ptAskedYouToCover(requester);
    final title = (req['title'] ?? '').toString();
    final glyph = personalTimeTypeGlyph(req['type']?.toString() ?? '');
    final semanticsLabel =
        '$glyph $title, $requester, $reqState, ${DateFormat('HH:mm').format(start)}';

    return Positioned(
      top: top,
      left: leftHourWidth + 6,
      right: 10,
      height: height,
      child: Semantics(
        container: true,
        label: semanticsLabel,
        child: Tappable(
          onTap: () => widget.onRequestTap(req),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: AppColors.inputBorder,
              radius: AppRadii.md,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Row(
                children: [
                  Text(glyph, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '$requester · $reqState',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('HH:mm').format(start),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChip(Map<String, dynamic> a, double availableWidth,
      double leftHourWidth, AppLocalizations l, AppState app) {
    final ts = _startsAt(a)!;
    final hour = ts.hour + ts.minute / 60.0;
    final clamped = hour < kStartHour ? kStartHour.toDouble() : hour;
    final top = (clamped - kStartHour) / kTotalHours * kGridHeight;
    final durMin = toNum(a['duration_minutes']).toDouble();
    final durH = (durMin <= 0 ? 30.0 : durMin) / 60.0;
    final visibleH = durH < (24 - clamped) ? durH : (24 - clamped);
    final height =
        (visibleH / kTotalHours * kGridHeight).clamp(52.0, kGridHeight);

    final colCount = (a['_colCount'] as int?) ?? 1;
    final colIndex = (a['_colIndex'] as int?) ?? 0;
    final colWidth = availableWidth / colCount;
    final left = leftHourWidth + colIndex * colWidth;
    final width = (colWidth - 4.0).clamp(40.0, availableWidth);

    final status = a['status']?.toString() ?? 'pending';
    final completed = status == 'completed';

    final chip = DayActivityBlock(
      activity: a,
      onValidate: widget.onValidate,
      onDelegate: widget.onBounty,
      onTakeOver: widget.onTakeOver,
    );

    final interactive = Tappable(
      onTap: () {
        if (widget.onActivityTap != null) {
          widget.onActivityTap!(a);
        } else if (completed) {
          widget.onCompletedInfo();
        } else if (a['is_recurrent'] == true) {
          widget.onRecurrence(a);
        }
      },
      child: chip,
    );

    final canMove = widget.canMove?.call(a) ?? false;
    final isDraggable = widget.isNarrow ? canMove : (canMove || widget.canRemove(a));

    return Positioned(
      top: top,
      left: left,
      width: width,
      height: height,
      child: isDraggable
          ? touchAwareDraggable(
              data: {'type': 'scheduled', 'activity': a},
              onDragStarted: widget.onDragStarted,
              onDragEnd: (_) => widget.onDragEnd(),
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: width.clamp(160.0, 320.0),
                  height: height,
                  child: Opacity(opacity: 0.85, child: chip),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: chip),
              child: interactive,
            )
          : interactive,
    );
  }
}

bool _hasActivityAction(Map<String, dynamic> item, AppState app) {
  if (isSelfActivity(item)) return false;
  final status = item['status']?.toString() ?? 'pending';
  final bounty = toNum(item['bounty_amount']);
  final mine = item['assigned_to'] != null &&
      app.userId != null &&
      item['assigned_to'].toString() == app.userId.toString();
  if (status == 'pending_validation') return true;
  if (status == 'completed') return true;
  if (status == 'rejected') return true;
  if (mine && bounty == 0 && app.isCaregiver) return true;
  if (mine && bounty > 0) return true;
  if (!mine && bounty > 0 && app.isCaregiver) return true;
  return false;
}

Widget _buildAvatarCircle(
    Map<String, dynamic> item, AppState app, AppLocalizations l) {
  final mine = item['assigned_to'] != null &&
      app.userId != null &&
      item['assigned_to'].toString() == app.userId.toString();
  final name = (item['assigned_alias'] ?? item['assigned_to_name'] ?? '')
      .toString()
      .trim();
  if (!mine && name.isEmpty) return const SizedBox.shrink();

  final initial = () {
    if (mine) {
      final myName = (app.family?['alias'] ??
              app.profile?['display_name'] ??
              item['assigned_alias'] ??
              item['assigned_to_name'] ??
              '')
          .toString()
          .trim();
      if (myName.isNotEmpty) return myName[0].toUpperCase();
      return l.assigneeYou.isNotEmpty ? l.assigneeYou[0].toUpperCase() : 'Y';
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }();

  return ExcludeSemantics(
    child: Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: mine ? AppColors.primarySoft : AppColors.bg,
        border: Border.all(
          color: mine ? AppColors.primary : AppColors.border,
          width: 1.0,
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: mine ? AppColors.primaryInk : AppColors.textSecondary,
          height: 1.0,
        ),
      ),
    ),
  );
}

class DayActivityBlock extends StatelessWidget {
  final Map<String, dynamic> activity;
  final ValueChanged<dynamic>? onValidate;
  final ValueChanged<Map<String, dynamic>>? onDelegate;
  final ValueChanged<Map<String, dynamic>>? onTakeOver;

  const DayActivityBlock({
    super.key,
    required this.activity,
    this.onValidate,
    this.onDelegate,
    this.onTakeOver,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = context.watch<AppState>();
    final a = activity;

    final status = a['status']?.toString() ?? 'pending';
    final completed = status == 'completed';
    final isCare = a['type'] == 'care' || a['category'] == 'care';
    final isCoverage = a['type'] == 'coverage';
    final isSelf = isSelfActivity(a);
    final coins = toNum(a['coin_value']).toInt();
    final filled = completed && !isSelf;

    final (bg, fg, border) = status == 'rejected'
        ? (AppColors.dangerSoft, AppColors.dangerInk, null)
        : filled
            ? (
                isCare ? AppColors.successStrong : AppColors.warningStrong,
                Colors.white,
                null,
              )
            : isSelf
                ? (
                    AppColors.surface,
                    AppColors.textPrimary,
                    Border.all(color: AppColors.inputBorder, width: 1.0),
                  )
                : isCoverage
                    ? (AppColors.primarySoft, AppColors.primaryInk, null)
                    : isCare
                        ? (AppColors.successSoft, AppColors.successInk, null)
                        : (AppColors.warningSoft, AppColors.warningInk, null);

    final semanticsLabel = _activitySemanticsLabel(l: l, item: a, app: app);

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final blockW = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : double.infinity;
          final blockH = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : double.infinity;

          final showEmoji = blockW >= 120;
          final titleMaxLines = blockH >= 72 ? 2 : 1;

          final titleText = Text.rich(
            TextSpan(children: [
              if (status == 'rejected') const TextSpan(text: '⚠️ '),
              TextSpan(text: (a['title'] ?? '').toString()),
              if (a['is_recurrent'] == true) const TextSpan(text: '  🔁'),
            ]),
            maxLines: titleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          );

          final titleWidget = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showEmoji) ...[
                ExcludeSemantics(
                  child: Text(
                    _activityEmoji(a),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: ExcludeSemantics(
                  child: titleText,
                ),
              ),
            ],
          );

          Widget? coinPill;
          if (coins > 0 && !isSelf) {
            coinPill = ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: filled
                      ? Colors.black.withValues(alpha: 0.15)
                      : AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  '🪙 ${coins}cc',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: filled ? Colors.white : AppColors.primaryInk,
                  ),
                ),
              ),
            );
          }

          final metaRow = Wrap(
            spacing: 4,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (blockW < 120)
                _buildAvatarCircle(a, app, l)
              else
                ExcludeSemantics(child: AssigneeBadge(item: a, compact: true)),
              if (coinPill != null) coinPill,
            ],
          );

          final hasAction = _hasActivityAction(a, app);

          return Container(
            width: constraints.hasBoundedWidth ? double.infinity : null,
            height: constraints.hasBoundedHeight ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              border: border,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (constraints.hasBoundedHeight)
                  Flexible(
                    fit: FlexFit.loose,
                    child: titleWidget,
                  )
                else
                  titleWidget,
                if (blockH >= 44) ...[
                  const SizedBox(height: 3),
                  metaRow,
                ],
                if (blockH >= 72 && hasAction) ...[
                  const SizedBox(height: 3),
                  _ActivityAction(
                    item: a,
                    compact: true,
                    onValidate: () => onValidate?.call(a['id']),
                    onDelegate: () => onDelegate?.call(a),
                    onTakeOver: () => onTakeOver?.call(a),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}


class WeekStrip extends StatelessWidget {
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<int> onWeekChange;
  final DateTime? today;

  const WeekStrip({
    super.key,
    required this.selectedDay,
    required this.onSelectDay,
    required this.onWeekChange,
    this.today,
  });

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static List<DateTime> weekDaysFor(DateTime selectedDay) {
    final monday = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day - (selectedDay.weekday - 1),
    );
    return List.generate(
      7,
      (i) => DateTime(monday.year, monday.month, monday.day + i),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    final days = weekDaysFor(selectedDay);
    final now = today ?? DateTime.now();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -300) {
          onWeekChange(1);
        } else if (v > 300) {
          onWeekChange(-1);
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
        child: Row(
          children: [
            for (final day in days)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: WeekDayChip(
                    day: day,
                    isSelected: isSameDay(day, selectedDay),
                    isToday: isSameDay(day, now),
                    locale: locale,
                    onTap: () => onSelectDay(day),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class WeekDayChip extends StatelessWidget {
  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final String locale;
  final VoidCallback onTap;

  const WeekDayChip({
    super.key,
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.locale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final weekdayStr = DateFormat.E(locale).format(day);
    final initial = weekdayStr.characters.isNotEmpty
        ? weekdayStr.characters.first.toUpperCase()
        : '';
    final fullDateLabel = DateFormat.yMMMMEEEEd(locale).format(day);

    return Semantics(
      button: true,
      selected: isSelected,
      label: fullDateLabel,
      child: Material(
        color: isSelected ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      initial,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            isSelected ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color:
                            isSelected ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isToday
                            ? (isSelected ? Colors.white : AppColors.primary)
                            : Colors.transparent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

sealed class _NeedsItem {}

class _NeedsValidation extends _NeedsItem {
  final Map<String, dynamic> activity;
  _NeedsValidation(this.activity);
}

class _NeedsCoverRequest extends _NeedsItem {
  final Map<String, dynamic> request;
  _NeedsCoverRequest(this.request);
}

class _NeedsMemberApproval extends _NeedsItem {
  final Map<String, dynamic> member;
  _NeedsMemberApproval(this.member);
}

class _NeedsTakeOverOffer extends _NeedsItem {
  final Map<String, dynamic> activity;
  _NeedsTakeOverOffer(this.activity);
}

class _NeedsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String? badge;
  final Color? badgeColor;
  final Color? badgeBg;
  final String actionLabel;
  final VoidCallback onTap;

  const _NeedsRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    this.badge,
    this.badgeColor,
    this.badgeBg,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeBg ?? AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: badgeColor ?? AppColors.primaryInk,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAddSheet extends StatefulWidget {
  final DateTime startsAt;
  final List<Map<String, dynamic>> templates;
  final ValueChanged<Map<String, dynamic>> onTapTemplate;
  final VoidCallback onTapTimeForMe;

  const _QuickAddSheet({
    required this.startsAt,
    required this.templates,
    required this.onTapTemplate,
    required this.onTapTimeForMe,
  });

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  final _search = TextEditingController();
  int _filter = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final timeStr = DateFormat('HH:mm').format(widget.startsAt);
    final q = _search.text.trim().toLowerCase();

    final filtered = widget.templates.where((t) {
      if (_filter == 1 && t['type'] != 'care') return false;
      if (_filter == 2 && t['type'] != 'household') return false;
      if (q.isNotEmpty &&
          !(t['title']?.toString().toLowerCase().contains(q) ?? false)) {
        return false;
      }
      return true;
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.quickAddTitle(timeStr),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l.searchTasks,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _search.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SegmentedTabs(
                tabs: [l.filterAll, l.filterCare, l.filterHousehold],
                selected: _filter,
                onChanged: (i) => setState(() => _filter = i),
              ),
              const SizedBox(height: 12),
              // "Time for me" as first row
              Semantics(
                button: true,
                label: l.timeForMe,
                child: Tappable(
                  onTap: widget.onTapTimeForMe,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Text('🧘', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l.timeForMe,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            size: 20, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
              ),
              for (final t in filtered) ...[
                Builder(
                  builder: (ctx) {
                    final title = (t['title'] ?? '').toString();
                    final isCare = t['type'] == 'care';
                    final coins = toNum(t['coin_value']).toInt();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Tappable(
                        onTap: () => widget.onTapTemplate(t),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isCare
                                      ? AppColors.successSoft
                                      : AppColors.warningSoft,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(isCare ? '❤️' : '🍽️',
                                    style: const TextStyle(fontSize: 16)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800),
                                    ),
                                    Text(
                                      '${isCare ? l.filterCare : l.filterHousehold}'
                                      '${coins > 0 ? ' · 🪙 ${coins}cc' : ''}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.add_circle_outline_rounded,
                                  size: 20, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      l.noTasksFiltered,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> activity;
  final VoidCallback? onValidate;
  final VoidCallback? onDelegate;
  final VoidCallback? onTakeOver;
  final VoidCallback? onRepeat;
  final VoidCallback? onMove;
  final VoidCallback? onRemove;

  const _ActivityDetailsSheet({
    required this.activity,
    this.onValidate,
    this.onDelegate,
    this.onTakeOver,
    this.onRepeat,
    this.onMove,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = AppLocalizations.of(context);
    final a = activity;

    final isCoverage = a['type'] == 'coverage';
    final isSelf = isSelfActivity(a);
    final isOrdinary = !isCoverage && !isSelf;
    final mine = a['assigned_to']?.toString() == app.userId?.toString();
    final status = a['status']?.toString() ?? 'pending';
    final completed = status == 'completed';
    final isApproved = status == 'approved';
    final isPendingValidation = status == 'pending_validation';
    final isCaregiver = app.isCaregiver;
    final bounty = toNum(a['bounty_amount']).toInt();
    final coins = toNum(a['coin_value']).toInt();

    final canValidate = !isCoverage && !completed && isPendingValidation && !mine && isCaregiver;
    final canTakeOver = isOrdinary && !completed && !isPendingValidation && !mine && bounty > 0;
    final canDelegate = isOrdinary && isApproved && mine && bounty == 0;
    final canRepeat = isOrdinary && !completed && a['is_recurrent'] == true;
    final canMove = canMoveActivity(a, app);
    final canRemove = !completed && canRemoveActivity(a, app);

    final rawTitle = (a['title'] ?? '').toString();
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : (isSelf ? l.personalTimeEntry : '');
    final emoji = _activityEmoji(a);

    final start = DateTime.tryParse(a['starts_at']?.toString() ?? '')?.toLocal();
    final durMin = toNum(a['duration_minutes']).toInt();
    final safeDur = durMin <= 0 ? 30 : durMin;
    final end = a['ends_at'] != null
        ? DateTime.tryParse(a['ends_at'].toString())?.toLocal() ??
            (start?.add(Duration(minutes: safeDur)))
        : (start?.add(Duration(minutes: safeDur)));

    String? timeRange;
    if (start != null && end != null) {
      timeRange =
          '${DateFormat('HH:mm').format(start)} – ${DateFormat('HH:mm').format(end)}';
    }

    final assigneeName = mine
        ? l.assigneeYou
        : (a['assigned_alias'] ?? a['assigned_to_name'] ?? '').toString().trim();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title & Emoji
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (timeRange != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            timeRange,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Assignee & Coins Row
              Row(
                children: [
                  if (assigneeName.isNotEmpty) ...[
                    _buildAvatarCircle(a, app, l),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        assigneeName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (coins > 0 && !isSelf) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        '🪙 ${coins}cc',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryInk,
                        ),
                      ),
                    ),
                  ],
                  if (bounty > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.warningSoft,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        '+${bounty}cc',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.warningInk,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // Explanations / Notes
              if (isCoverage) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Text(
                    l.coverageEndsWithPersonalTime,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryInk,
                    ),
                  ),
                ),
              ] else if (completed) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Text(
                    l.completedLockedBody,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
              // Action Buttons
              if (canValidate) ...[
                const SizedBox(height: 16),
                VButton(
                  type: VButtonType.primary,
                  block: true,
                  onPressed: onValidate,
                  child: Text(l.actionValidate),
                ),
              ],
              if (canTakeOver) ...[
                const SizedBox(height: 16),
                VButton(
                  type: VButtonType.primary,
                  block: true,
                  onPressed: onTakeOver,
                  child: Text(l.actionTakeOver('$bounty')),
                ),
              ],
              if (canDelegate) ...[
                const SizedBox(height: 12),
                VButton(
                  type: VButtonType.secondary,
                  block: true,
                  onPressed: onDelegate,
                  child: Text(l.actionDelegate),
                ),
              ],
              if (canRepeat) ...[
                const SizedBox(height: 12),
                VButton(
                  type: VButtonType.secondary,
                  block: true,
                  onPressed: onRepeat,
                  child: Text(l.actionRepeat),
                ),
              ],
              if (canMove) ...[
                const SizedBox(height: 12),
                VButton(
                  type: VButtonType.secondary,
                  block: true,
                  onPressed: onMove,
                  child: Text(l.actionMove),
                ),
              ],
              if (canRemove) ...[
                const SizedBox(height: 12),
                VButton(
                  type: VButtonType.danger,
                  block: true,
                  onPressed: onRemove,
                  child: Text(l.remove),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

