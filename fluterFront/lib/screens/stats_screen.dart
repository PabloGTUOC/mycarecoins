import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/tour_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/json.dart';
import '../widgets/charts.dart';
import '../widgets/coach_marks.dart';
import '../widgets/ui.dart';

/// Stats — ten panels rendered as dependency-free charts: KPI row, income trend (with the
/// compare-caregivers toggle), category balance, task frequency,
/// leaderboard, completion rates, bounty stats, coin flow, rewards by
/// member, top rewards and status distribution.
class StatsScreen extends StatefulWidget {
  /// Whether this is the visible tab; becoming active triggers a refetch.
  final bool active;

  const StatsScreen({super.key, this.active = true});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  bool _error = false;
  bool _compare = false;
  int _tab = 0; // mobile: 0 overview, 1 members, 2 economy

  static const _caregiverColors = [
    AppColors.primary,
    AppColors.success,
    AppColors.warning,
    AppColors.danger,
  ];

  final _tourHeadingKey = GlobalKey();
  final _tourCompareKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    TourService.I.addListener(_maybeTour);
    _load();
  }

  @override
  void dispose() {
    TourService.I.removeListener(_maybeTour);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StatsScreen old) {
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
      maybeShowTour(context, 'stats', [
        CoachMark(
          targetKey: _tourHeadingKey,
          title: l.tourStatsTitle,
          body: l.tourStatsBody,
        ),
        CoachMark(
          targetKey: _tourCompareKey,
          title: l.tourCompareTitle,
          body: l.tourCompareBody,
        ),
      ]);
    });
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final data = await app.api.get('/api/stats/${app.familyId}');
      if (mounted) {
        setState(() {
          _stats = Map<String, dynamic>.from(data as Map);
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

  List<Map<String, dynamic>> _listOf(String key) =>
      ((_stats?[key] as List?) ?? [])
          .cast<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();

  List<String> get _caregivers =>
      ((_stats?['activeCaregivers'] as List?) ?? [])
          .map((e) => e.toString())
          .toList();

  bool get _comparing => _compare && _caregivers.length > 1;

  Color _cgColor(int i) => _caregiverColors[i % _caregiverColors.length];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_stats == null) {
      if (_error) {
        return LoadErrorState(onRetry: () {
          setState(() => _loading = true);
          _load();
        });
      }
      return Center(
          child: Text(l.noStatsYet,
              style: const TextStyle(color: AppColors.textSecondary)));
    }

    final wide = isWideLayout(context);
    final overview = _buildOverview();
    final members = _buildMembers();
    final economy = _buildEconomy();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 16, bottom: 40),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PageHeading(
                    key: _tourHeadingKey,
                    title: l.statsTitle,
                    subtitle: l.statsSubtitle),
              ),
              if (_caregivers.length > 1)
                Column(
                  key: _tourCompareKey,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(l.compareCaregivers,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: AppColors.textSecondary)),
                    ),
                    Switch(
                      value: _compare,
                      activeThumbColor: AppColors.primary,
                      onChanged: (v) => setState(() => _compare = v),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (wide) ...[
            ...overview,
            _SectionDivider(l.sectionMembers),
            ...members,
            _SectionDivider(l.sectionEconomy),
            ...economy,
          ] else ...[
            SegmentedTabs(
              tabs: [l.tabOverview, l.sectionMembers, l.tabEconomy],
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: 20),
            if (_tab == 0) ...overview,
            if (_tab == 1) ...members,
            if (_tab == 2) ...economy,
          ],
        ],
      ),
    );
  }

  // ── Overview: KPIs, trend, category balance, task frequency ─────

  List<Widget> _buildOverview() {
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    final kpis = (_stats?['kpis'] as Map?)?.cast<String, dynamic>() ?? {};
    final trend = _listOf('trendByMonth');
    final trendMonths = trend.map((t) => t['month'].toString()).toSet().toList()
      ..sort();
    final fmt = NumberFormat.decimalPattern(loc);

    return [
      LayoutBuilder(builder: (context, c) {
        final perRow = c.maxWidth > kMobileBreakpoint ? 4 : 2;
        final w = (c.maxWidth - (perRow - 1) * 14) / perRow;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(
                width: w,
                child: KpiCard(
                    label: l.kpiLifetimeCoins,
                    value: fmt.format(toNum(kpis['total_lifetime_coins'])),
                    unit: 'cc')),
            SizedBox(
                width: w,
                child: KpiCard(
                    label: l.kpiTasksCompleted,
                    accent: AppColors.success,
                    value: fmt.format(toNum(kpis['total_lifetime_tasks'])))),
            SizedBox(
                width: w,
                child: KpiCard(
                    label: l.kpiBountiesOffered,
                    accent: AppColors.danger,
                    value:
                        fmt.format(toNum(kpis['total_bounties_offered'])))),
            SizedBox(
                width: w,
                child: KpiCard(
                    label: l.kpiRewardsClaimed,
                    accent: AppColors.warning,
                    value: fmt.format(toNum(kpis['total_rewards_claimed'])))),
          ],
        );
      }),
      const SizedBox(height: 20),
      if (trendMonths.isNotEmpty)
        VCard(
          title: l.chartIncomeTrend,
          child: _comparing
              ? MultiLineChart(
                  labels: trendMonths,
                  series: [
                    for (final (i, cg) in _caregivers.indexed)
                      LineSeries(cg, _cgColor(i), [
                        for (final m in trendMonths)
                          toNum(trend.firstWhere(
                            (t) =>
                                t['caregiver'] == cg &&
                                t['month'].toString() == m,
                            orElse: () => const {'coins': 0},
                          )['coins'])
                              .toDouble(),
                      ]),
                  ],
                )
              : LineAreaChart(labels: trendMonths, values: [
                  for (final m in trendMonths)
                    trend
                        .where((t) => t['month'].toString() == m)
                        .fold<double>(0, (sum, t) => sum + toNum(t['coins'])),
                ]),
        ),
      ..._buildCategoryBalance(),
      ..._buildTaskFrequency(),
    ];
  }

  List<Widget> _buildCategoryBalance() {
    final l = AppLocalizations.of(context);
    final split = _listOf('typeSplit');
    if (split.isEmpty) return [];
    num sumFor(String category, [String? caregiver]) => split
        .where((x) =>
            x['type'] == category &&
            (caregiver == null || x['caregiver'] == caregiver))
        .fold<num>(0, (acc, x) => acc + toNum(x['value']));

    return [
      VCard(
        title: l.chartCategoryBalance,
        child: _comparing
            ? Column(
                children: [
                  for (final (label, category) in [
                    (l.catCareEmoji, 'care'),
                    (l.catHouseholdEmoji, 'household')
                  ]) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 4),
                        child: Text(label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14)),
                      ),
                    ),
                    for (final (i, cg) in _caregivers.indexed)
                      _BarRow(
                        label: cg,
                        valueLabel: '${sumFor(category, cg)}',
                        fraction: _fractionOfMax(sumFor(category, cg), [
                          for (final c in _caregivers) sumFor(category, c)
                        ]),
                        color: _cgColor(i),
                      ),
                  ],
                ],
              )
            : DonutChart(segments: [
                DonutSegment(l.filterCare, sumFor('care').toDouble(),
                    AppColors.success),
                DonutSegment(l.filterHousehold,
                    sumFor('household').toDouble(), AppColors.warning),
              ]),
      ),
    ];
  }

  List<Widget> _buildTaskFrequency() {
    final l = AppLocalizations.of(context);
    final freq = _listOf('activityFrequency');
    if (freq.isEmpty) return [];

    final totals = <String, num>{};
    for (final a in freq) {
      final t = (a['title'] ?? '').toString();
      totals[t] = (totals[t] ?? 0) + toNum(a['value']);
    }
    final topTasks = totals.keys.toList()
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    final top6 = topTasks.take(6).toList();

    num countFor(String title, String caregiver) => toNum(freq.firstWhere(
          (x) => x['caregiver'] == caregiver && x['title'] == title,
          orElse: () => const {'value': 0},
        )['value']);

    return [
      VCard(
        title: l.chartTaskFrequency,
        child: Column(
          children: [
            if (_comparing)
              for (final t in top6) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 4),
                    child: Text(t,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                ),
                for (final (i, cg) in _caregivers.indexed)
                  if (countFor(t, cg) > 0)
                    _BarRow(
                      label: cg,
                      valueLabel: '${countFor(t, cg)}×',
                      fraction: _fractionOfMax(countFor(t, cg),
                          [for (final c in _caregivers) countFor(t, c)]),
                      color: _cgColor(i),
                    ),
              ]
            else
              for (final t in top6)
                _BarRow(
                  label: t,
                  valueLabel: '${totals[t]}×',
                  fraction: _fractionOfMax(
                      totals[t]!, [for (final x in top6) totals[x]!]),
                  color: AppColors.primary,
                ),
          ],
        ),
      ),
    ];
  }

  // ── Members: leaderboard, completion, bounty stats ───────────────

  List<Widget> _buildMembers() {
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    final balances = _listOf('memberBalances');
    final completion = _listOf('completionRates');
    final bounties = _listOf('bountyStats');

    // Fairness reads the latest month there is data for, rather than "now":
    // an empty card in the first days of a month would say nothing true.
    final fairness = _listOf('fairnessByMonth');
    final fairMonth = fairness
        .map((f) => f['month'].toString())
        .fold<String?>(null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a);
    final fair = fairness.where((f) => f['month'] == fairMonth).toList();
    final fairScale = [
      for (final f in fair) ...[
        toNum(f['personal_minutes']),
        toNum(f['coverage_minutes'])
      ]
    ];

    return [
      if (balances.isNotEmpty)
        VCard(
          title: l.chartLeaderboard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.legendRoles,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              for (final b in balances)
                _BarRow(
                  label: (b['name'] ?? '').toString(),
                  valueLabel: '${b['coin_balance'] ?? 0} cc',
                  fraction: _fractionOfMax(toNum(b['coin_balance']),
                      [for (final x in balances) toNum(x['coin_balance'])]),
                  color: b['role'] == 'caregiver'
                      ? AppColors.warning
                      : AppColors.primary,
                ),
            ],
          ),
        ),
      if (completion.isNotEmpty)
        VCard(
          title: l.chartCompletionRate,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🟢 ≥80% · 🟡 50–79% · 🔴 <50%',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              for (final r in completion)
                Builder(builder: (_) {
                  final total = toNum(r['total']);
                  final done = toNum(r['completed']);
                  final rate = total > 0 ? (100 * done / total).round() : 0;
                  return _BarRow(
                    label: (r['caregiver'] ?? '').toString(),
                    valueLabel: '$rate% ($done/$total)',
                    fraction: rate / 100,
                    color: rate >= 80
                        ? AppColors.success
                        : rate >= 50
                            ? AppColors.warning
                            : AppColors.danger,
                  );
                }),
            ],
          ),
        ),
      if (bounties.isNotEmpty)
        VCard(
          title: l.chartBounties,
          child: Column(
            children: [
              for (final b in bounties) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 4),
                    child: Text((b['name'] ?? '').toString(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                ),
                for (final (label, key, color) in [
                  (l.offered, 'offered', AppColors.danger),
                  (l.earned, 'earned', AppColors.success),
                  (l.refunded, 'refunded', const Color(0xFF94A3B8)),
                ])
                  _BarRow(
                    label: label,
                    valueLabel: '${toNum(b[key])} cc',
                    fraction: _fractionOfMax(toNum(b[key]), [
                      for (final x in bounties) ...[
                        toNum(x['offered']),
                        toNum(x['earned']),
                        toNum(x['refunded'])
                      ]
                    ]),
                    color: color,
                  ),
              ],
            ],
          ),
        ),
      // Taking time for yourself should be as visible as the care you give;
      // otherwise the app offers a way to take without a way to see it.
      if (fair.isNotEmpty)
        VCard(
          title: l.chartFairness,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  DateFormat('MMMM y', loc)
                      .format(DateTime.parse('$fairMonth-01')),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              for (final f in fair) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 4),
                    child: Text((f['caregiver'] ?? '').toString(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                ),
                for (final (label, key, color) in [
                  (l.fairnessTaken, 'personal_minutes', AppColors.accentSecondary),
                  (l.fairnessGiven, 'coverage_minutes', AppColors.success),
                ])
                  _BarRow(
                    label: label,
                    valueLabel: _hoursLabel(toNum(f[key]).toInt()),
                    fraction: _fractionOfMax(toNum(f[key]), fairScale),
                    color: color,
                  ),
              ],
              Text(l.fairnessNoDeclines,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
    ];
  }

  // ── Economy: coin flow, marketplace, status distribution ─────────

  List<Widget> _buildEconomy() {
    final l = AppLocalizations.of(context);
    final coinFlow = _listOf('coinFlowByReason');
    final rewardsByUser = _listOf('rewardsByUser');
    final topRewards = _listOf('topRewards');
    final statuses = _listOf('statusDistribution');

    final flowMeta = [
      ('activity_completed', l.flowActivities, AppColors.primary),
      ('bounty_earned', l.flowBountiesEarned, AppColors.success),
      ('bounty_escrow', l.flowBountiesPaid, AppColors.danger),
      ('redeemed', l.flowRewardsRedeemed, AppColors.warning),
      ('bounty_refunded', l.flowBountiesRefunded, const Color(0xFF94A3B8)),
      ('coverage_earned', l.flowCoverage, AppColors.accentSecondary),
    ];
    final flowMonths =
        coinFlow.map((d) => d['month'].toString()).toSet().toList()..sort();
    final flowSeries = [
      for (final (reason, label, color) in flowMeta)
        if (coinFlow.any((d) => d['reason'] == reason))
          StackedBarSeries(label, color, [
            for (final m in flowMonths)
              toNum(coinFlow.firstWhere(
                (d) => d['month'].toString() == m && d['reason'] == reason,
                orElse: () => const {'total': 0},
              )['total'])
                  .toDouble(),
          ]),
    ];

    final statusMeta = {
      'completed': (l.statusCompleted, AppColors.success),
      'approved': (l.statusApproved, AppColors.primary),
      'pending': (l.statusPending, AppColors.warning),
      'pending_validation': (l.statusPendingValidation, AppColors.primary),
      'rejected': (l.statusRejected, AppColors.danger),
    };

    return [
      if (flowSeries.isNotEmpty)
        VCard(
          title: l.chartCoinFlow,
          child: StackedBarChart(labels: flowMonths, series: flowSeries),
        ),
      if (rewardsByUser.isNotEmpty)
        VCard(
          title: l.chartRewardsByMember,
          child: Column(
            children: [
              for (final r in rewardsByUser)
                _BarRow(
                  label: (r['name'] ?? '').toString(),
                  valueLabel: '${toNum(r['redemptions'])}',
                  fraction: _fractionOfMax(toNum(r['redemptions']), [
                    for (final x in rewardsByUser) toNum(x['redemptions'])
                  ]),
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      if (topRewards.isNotEmpty)
        VCard(
          title: l.chartTopRewards,
          child: Column(
            children: [
              for (final r in topRewards)
                _BarRow(
                  label: (r['title'] ?? '').toString(),
                  valueLabel: '${toNum(r['redemptions'])}',
                  fraction: _fractionOfMax(toNum(r['redemptions']),
                      [for (final x in topRewards) toNum(x['redemptions'])]),
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      if (statuses.isNotEmpty)
        VCard(
          title: l.chartStatusDist,
          child: DonutChart(segments: [
            for (final s in statuses)
              DonutSegment(
                (statusMeta[s['status']]?.$1 ?? s['status'].toString()),
                toNum(s['count']).toDouble(),
                statusMeta[s['status']]?.$2 ?? const Color(0xFF94A3B8),
              ),
          ]),
        ),
    ];
  }

  static double _fractionOfMax(num value, List<num> all) {
    final max = all.fold<num>(0, (m, v) => v > m ? v : m);
    return max > 0 ? (value / max).toDouble() : 0;
  }
}

class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 16),
      child: Row(
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: AppColors.textSecondary)),
          const SizedBox(width: 12),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }
}

/// Minutes as hours and minutes. Follows the duration picker's convention in
/// personal_time_dialog.dart rather than inventing a second one.
String _hoursLabel(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

class _BarRow extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double fraction;
  final Color color;

  const _BarRow(
      {required this.label,
      required this.valueLabel,
      required this.fraction,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(valueLabel,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.bg,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}
