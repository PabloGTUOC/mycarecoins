import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/telemetry.dart';
import '../services/tour_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/activity_title.dart';
import '../utils/json.dart';
import '../widgets/absence_dialog.dart';
import '../widgets/personal_time_dialog.dart';
import '../widgets/activation_checklist.dart';
import '../widgets/coach_marks.dart';
import '../widgets/ui.dart';
import 'daily_screen.dart';

/// Family Hub: member cards, paginated week
/// strip with absences, task offers, KPI summary and the Recent Activity feed.
class DashboardScreen extends StatefulWidget {
  final VoidCallback? onOpenStats;

  /// Tab jumps used by the activation checklist's deep links.
  final VoidCallback? onOpenActivities;
  final VoidCallback? onOpenMarketplace;
  final ValueChanged<DateTime>? onOpenDaily;

  /// Whether this is the visible tab; becoming active triggers a silent
  /// refetch so the dashboard doesn't go stale between tab switches.
  final bool active;

  const DashboardScreen({
    super.key,
    this.onOpenStats,
    this.onOpenActivities,
    this.onOpenMarketplace,
    this.onOpenDaily,
    this.active = true,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> _dashboard = {
    'members': [],
    'calendar': [],
    'objectsOfCare': []
  };
  List<Map<String, dynamic>> _activities = [];
  List<Map<String, dynamic>> _claimed = [];
  List<Map<String, dynamic>> _absences = [];
  List<Map<String, dynamic>> _requests = [];
  int _weekOffset = 0;
  bool _loading = true;
  bool _error = false;
  int _rewardCount = 0;

  /// Hidden until the stored flag loads, so the card never flashes in
  /// for users who already dismissed it.
  bool _checklistDismissed = true;

  final _tourMembersKey = GlobalKey();
  final _tourWeekKey = GlobalKey();
  final _tourKpiKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    TourService.I.addListener(_maybeTour);
    TourService.I.hasSeen('checklist-dismissed').then((seen) {
      if (mounted && !seen) setState(() => _checklistDismissed = false);
    });
    _load();
  }

  @override
  void dispose() {
    TourService.I.removeListener(_maybeTour);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _load();
      _maybeTour();
    }
  }

  void _maybeTour() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active || _loading) return;
      final l = AppLocalizations.of(context);
      maybeShowTour(context, 'dashboard', [
        CoachMark(
          targetKey: _tourMembersKey,
          title: l.tourMembersTitle,
          body: l.tourMembersBody,
        ),
        CoachMark(
          targetKey: _tourWeekKey,
          title: l.tourWeekTitle,
          body: l.tourWeekBody,
        ),
        CoachMark(
          targetKey: _tourKpiKey,
          title: l.tourKpiTitle,
          body: l.tourKpiBody,
        ),
      ]);
    });
  }

  List<Map<String, dynamic>> _asMaps(dynamic list) => ((list as List?) ?? [])
      .cast<Map>()
      .map((m) => m.cast<String, dynamic>())
      .toList();

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (app.familyId == 0) {
      setState(() => _loading = false);
      return;
    }
    try {
      final data = await app.api.get('/api/dashboard/${app.familyId}');
      final acts =
          await app.api.get('/api/activities?familyId=${app.familyId}');
      List<Map<String, dynamic>> claimed = [];
      var rewardCount = 0;
      try {
        final rewards =
            await app.api.get('/api/marketplace/rewards/${app.familyId}');
        if (rewards is List) {
          rewardCount = rewards.length;
        } else {
          claimed = _asMaps(rewards['claimed']);
          rewardCount = ((rewards['rewards'] as List?) ?? []).length;
        }
      } catch (_) {}
      List<Map<String, dynamic>> absences = [];
      List<Map<String, dynamic>> requests = [];
      try {
        final abs = await app.api.get('/api/absences?familyId=${app.familyId}');
        absences = _asMaps(abs['absences']);
        final pt =
            await app.api.get('/api/personal-time?familyId=${app.familyId}');
        requests = _asMaps(pt['requests']);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _dashboard = Map<String, dynamic>.from(data as Map);
          _activities =
              acts is List ? _asMaps(acts) : _asMaps(acts['activities']);
          _claimed = claimed;
          _absences = absences;
          _requests = requests;
          _rewardCount = rewardCount;
          _loading = false;
          _error = false;
        });
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

  List<Map<String, dynamic>> get _members => _asMaps(_dashboard['members']);

  /// Logs checklist_completed exactly once, and only for a user who was
  /// shown the checklist while it was still incomplete.
  Future<void> _maybeLogChecklistComplete() async {
    if (!await TourService.I.hasSeen('checklist-started')) return;
    if (await TourService.I.hasSeen('checklist-completed-logged')) return;
    await TourService.I.markSeen('checklist-completed-logged');
    Telemetry.log('checklist_completed');
  }

  /// Steps auto-check from data the dashboard already loads; the whole
  /// card disappears once the family has run the full loop.
  List<Widget> _buildChecklist() {
    final hasTemplate = _activities.any((a) => a['is_template'] == true);
    final hasScheduled = _scheduled.isNotEmpty;
    final hasCompleted = _activities.any((a) =>
        a['status'] == 'pending_validation' || a['status'] == 'completed');
    final hasValidated = _activities.any((a) => a['status'] == 'completed');
    final hasReward = _rewardCount > 0;
    if (hasTemplate &&
        hasScheduled &&
        hasCompleted &&
        hasValidated &&
        hasReward) {
      _maybeLogChecklistComplete();
      return const [];
    }
    // Remember that this user actually saw the checklist, so
    // checklist_completed only fires for people it was shown to (and not
    // for every member of an already-established family).
    TourService.I.markSeen('checklist-started');
    void go(String step, VoidCallback action) {
      Telemetry.log('checklist_step_tapped', {'step': step});
      action();
    }

    final doneCount = [
      hasTemplate,
      hasScheduled,
      hasCompleted,
      hasValidated,
      hasReward
    ].where((d) => d).length;
    final l = AppLocalizations.of(context);
    return [
      ActivationChecklist(
        steps: [
          ChecklistStep(
              label: l.checklistCreateTask,
              done: hasTemplate,
              onGo: () =>
                  go('create_task', () => widget.onOpenActivities?.call())),
          ChecklistStep(
              label: l.checklistSchedule,
              done: hasScheduled,
              onGo: () => go('schedule', () => _openDaily(DateTime.now()))),
          ChecklistStep(
              label: l.checklistMarkDone,
              done: hasCompleted,
              onGo: () => go('complete', () => _openDaily(DateTime.now()))),
          ChecklistStep(
              label: l.checklistValidate,
              done: hasValidated,
              onGo: () => go('validate', () => _openDaily(DateTime.now()))),
          ChecklistStep(
              label: l.checklistStockStore,
              done: hasReward,
              onGo: () => go('reward', () => widget.onOpenMarketplace?.call())),
        ],
        onDismiss: () {
          Telemetry.log('checklist_dismissed', {'progress': doneCount});
          TourService.I.markSeen('checklist-dismissed');
          setState(() => _checklistDismissed = true);
        },
      ),
    ];
  }

  /// Scheduled instances: non-template activities with a start time.
  List<Map<String, dynamic>> get _scheduled => _activities
      .where((a) => a['is_template'] != true && a['starts_at'] != null)
      .toList();

  Future<void> _approveMember(dynamic userId) async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    await app.runAction(() async {
      await app.api
          .post('/api/families/${app.familyId}/members/$userId/approve');
      await _load();
    }, l.toastMemberApproved);
  }

  Future<void> _openDaily(DateTime day) async {
    if (widget.onOpenDaily != null) {
      widget.onOpenDaily!(day);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            DailyScreen(date: DateFormat('yyyy-MM-dd').format(day))));
    // Anything scheduled/validated in Daily should be visible on return.
    if (mounted) await _load();
  }

  Future<void> _logTimeOff() async {
    final created = await showLogAbsenceDialog(context, day: DateTime.now());
    if (created) await _load();
  }

  // ── Week strip ──────────────────────────────────────────────────

  List<DateTime> get _weekDays {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1))
        .add(Duration(days: _weekOffset * 7));
    return [for (var d = 0; d < 7; d++) monday.add(Duration(days: d))];
  }

  /// Phone variant of the week: a rolling window that always starts on
  /// today (plus the pagination offset) — caregivers on mobile think in
  /// "what's ahead", not calendar weeks.
  List<DateTime> get _rollingDays {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .add(Duration(days: _weekOffset * 7));
    return [for (var d = 0; d < 8; d++) start.add(Duration(days: d))];
  }

  String _rangeLabel(List<DateTime> days, String loc) {
    final first = days.first, last = days.last;
    if (first.month == last.month) {
      return '${DateFormat('MMM', loc).format(first)} ${first.day} to ${last.day}';
    }
    return '${DateFormat('MMM d', loc).format(first)} to ${DateFormat('MMM d', loc).format(last)}';
  }

  List<Map<String, dynamic>> _absencesOn(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return _absences.where((a) {
      final start = DateTime.tryParse(a['start_time']?.toString() ?? '');
      final end = DateTime.tryParse(a['end_time']?.toString() ?? '');
      if (start == null || end == null) return false;
      return start.isBefore(dayEnd) && end.isAfter(dayStart);
    }).toList();
  }

  List<Map<String, dynamic>> _actsOn(DateTime day) {
    final acts = _scheduled.where((a) {
      // toLocal() matters: bucketing by the UTC date puts late-evening
      // tasks on the wrong day column (Daily already converts).
      final ts = DateTime.tryParse(a['starts_at']?.toString() ?? '')?.toLocal();
      return ts != null &&
          ts.year == day.year &&
          ts.month == day.month &&
          ts.day == day.day;
    }).toList();
    acts.sort((a, b) => (a['starts_at']?.toString() ?? '')
        .compareTo(b['starts_at']?.toString() ?? ''));
    return acts;
  }

  List<Widget> _buildAgenda(
      List<DateTime> days, String loc, AppLocalizations l) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final widgets = <Widget>[];
    List<DateTime> emptyRun = [];

    void flushEmptyRun() {
      if (emptyRun.isEmpty) return;
      final start = emptyRun.first;
      final end = emptyRun.last;
      final startStr = DateFormat('EEE d', loc).format(start);
      final String label;
      if (emptyRun.length == 1) {
        label = l.freeDaySingle(startStr);
      } else {
        final endStr = DateFormat('EEE d', loc).format(end);
        label = l.freeDaysRange(startStr, endStr);
      }
      widgets.add(
        _FreeDaysRow(
          label: label,
          onTap: () => _openDaily(start),
        ),
      );
      emptyRun = [];
    }

    for (final day in days) {
      final dayDate = DateTime(day.year, day.month, day.day);
      final isToday = dayDate == today;
      final acts = _actsOn(day);
      final absences = _absencesOn(day);
      final hasContent = acts.isNotEmpty || absences.isNotEmpty;

      if (isToday || hasContent) {
        flushEmptyRun();
        widgets.add(
          _DayRow(
            day: day,
            acts: acts,
            absences: absences,
            onTap: () => _openDaily(day),
          ),
        );
      } else {
        emptyRun.add(day);
      }
    }
    flushEmptyRun();
    return widgets;
  }

  // ── Recent activity feed ────────────────────────────────────────

  List<_FeedItem> get _recentActivity {
    final l = AppLocalizations.of(context);
    final items = <_FeedItem>[
      for (final a in _scheduled)
        if (a['status'] == 'completed')
          _FeedItem(
            icon: '✓',
            color: AppColors.primaryInk,
            background: AppColors.primarySoft,
            actor: (a['assigned_to_name'] ?? l.fallbackSomeone).toString(),
            verb: l.feedVerbCompleted,
            subject: displayTitle(l, a),
            time: DateTime.tryParse(a['starts_at']?.toString() ?? ''),
            coinText: isSelfActivity(a) ? null : '+${toNum(a['coin_value'])} cc',
            coinColor: AppColors.success,
          ),
      for (final r in _claimed)
        _FeedItem(
          icon: '🛍️',
          color: AppColors.dangerInk,
          background: AppColors.dangerSoft,
          actor: (r['buyer_name'] ?? l.fallbackSomeone).toString(),
          verb: l.feedVerbGot,
          subject: (r['title'] ?? '').toString(),
          time: DateTime.tryParse(r['redeemed_at']?.toString() ?? ''),
          coinText: '-${toNum(r['cost'])} cc',
          coinColor: AppColors.danger,
        ),
    ].where((i) => i.time != null).toList();
    items.sort((a, b) => b.time!.compareTo(a.time!));
    return items.take(3).toList();
  }

  String _greeting(AppLocalizations l) {
    final h = DateTime.now().hour;
    if (h < 12) return l.greetingMorning;
    if (h < 18) return l.greetingAfternoon;
    return l.greetingEvening;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error && _members.isEmpty && _activities.isEmpty) {
      return LoadErrorState(onRetry: () {
        setState(() => _loading = true);
        _load();
      });
    }

    final app = context.watch<AppState>();
    final wide = isWideLayout(context);
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    final active = _members.where((m) => m['status'] != 'pending').toList();
    final pending = _members.where((m) => m['status'] == 'pending').toList();
    final objects = _asMaps(_dashboard['objectsOfCare']);
    final totalCoins =
        _members.fold<num>(0, (acc, m) => acc + toNum(m['coin_balance']));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final coinsEarnedToday = _scheduled.fold<num>(0, (sum, a) {
      if (a['status'] != 'completed') return sum;
      if ((a['category'] ?? 'care') != 'care') return sum;
      final ts = DateTime.tryParse(a['starts_at']?.toString() ?? '')?.toLocal();
      if (ts == null || DateTime(ts.year, ts.month, ts.day) != today) return sum;
      return sum + toNum(a['coin_value']) + toNum(a['bounty_amount']);
    });
    final completedToday = _scheduled.where((a) {
      if (a['status'] != 'completed') return false;
      final ts = DateTime.tryParse(a['starts_at']?.toString() ?? '')?.toLocal();
      return ts != null && DateTime(ts.year, ts.month, ts.day) == today;
    }).length;
    final todayActs = _scheduled.where((a) {
      final ts = DateTime.tryParse(a['starts_at']?.toString() ?? '')?.toLocal();
      return ts != null && DateTime(ts.year, ts.month, ts.day) == today;
    }).length;
    final pendingTasks = _activities
        .where((a) =>
            a['status'] == 'pending_validation' || a['status'] == 'pending')
        .length;
    final offers = _scheduled
        .where(
            (a) => toNum(a['bounty_amount']) > 0 && a['status'] != 'completed')
        .toList();
    final bountyTotal =
        offers.fold<num>(0, (acc, o) => acc + toNum(o['bounty_amount']));
    // Requests waiting on this user specifically — the only ones they can act
    // on, and the reason the card is worth interrupting the dashboard for.
    final toCover = _requests.where((r) {
      if (r['status'] != 'pending') return false;
      if (r['requester_id']?.toString() == app.userId?.toString()) return false;
      final target = r['requested_of'];
      return target == null || target.toString() == app.userId?.toString();
    }).toList();
    final recent = _recentActivity;
    final greetName = (app.family?['alias'] ??
            app.profile?['display_name'] ??
            l.fallbackCaregiver)
        .toString();

    final firstSentence = coinsEarnedToday > 0
        ? l.dashEarned(_greeting(l), greetName, coinsEarnedToday)
        : l.dashNothingEarned(_greeting(l), greetName);
    final subtitle = '$firstSentence ${l.dashPendingTasks(pendingTasks)}';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 16, bottom: 40),
        children: [
          PageHeading(
              title: l.dashTitle,
              subtitle: subtitle,
              onSubtitleTap: () => _openDaily(DateTime.now())),
          if (pendingTasks > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _openDaily(DateTime.now()),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(l.goToToday,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ),

          // ── Activation checklist (onboarding-help-plan Phase 3) ──
          // Caregiver-only: creating tasks, validating and stocking the
          // store are caregiver actions. Auto-hides once the loop ran.
          if (app.isCaregiver && !_checklistDismissed) ..._buildChecklist(),

          // ── Active members ──
          _SectionTitle(l.dashActiveMembers),
          Wrap(
            key: _tourMembersKey,
            spacing: 16,
            runSpacing: 16,
            children: [
              for (var i = 0; i < active.length; i++)
                _MemberCard(
                  name: (active[i]['name'] ??
                          l.fallbackUser(active[i]['user_id'] ?? ''))
                      .toString(),
                  imageUrl: active[i]['avatar_url']?.toString(),
                  balance: toNum(active[i]['coin_balance']),
                  colorIndex: i,
                ),
              for (var i = 0; i < objects.length; i++)
                _MemberCard(
                  name: (objects[i]['name'] ?? l.fallbackDependent).toString(),
                  imageUrl: objects[i]['avatar_url']?.toString(),
                  balance: null,
                  colorIndex: active.length + i,
                ),
            ],
          ),

          if (pending.isNotEmpty) ...[
            const SizedBox(height: 28),
            _SectionTitle(l.dashPendingApproval),
            for (final pm in pending)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Row(
                  children: [
                    AvatarCircle(
                        name: (pm['name'] ?? '?').toString(),
                        size: 40,
                        background: AppColors.bg,
                        foreground: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(
                            (pm['name'] ?? l.fallbackUser(pm['user_id'] ?? ''))
                                .toString(),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700))),
                    VButton(
                        type: VButtonType.outline,
                        onPressed: () => _approveMember(pm['user_id']),
                        child: Text(l.approve)),
                  ],
                ),
              ),
          ],

          const SizedBox(height: 32),

          // ── Week strip ──
          Container(
            key: _tourWeekKey,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 20,
                    offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(wide ? l.dashThisWeek : l.dashComingUp,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text(_rangeLabel(wide ? _weekDays : _rollingDays, loc),
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                height: 1)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VButton(
                            type: VButtonType.outline,
                            onPressed: _logTimeOff,
                            child: Text(l.logTimeOff)),
                        const SizedBox(width: 8),
                        _PaginationButton(
                            label: '«',
                            tooltip: l.prevWeek,
                            onTap: () => setState(() => _weekOffset--)),
                        const SizedBox(width: 8),
                        _PaginationButton(
                            label: '»',
                            tooltip: l.nextWeek,
                            onTap: () => setState(() => _weekOffset++)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Phones: a vertical agenda of the next days — nothing is
                // hidden off-canvas and every row is a full-width tap target.
                if (!wide)
                  Column(
                    children: _buildAgenda(_rollingDays, loc, l),
                  )
                else
                  // Seven-column week grid: when the card
                  // fits all seven days they stretch to share the full width;
                  // narrower than that falls back to a horizontal scroll.
                  LayoutBuilder(builder: (context, constraints) {
                    const cellWidth = 120.0, gap = 10.0;
                    if (constraints.maxWidth >= 7 * cellWidth + 6 * gap) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < _weekDays.length; i++) ...[
                            if (i > 0) const SizedBox(width: gap),
                            Expanded(
                              child: _DayColumn(
                                day: _weekDays[i],
                                acts: _actsOn(_weekDays[i]),
                                absences: _absencesOn(_weekDays[i]),
                                onTap: () => _openDaily(_weekDays[i]),
                                width: null,
                              ),
                            ),
                          ],
                        ],
                      );
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final day in _weekDays)
                            _DayColumn(
                              day: day,
                              acts: _actsOn(day),
                              absences: _absencesOn(day),
                              onTap: () => _openDaily(day),
                            ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ── Someone asked you to cover ──
          if (toCover.isNotEmpty) ...[
            _SectionTitle(l.dashCoverTitle),
            for (final r in toCover)
              _CoverRequestCard(
                request: r,
                onAnswered: _load,
              ),
            const SizedBox(height: 20),
          ],

          // ── Offers ──
          if (offers.isNotEmpty) ...[
            Row(
              children: [
                Expanded(child: _SectionTitle(l.dashOffersTitle)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: PillBadge(text: l.offersOpenCount(offers.length)),
                ),
              ],
            ),
            for (final offer in offers)
              InkWell(
                borderRadius: BorderRadius.circular(AppRadii.md),
                onTap: () {
                  final ts =
                      DateTime.tryParse(offer['starts_at']?.toString() ?? '');
                  if (ts != null) _openDaily(ts);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                            color: AppColors.bg, shape: BoxShape.circle),
                        child: Text(offer['type'] == 'care' ? '❤️' : '🍽️',
                            style: const TextStyle(fontSize: 18)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayTitle(l, offer),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            if (offer['starts_at'] != null)
                              Text(
                                  DateFormat('EEE d MMM · HH:mm', loc).format(
                                      DateTime.parse(
                                              offer['starts_at'].toString())
                                          .toLocal()),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      PillBadge(text: '+${offer['bounty_amount']}cc'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
          ],

          // ── KPIs ──
          LayoutBuilder(builder: (context, c) {
            final perRow = c.maxWidth > kMobileBreakpoint ? 4 : 2;
            final w = (c.maxWidth - (perRow - 1) * 14) / perRow;
            return Wrap(
              key: _tourKpiKey,
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                    width: w,
                    child: InkWell(
                        onTap: widget.onOpenStats,
                        child: KpiCard(
                            label: l.kpiFamilyBalance,
                            value: NumberFormat.decimalPattern(loc)
                                .format(totalCoins),
                            unit: 'cc',
                            subtitle: l.kpiMembersCount(_members.length)))),
                SizedBox(
                    width: w,
                    child: InkWell(
                        onTap: widget.onOpenStats,
                        child: KpiCard(
                            label: l.kpiTasksToday,
                            value: '$completedToday/$todayActs',
                            subtitle: pendingTasks > 0
                                ? l.kpiAwaitingValidation(pendingTasks)
                                : l.kpiOnTrack,
                            progress: todayActs == 0
                                ? 0
                                : 100 * completedToday / todayActs))),
                SizedBox(
                    width: w,
                    child: InkWell(
                        onTap: widget.onOpenStats,
                        child: KpiCard(
                            label: l.kpiOpenBounties,
                            value: '${offers.length}',
                            subtitle: offers.isEmpty
                                ? l.kpiNoBounties
                                : l.kpiUpForGrabs(bountyTotal)))),
                SizedBox(
                    width: w,
                    child: InkWell(
                        onTap: widget.onOpenStats,
                        child: KpiCard(
                            label: l.recentActivity,
                            value: '${recent.length}',
                            subtitle: recent.isEmpty
                                ? l.kpiNoRecent
                                : l.kpiCompletedRecently))),
              ],
            );
          }),

          if (widget.onOpenStats != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onOpenStats,
                child: Text(l.seeAllStats,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // ── Recent Activity feed ──
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.recentActivity,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),
                if (recent.isEmpty)
                  EmptyState(
                    icon: Icons.checklist_rounded,
                    title: l.feedEmptyTitle,
                    body: l.feedEmptyBody,
                    actionLabel: l.feedEmptyAction,
                    onAction: () => _openDaily(DateTime.now()),
                  ),
                for (final item in recent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: item.background, shape: BoxShape.circle),
                          child: Text(item.icon,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: item.color)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(children: [
                                  TextSpan(text: '${item.actor} '),
                                  TextSpan(
                                      text: item.verb,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textSecondary)),
                                  TextSpan(text: ' ${item.subject}'),
                                ]),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    height: 1.3),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  Text(item.timeAgo(l),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textSecondary)),
                                  if (item.coinText != null && item.coinText!.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(item.coinText!,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: item.coinColor)),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                VButton(
                    type: VButtonType.outline,
                    block: true,
                    onPressed: widget.onOpenStats,
                    child: Text(l.seeAllActivity)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the Recent Activity feed (activity completed / reward claimed).
class _FeedItem {
  final String icon;
  final Color color;
  final Color background;
  final String actor;
  final String verb;
  final String subject;
  final DateTime? time;
  final String? coinText;
  final Color coinColor;

  _FeedItem({
    required this.icon,
    required this.color,
    required this.background,
    required this.actor,
    required this.verb,
    required this.subject,
    required this.time,
    this.coinText,
    required this.coinColor,
  });

  String timeAgo(AppLocalizations l) {
    final ms = DateTime.now().difference(time!);
    if (ms.inHours > 24) return l.timeAgoDays(ms.inHours ~/ 24);
    if (ms.inHours > 0) return l.timeAgoHours(ms.inHours);
    return l.timeAgoMins(ms.inMinutes.clamp(1, 59));
  }
}

class _PaginationButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _PaginationButton(
      {required this.label, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _buildButton(),
    );
  }

  Widget _buildButton() {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border.all(color: AppColors.border),
          shape: BoxShape.circle,
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.primary)),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(text,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
    );
  }
}

class _MemberCard extends StatelessWidget {
  final String name;
  final num? balance;
  final int colorIndex;
  final String? imageUrl;

  const _MemberCard(
      {required this.name,
      required this.balance,
      required this.colorIndex,
      this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final soft = AppColors.softAccents[colorIndex % 4];
    final accent = AppColors.accents[colorIndex % 4];
    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        children: [
          AvatarCircle(
              name: name,
              size: 56,
              imageUrl: imageUrl,
              background: soft,
              foreground: accent),
          const SizedBox(height: 10),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (balance != null)
            PillBadge(text: '$balance cc')
          else
            PillBadge(
                text: AppLocalizations.of(context).caredFor,
                color: AppColors.textSecondary,
                background: AppColors.bg),
        ],
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  final DateTime day;
  final List<Map<String, dynamic>> acts;
  final List<Map<String, dynamic>> absences;
  final VoidCallback onTap;

  /// Fixed cell width for the scrolling (phone) layout; null lets the cell
  /// expand to whatever the wide-layout week grid gives it.
  final double? width;

  const _DayColumn(
      {required this.day,
      required this.acts,
      required this.absences,
      required this.onTap,
      this.width = 120});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final hasAbsence = absences.isNotEmpty;

    final bg = hasAbsence
        ? AppColors.dangerSoft
        : (isToday ? AppColors.primarySoft : AppColors.bg);
    final borderColor = hasAbsence
        ? AppColors.dangerSoft
        : (isToday ? AppColors.primary : AppColors.border);

    return Tappable(
      onTap: onTap,
      child: Container(
        width: width,
        margin: EdgeInsets.only(right: width == null ? 0 : 10),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minHeight: 220),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _DayHeader(day: day, isToday: isToday),
                if (hasAbsence)
                  const Positioned(
                      top: -2,
                      right: -34,
                      child: Text('✈️', style: TextStyle(fontSize: 13))),
              ],
            ),
            const SizedBox(height: 8),
            for (final abs in absences) _AbsenceChip(abs: abs),
            for (final a in acts) _ActChip(a: a),
          ],
        ),
      ),
    );
  }
}

/// Weekday abbreviation + day number, shared by the wide week grid and the
/// narrow rolling-day strip. [todayLabel], when given, replaces the weekday
/// abbreviation on the current day (rendered slightly smaller to fit).
class _DayHeader extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final String? todayLabel;

  const _DayHeader({required this.day, required this.isToday, this.todayLabel});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final showToday = isToday && todayLabel != null;
    return Column(
      children: [
        Text(
            showToday
                ? todayLabel!
                : DateFormat('EEE', l.localeName).format(day),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: isToday ? AppColors.primary : AppColors.textSecondary)),
        Text('${day.day}',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isToday ? AppColors.primary : AppColors.textPrimary)),
      ],
    );
  }
}

class _AbsenceChip extends StatelessWidget {
  final Map<String, dynamic> abs;
  const _AbsenceChip({required this.abs});

  @override
  Widget build(BuildContext context) {
    final who = (abs['user_alias'] ?? abs['user_name'] ?? '').toString();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.dangerSoft,
          borderRadius: BorderRadius.circular(AppRadii.sm)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('✈️ ${who.toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: AppColors.dangerInk)),
          Text((abs['title'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: AppColors.dangerInk)),
        ],
      ),
    );
  }
}

/// One day of the phone agenda: date block, activity chips, chevron.
/// Today is outlined in primary, absence days tinted danger — the same
/// vocabulary as the desktop `_DayColumn`.
class _DayRow extends StatelessWidget {
  final DateTime day;
  final List<Map<String, dynamic>> acts;
  final List<Map<String, dynamic>> absences;
  final VoidCallback onTap;

  /// Chips shown before collapsing the rest into a "+N more" pill.
  static const _maxChips = 3;

  const _DayRow(
      {required this.day,
      required this.acts,
      required this.absences,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final hasAbsence = absences.isNotEmpty;

    final bg = hasAbsence
        ? AppColors.dangerSoft
        : (isToday ? AppColors.primarySoft : AppColors.bg);
    final borderColor = hasAbsence
        ? AppColors.dangerSoft
        : (isToday ? AppColors.primary : AppColors.border);
    final free = acts.isEmpty && !hasAbsence;

    return Tappable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 44,
              child: _DayHeader(
                  day: day,
                  isToday: isToday,
                  todayLabel: AppLocalizations.of(context).dayToday),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: free
                  ? Text(AppLocalizations.of(context).freeDay,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary))
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final abs in absences)
                          PillBadge(
                              text:
                                  '✈️ ${(abs['user_alias'] ?? abs['user_name'] ?? '').toString().toUpperCase()}',
                              fontSize: 12,
                              color: AppColors.danger,
                              background: Colors.white),
                        for (final a in acts.take(_maxChips))
                          _ActChip(a: a, dense: true),
                        if (acts.length > _maxChips)
                          PillBadge(
                              text: AppLocalizations.of(context)
                                  .moreCount(acts.length - _maxChips),
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              background: AppColors.surface),
                      ],
                    ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _FreeDaysRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FreeDaysRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          children: [
            const Icon(Icons.wb_sunny_outlined,
                size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _ActChip extends StatelessWidget {
  final Map<String, dynamic> a;

  /// Dense chips size to their content (for the agenda-row Wrap) instead
  /// of filling the day column's width.
  final bool dense;

  const _ActChip({required this.a, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = a['status']?.toString() ?? '';
    final isCare = a['type'] == 'care';

    Color bg, fg;
    Border? border;
    if (status == 'rejected') {
      bg = AppColors.dangerSoft;
      fg = AppColors.dangerInk;
    } else if (status == 'completed') {
      bg = isCare ? AppColors.successStrong : AppColors.warningStrong;
      fg = Colors.white;
    } else {
      bg = AppColors.surface;
      fg = AppColors.textPrimary;
      border = Border.all(color: AppColors.border);
    }

    final ts = DateTime.tryParse(a['starts_at']?.toString() ?? '')?.toLocal();
    final chip = Container(
      width: dense ? null : double.infinity,
      margin: dense ? EdgeInsets.zero : const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
          color: bg,
          border: border,
          borderRadius: BorderRadius.circular(AppRadii.sm)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${status == 'rejected' ? '⚠️ ' : ''}${displayTitle(l, a)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: fg),
                ),
              ),
              // Hidden once completed: the bounty is already earned, and
              // amber is unreadable on the green/amber completed chip.
              if (toNum(a['bounty_amount']) > 0 && status != 'completed')
                Text('+${a['bounty_amount']}cc',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (ts != null)
                Text(DateFormat('HH:mm').format(ts),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: status == 'completed'
                            ? Colors.white
                            : AppColors.textSecondary)),
              Flexible(child: AssigneeBadge(item: a, compact: true)),
            ],
          ),
        ],
      ),
    );
    if (!dense) return chip;
    // Inside a Wrap the width constraint is unbounded; cap it so the inner
    // Expanded works and long titles ellipsize instead of overflowing.
    return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190), child: chip);
  }
}

/// "X asked you to cover" — the one thing on the dashboard that needs an answer
/// rather than a glance. Declining is deliberately as easy as accepting, and
/// nothing anywhere counts how often someone says no.
class _CoverRequestCard extends StatefulWidget {
  final Map<String, dynamic> request;
  final Future<void> Function() onAnswered;

  const _CoverRequestCard({required this.request, required this.onAnswered});

  @override
  State<_CoverRequestCard> createState() => _CoverRequestCardState();
}

class _CoverRequestCardState extends State<_CoverRequestCard> {
  bool _busy = false;

  Future<void> _answer(bool accept) async {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    setState(() => _busy = true);
    Map? answer;
    final ok = await app.runAction(() async {
      final res = await app.api.post(
          '/api/personal-time/${widget.request['id']}/${accept ? 'accept' : 'decline'}');
      if (res is Map) answer = res;
      await widget.onAnswered();
    });
    if (ok) {
      // A repeating request may be only partly coverable; say which it was.
      final skipped = toNum(answer?['skipped'] ?? 0).toInt();
      final created = toNum(answer?['created'] ?? 0).toInt();
      app.setSuccess(skipped > 0
          ? l.toastCoverageAcceptedSeries(created, created + skipped)
          : (accept ? l.toastCoverageAccepted : l.toastCoverageDeclined));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    final r = widget.request;
    final start = DateTime.parse(r['starts_at'].toString()).toLocal();
    final end = DateTime.parse(r['ends_at'].toString()).toLocal();
    final pays = toNum(r['baseline_coins']) + toNum(r['sweetener_coins']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.primary),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(personalTimeTypeGlyph(r['type']?.toString() ?? ''),
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.ptCoverCardBody(
                    (r['requester_name'] ?? '').toString(),
                    '${DateFormat('EEE d MMM', loc).format(start)} '
                    '${DateFormat('HH:mm').format(start)}\u2013${DateFormat('HH:mm').format(end)}',
                    displayTitle(l, r),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if ((r['description'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 30),
              child: Text(r['description'].toString(),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ),
          const SizedBox(height: 10),
          Text(l.ptCoverPays(pays),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.success)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: VButton(
                  type: VButtonType.outline,
                  disabled: _busy,
                  onPressed: _busy ? null : () => _answer(false),
                  child: Text(l.declineAction),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: VButton(
                  disabled: _busy,
                  onPressed: _busy ? null : () => _answer(true),
                  child: Text(l.acceptAction),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
