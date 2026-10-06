import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/tour_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/json.dart';
import '../widgets/coach_marks.dart';
import '../widgets/ui.dart';

/// Activities: Catalogue / New Activity / Budget tabs.
/// Coin suggestions come from the family budget (`baseRatePerHour`), the
/// slider is bounded to 0.5×–1.5× of the suggestion, and pending templates
/// carry an Approve action.
class ActivitiesScreen extends StatefulWidget {
  /// Whether this is the visible tab; becoming active triggers a refetch.
  final bool active;

  const ActivitiesScreen({super.key, this.active = true});

  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen> {
  List<Map<String, dynamic>> _activities = [];
  Map<String, dynamic>? _budget;
  bool _loading = true;
  bool _error = false;
  int _tab = 0; // 0 catalogue, 1 new, 2 budget
  int _filter = 0; // 0 all, 1 care, 2 household

  final _title = TextEditingController();
  String _type = 'care';
  int _durationMinutes = 60;
  bool _isRecurrent = false;
  double _coins = 0;

  final _tourTabsKey = GlobalKey();
  final _tourFilterKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    TourService.I.addListener(_maybeTour);
    _load();
  }

  @override
  void didUpdateWidget(covariant ActivitiesScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _load();
      _maybeTour();
    }
  }

  @override
  void dispose() {
    TourService.I.removeListener(_maybeTour);
    _title.dispose();
    super.dispose();
  }

  void _maybeTour() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active || _loading) return;
      final l = AppLocalizations.of(context);
      maybeShowTour(context, 'activities', [
        CoachMark(
          targetKey: _tourTabsKey,
          title: l.tourActTitle,
          body: l.tourActBody,
        ),
        CoachMark(
          targetKey: _tourFilterKey,
          title: l.tourCatTitle,
          body: l.tourCatBody,
        ),
      ]);
    });
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final data =
          await app.api.get('/api/activities?familyId=${app.familyId}');
      final list = data is List ? data : (data['activities'] as List? ?? []);
      Map<String, dynamic>? budget;
      try {
        final b = await app.api.get('/api/families/${app.familyId}/budget');
        budget = Map<String, dynamic>.from(b as Map);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _activities =
              list.cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
          _budget = budget;
          _coins = _baseScore.toDouble().clamp(1, double.infinity);
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

  // ── Budget economics (base score, min/max coins) ────────────────

  int get _baseScore {
    final rate = toNum(_budget?['baseRatePerHour']);
    return (rate * _durationMinutes / 60).round();
  }

  int get _minCoins => math.max(1, (_baseScore * 0.5).floor());
  int get _maxCoins => math.max(1, (_baseScore * 1.5).ceil());

  void _onDurationChanged(int minutes) {
    setState(() {
      _durationMinutes = minutes;
      if (_baseScore > 0) _coins = _baseScore.toDouble();
    });
  }

  String _durationLabel(AppLocalizations l, int mins) {
    final h = mins ~/ 60, m = mins % 60;
    if (h == 0) return l.durMins('$m');
    if (m == 0) return l.durHours(h);
    return l.durHoursMins(h, m);
  }

  Future<void> _create() async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    if (_title.text.trim().isEmpty) {
      app.setError(l.errNameFirst);
      return;
    }
    final ok = await app.runAction(() async {
      await app.api.post('/api/activities', {
        'familyId': app.familyId,
        'title': _title.text.trim(),
        'type': _type,
        'durationMinutes': _durationMinutes,
        'coinValue': _coins.round() > 0 ? _coins.round() : _baseScore,
        'isRecurrent': _isRecurrent,
      });
      await _load();
    }, l.toastTemplateCreated);
    if (ok) {
      _title.clear();
      setState(() => _tab = 0);
    }
  }

  Future<void> _approve(dynamic id) async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    await app.runAction(() async {
      await app.api.post('/api/activities/$id/approve');
      await _load();
    }, l.toastTemplateApproved);
  }

  Future<void> _delete(dynamic id) async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        title: Text(l.deleteActivityTitle,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(l.deleteActivityBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.deleteAction,
                  style: const TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    await app.runAction(() async {
      await app.api.delete('/api/activities/$id');
      await _load();
    }, l.toastTemplateDeleted);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error && _activities.isEmpty) {
      return LoadErrorState(onRetry: () {
        setState(() => _loading = true);
        _load();
      });
    }

    final l = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 16, bottom: 40),
        children: [
          PageHeading(title: l.actTitle, subtitle: l.actSubtitle),
          SegmentedTabs(
            key: _tourTabsKey,
            tabs: [l.tabCatalogue, l.tabNewActivity, l.tabBudget],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 20),
          if (_tab == 0) ..._buildCatalogue(),
          if (_tab == 1) _buildNewActivity(),
          if (_tab == 2) _buildBudget(),
        ],
      ),
    );
  }

  // ── Catalogue tab ────────────────────────────────────────────────

  List<Widget> _buildCatalogue() {
    final l = AppLocalizations.of(context);
    final templates =
        _activities.where((a) => a['is_template'] == true).toList()
          ..sort((a, b) => (a['title'] ?? '')
              .toString()
              .compareTo((b['title'] ?? '').toString()));
    final filtered = templates.where((a) {
      if (_filter == 1) return a['type'] == 'care';
      if (_filter == 2) return a['type'] == 'household';
      return true;
    }).toList();

    return [
      Row(
        key: _tourFilterKey,
        children: [
          for (final (i, label)
              in [l.filterAll, l.filterCare, l.filterHousehold].indexed)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: _filter == i,
                selectedColor: AppColors.primarySoft,
                labelStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _filter == i
                        ? AppColors.primaryInk
                        : AppColors.textSecondary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    side: BorderSide(
                        color: _filter == i
                            ? AppColors.primary
                            : AppColors.border)),
                onSelected: (_) => setState(() => _filter = i),
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      if (filtered.isEmpty)
        templates.isEmpty
            // Nothing in the catalogue at all: teach the first mechanic.
            ? EmptyState(
                icon: Icons.playlist_add_rounded,
                title: l.catEmptyTitle,
                body: l.catEmptyBody,
                actionLabel: l.catEmptyAction,
                onAction: () => setState(() => _tab = 1),
              )
            : EmptyState(
                icon: Icons.filter_list_off_rounded,
                title: l.filterEmptyTitle,
                body: l.filterEmptyBody,
              )
      else
        for (final a in filtered)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
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
                  decoration: BoxDecoration(
                      color: a['type'] == 'care'
                          ? AppColors.successSoft
                          : AppColors.warningSoft,
                      shape: BoxShape.circle),
                  child: Text(a['type'] == 'care' ? '❤️' : '🍽️',
                      style: const TextStyle(fontSize: 17)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                                '${a['title'] ?? ''}${a['is_recurrent'] == true ? ' 🔁' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800)),
                          ),
                          if (a['status'] == 'approved') ...[
                            const SizedBox(width: 6),
                            PillBadge(
                                text: l.badgeApproved,
                                fontSize: 12,
                                color: Colors.white,
                                background: AppColors.success),
                          ],
                        ],
                      ),
                      Text(
                          '${a['type'] == 'care' ? l.filterCare : l.filterHousehold} · ${_durationLabel(l, toNum(a['duration_minutes'] ?? a['durationMinutes']).toInt())} · 🪙 ${a['coin_value'] ?? a['coinValue'] ?? 0}cc',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (a['status'] == 'pending')
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: VButton(
                        type: VButtonType.outline,
                        onPressed: () => _approve(a['id']),
                        child: Text(l.approve)),
                  ),
                IconButton(
                  onPressed: () => _delete(a['id']),
                  tooltip: l.deleteAction,
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: AppColors.danger),
                ),
              ],
            ),
          ),
      const SizedBox(height: 12),
      VButton(
          type: VButtonType.secondary,
          block: true,
          onPressed: () => setState(() => _tab = 1),
          child: Text(l.newActivityBtn)),
    ];
  }

  // ── New Activity tab ─────────────────────────────────────────────

  Widget _buildNewActivity() {
    final l = AppLocalizations.of(context);
    return VCard(
      title: l.tabNewActivity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.newActivityIntro,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          VInput(
              controller: _title,
              label: l.fieldTitle,
              placeholder: l.activityTitleHint),
          const SizedBox(height: 16),
          Text(l.categoryLabel,
              style: const TextStyle(
                  fontSize: 13.6,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (value, label) in [
                ('care', l.catCareEmoji),
                ('household', l.catHouseholdEmoji)
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _type == value,
                    selectedColor: AppColors.primarySoft,
                    labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _type == value
                            ? AppColors.primaryInk
                            : AppColors.textSecondary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        side: BorderSide(
                            color: _type == value
                                ? AppColors.primary
                                : AppColors.border)),
                    onSelected: (_) => setState(() => _type = value),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(l.durationFieldLabel,
              style: const TextStyle(
                  fontSize: 13.6,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _durationMinutes,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (var i = 1; i <= 24; i++)
                DropdownMenuItem(
                    value: i * 30, child: Text(_durationLabel(l, i * 30))),
            ],
            onChanged: (v) {
              if (v != null) _onDurationChanged(v);
            },
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () => setState(() => _isRecurrent = !_isRecurrent),
            child: Row(
              children: [
                Checkbox(
                    value: _isRecurrent,
                    activeColor: AppColors.primary,
                    onChanged: (v) =>
                        setState(() => _isRecurrent = v ?? false)),
                Text(l.recurringCheckbox,
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const Divider(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l.coinValueLabel,
                  style: const TextStyle(
                      fontSize: 13.6, color: AppColors.textSecondary)),
              Text('${_coins.round()} cc',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
          Slider(
            value: _coins.clamp(_minCoins.toDouble(), _maxCoins.toDouble()),
            min: _minCoins.toDouble(),
            max: _maxCoins.toDouble(),
            divisions: math.max(1, _maxCoins - _minCoins),
            activeColor: AppColors.warning,
            onChanged: (v) => setState(() => _coins = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l.minLabel('$_minCoins'),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              Text(l.suggestedLabel('$_baseScore'),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              Text(l.maxLabel('$_maxCoins'),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 20),
          VButton(
              onPressed: _create,
              block: true,
              child: Text(l.createTemplateBtn)),
        ],
      ),
    );
  }

  // ── Budget tab ───────────────────────────────────────────────────

  Widget _buildBudget() {
    final l = AppLocalizations.of(context);
    final b = _budget;
    if (b == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(l.budgetUnavailable,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    final monthly = toNum(b['monthlyBudget']);
    final remaining = toNum(b['remainingBudget']);
    final used = toNum(b['usedThisMonth']);
    final rate = toNum(b['baseRatePerHour']);
    final fraction =
        monthly > 0 ? (remaining / monthly).clamp(0.0, 1.0) : 0.0;

    return VCard(
      title: l.budgetTitle,
      child: Column(
        children: [
          Text(l.remainingThisMonth,
              style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          SizedBox(
            width: 220,
            height: 130,
            child: CustomPaint(
              painter: _GaugePainter(fraction: fraction.toDouble()),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$remaining'),
                    const TextSpan(
                        text: ' cc',
                        style: TextStyle(
                            fontSize: 18, color: AppColors.primary)),
                  ]),
                  style: const TextStyle(
                      fontSize: 40, fontWeight: FontWeight.w800, height: 1),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.bg,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (final (label, value, color) in [
                  (l.totalMonthlyPool, '$monthly cc', AppColors.textPrimary),
                  (l.scheduledUsed, '$used cc', AppColors.textPrimary),
                  (l.estimatedRate, l.ratePerHour('$rate'), AppColors.warning),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(label,
                            style: const TextStyle(
                                color: AppColors.textSecondary)),
                        Text(value,
                            style: TextStyle(
                                fontWeight: FontWeight.w800, color: color)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Semicircular budget gauge.
class _GaugePainter extends CustomPainter {
  final double fraction;

  _GaugePainter({required this.fraction});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 10);
    final radius = math.min(size.width / 2 - 14, size.height - 24);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = AppColors.border;
    canvas.drawArc(rect, math.pi, math.pi, false, track);

    if (fraction > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..color = AppColors.primary;
      canvas.drawArc(rect, math.pi, math.pi * fraction, false, arc);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.fraction != fraction;
}
