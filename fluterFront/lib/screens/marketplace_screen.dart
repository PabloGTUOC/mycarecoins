import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/tour_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/coach_marks.dart';
import '../widgets/ui.dart';
import '../utils/json.dart';

/// Marketplace: Store / History / Create tabs,
/// reward cards with rotating banner colours, redeem flow.
class MarketplaceScreen extends StatefulWidget {
  /// Whether this is the visible tab; becoming active triggers a refetch.
  final bool active;

  const MarketplaceScreen({super.key, this.active = true});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  int _tab = 0;
  bool _loading = true;
  bool _error = false;
  List<Map<String, dynamic>> _rewards = [];
  List<Map<String, dynamic>> _claimed = [];

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _cost = TextEditingController();
  final _maxUses = TextEditingController();
  DateTime? _validFrom;
  DateTime? _validUntil;

  static const _bannerColors = [
    AppColors.primarySoft,
    AppColors.successSoft,
    AppColors.warningSoft,
    AppColors.dangerSoft,
    Color(0xFFEDE9FE), // violet-soft, 5th banner variant
  ];

  final _tourTabsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    TourService.I.addListener(_maybeTour);
    _load();
  }

  @override
  void didUpdateWidget(covariant MarketplaceScreen old) {
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
      maybeShowTour(context, 'marketplace', [
        CoachMark(
          targetKey: _tourTabsKey,
          title: l.tourMktTitle,
          body: l.tourMktBody,
        ),
      ]);
    });
  }

  @override
  void dispose() {
    TourService.I.removeListener(_maybeTour);
    _title.dispose();
    _description.dispose();
    _cost.dispose();
    _maxUses.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final data =
          await app.api.get('/api/marketplace/rewards/${app.familyId}');
      List rewards = [];
      List claimed = [];
      if (data is List) {
        rewards = data;
      } else if (data is Map) {
        rewards = (data['rewards'] as List?) ?? [];
        claimed =
            (data['claimed'] as List?) ?? (data['redemptions'] as List?) ?? [];
      }
      if (mounted) {
        setState(() {
          _rewards = rewards
              .cast<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList();
          _claimed = claimed
              .cast<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList();
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

  Future<void> _redeem(Map<String, dynamic> r) async {
    final app = context.read<AppState>();
    await app.runAction(() async {
      await app.api.post('/api/marketplace/rewards/${r['id']}/redeem');
      await Future.wait([_load(), app.fetchUserData()]);
    }, AppLocalizations.of(context).toastRewardRedeemed);
  }

  Future<void> _create() async {
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    if (_title.text.trim().isEmpty || _cost.text.trim().isEmpty) {
      app.setError(l.errTitleCostRequired);
      return;
    }
    final ok = await app.runAction(() async {
      await app.api.post('/api/marketplace/rewards', {
        'familyId': app.familyId,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'cost': int.tryParse(_cost.text) ?? 0,
        if (_maxUses.text.trim().isNotEmpty)
          'maxUses': int.tryParse(_maxUses.text),
        if (_validFrom != null)
          'validFrom': _validFrom!.toUtc().toIso8601String(),
        if (_validUntil != null)
          'validUntil': _validUntil!.toUtc().toIso8601String(),
      });
      await _load();
    }, l.toastRewardCreated);
    if (ok) {
      _title.clear();
      _description.clear();
      _cost.clear();
      _maxUses.clear();
      setState(() {
        _validFrom = null;
        _validUntil = null;
        _tab = 0;
      });
    }
  }

  Future<void> _pickValidity(bool from) async {
    final initial = (from ? _validFrom : _validUntil) ?? DateTime.now();
    final d = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 365 * 2)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    final picked =
        DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
    setState(() {
      if (from) {
        _validFrom = picked;
      } else {
        _validUntil = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error && _rewards.isEmpty && _claimed.isEmpty) {
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
          PageHeading(title: l.navMarketplace, subtitle: l.mktSubtitle),
          SegmentedTabs(
            key: _tourTabsKey,
            tabs: app.isCaregiver
                ? [l.tabStore, l.tabHistory, l.tabCreate]
                : [l.tabStore, l.tabHistory],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 24),
          if (_tab == 0) _buildStore(),
          if (_tab == 1) _buildHistory(),
          if (_tab == 2) _buildCreate(),
        ],
      ),
    );
  }

  Widget _buildStore() {
    if (_rewards.isEmpty) {
      final isCaregiver = context.read<AppState>().isCaregiver;
      final l = AppLocalizations.of(context);
      return EmptyState(
        icon: Icons.storefront_rounded,
        title: l.storeEmptyTitle,
        body: isCaregiver ? l.storeEmptyBodyCaregiver : l.storeEmptyBodyMember,
        actionLabel: isCaregiver ? l.createReward : null,
        onAction: isCaregiver ? () => setState(() => _tab = 2) : null,
      );
    }
    return LayoutBuilder(builder: (context, c) {
      final perRow = c.maxWidth > kMobileBreakpoint ? 3 : 1;
      final w = (c.maxWidth - (perRow - 1) * 16) / perRow;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (var i = 0; i < _rewards.length; i++)
            SizedBox(
                width: w,
                child: _RewardCard(
                    r: _rewards[i],
                    banner: _bannerColors[(_rewards[i]['id'].hashCode) % 5],
                    onRedeem: () => _redeem(_rewards[i]))),
        ],
      );
    });
  }

  Widget _buildHistory() {
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    if (_claimed.isEmpty) {
      return EmptyState(
        icon: Icons.history_rounded,
        title: l.historyEmptyTitle,
        body: l.historyEmptyBody,
      );
    }
    return Column(
      children: [
        for (final cRow in _claimed)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.inputBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                AvatarCircle(
                    name: (cRow['buyer_name'] ?? '?').toString(),
                    imageUrl: cRow['buyer_avatar']?.toString(),
                    size: 45),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((cRow['buyer_name'] ?? l.fallbackSomeone).toString(),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(
                          l.redeemedQuoted(
                              (cRow['title'] ?? l.fallbackAReward).toString()),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (cRow['redeemed_at'] != null)
                      Text(
                          DateFormat('d MMM yyyy · HH:mm', loc).format(
                              DateTime.tryParse(
                                          cRow['redeemed_at'].toString())
                                      ?.toLocal() ??
                                  DateTime.now()),
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary)),
                    const SizedBox(height: 3),
                    PillBadge(
                        text: '-${cRow['cost'] ?? 0} cc',
                        color: AppColors.danger,
                        background: AppColors.dangerSoft,
                        fontSize: 11),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCreate() {
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    return VCard(
      title: l.createRewardTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VInput(
              controller: _title,
              label: l.fieldTitle,
              placeholder: l.rewardTitleHint),
          const SizedBox(height: 14),
          VInput(
              controller: _description,
              label: l.descriptionLabel,
              placeholder: l.rewardDescHint,
              pill: false,
              maxLines: 3),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: VInput(
                      controller: _cost,
                      label: l.costLabel,
                      placeholder: '50',
                      keyboardType: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(
                  child: VInput(
                      controller: _maxUses,
                      label: l.maxUsesLabel,
                      placeholder: '∞',
                      keyboardType: TextInputType.number)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final (label, from, value) in [
                (l.validFrom, true, _validFrom),
                (l.validUntil, false, _validUntil),
              ])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: from ? 12 : 0),
                    child: OutlinedButton.icon(
                      onPressed: () => _pickValidity(from),
                      icon: const Icon(Icons.event_rounded, size: 16),
                      label: Text(
                          value == null
                              ? l.fieldOptional(label)
                              : l.fieldWithDate(label,
                                  DateFormat('d MMM HH:mm', loc).format(value)),
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          VButton(
              onPressed: _create,
              block: true,
              child: Text(l.createRewardBtn)),
        ],
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  final Map<String, dynamic> r;
  final Color banner;
  final VoidCallback onRedeem;

  const _RewardCard(
      {required this.r, required this.banner, required this.onRedeem});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final loc = l.localeName;
    final uses = toNum(r['uses']);
    final maxUses = toNumOrNull(r['max_uses']);
    final soldOut = maxUses != null && uses >= maxUses;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 84,
            color: banner,
            alignment: Alignment.center,
            child: const Text('🎁', style: TextStyle(fontSize: 34)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((r['title'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                if ((r['description'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(r['description'].toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.5)),
                ],
                if (maxUses != null || r['valid_until'] != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (maxUses != null)
                        PillBadge(
                            text: soldOut ? l.soldOut : l.nLeft(maxUses - uses),
                            color:
                                soldOut ? AppColors.danger : AppColors.warning,
                            background: soldOut
                                ? AppColors.dangerSoft
                                : AppColors.warningSoft,
                            fontSize: 11),
                      if (r['valid_until'] != null)
                        PillBadge(
                            text: l.expires(DateFormat('d MMM yyyy', loc)
                                .format(DateTime.tryParse(
                                            r['valid_until'].toString())
                                        ?.toLocal() ??
                                    DateTime.now())),
                            color: AppColors.danger,
                            background: AppColors.dangerSoft,
                            fontSize: 11),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${r['cost'] ?? 0}',
                            style: const TextStyle(
                                fontSize: 17.6,
                                fontWeight: FontWeight.w800,
                                color: AppColors.warning)),
                        const SizedBox(width: 3),
                        const Text('cc',
                            style: TextStyle(
                                fontSize: 12.8,
                                fontWeight: FontWeight.w700,
                                color: AppColors.warning)),
                      ],
                    ),
                    VButton(
                        disabled: soldOut,
                        onPressed: onRedeem,
                        child: Text(l.buy,
                            style: const TextStyle(fontSize: 14))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
