import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/json.dart';
import '../widgets/ui.dart';

/// Platform admin console (docs/admin-family-management-plan.md Phase 5).
///
/// Registry + billing oversight only: these screens render family liveness,
/// plan and grant state — never members, tasks or coins. The backend enforces
/// the same boundary; the /api/admin endpoints simply have nothing more to
/// show. Entry is gated in ProfileScreen by AppState.isPlatformAdmin, and the
/// server re-checks the role on every call.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(l.adminTitle,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SegmentedTabs(
              tabs: [l.adminTabFamilies, l.adminTabPlans],
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          Expanded(
              child: _tab == 0 ? const _FamiliesTab() : const _PlansTab()),
        ],
      ),
    );
  }
}

String _fmtDate(BuildContext context, dynamic iso) {
  final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (d == null) return '—';
  return DateFormat('d MMM yyyy', Localizations.localeOf(context).toString())
      .format(d);
}

(Color, Color) _statusColors(String status) => switch (status) {
      'active' => (AppColors.successInk, AppColors.successSoft),
      'dormant' => (AppColors.warningInk, AppColors.warningSoft),
      _ => (AppColors.dangerInk, AppColors.dangerSoft),
    };

String _statusLabel(AppLocalizations l, String status) => switch (status) {
      'active' => l.adminStatusActive,
      'dormant' => l.adminStatusDormant,
      _ => l.adminStatusInactive,
    };

// ─── Families tab ───────────────────────────────────────────────────────────

class _FamiliesTab extends StatefulWidget {
  const _FamiliesTab();

  @override
  State<_FamiliesTab> createState() => _FamiliesTabState();
}

class _FamiliesTabState extends State<_FamiliesTab> {
  static const _pageSize = 20;
  static const _statusFilters = ['', 'active', 'dormant', 'inactive'];

  final _search = TextEditingController();
  int _filter = 0;
  List<dynamic> _families = [];
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    setState(() {
      _loading = true;
      _error = false;
      if (!append) _page = 1;
    });
    try {
      final api = context.read<AppState>().api;
      final q = Uri(queryParameters: {
        if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
        if (_statusFilters[_filter].isNotEmpty) 'status': _statusFilters[_filter],
        'page': '$_page',
        'pageSize': '$_pageSize',
      }).query;
      final data = await api.get('/api/admin/families?$q');
      if (!mounted) return;
      setState(() {
        final rows = (data['families'] as List?) ?? [];
        _families = append ? [..._families, ...rows] : rows;
        _total = toNum(data['total']).toInt();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_error && _families.isEmpty) {
      return LoadErrorState(onRetry: _load);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        VInput(
          controller: _search,
          placeholder: l.adminSearchHint,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
        ),
        const SizedBox(height: 12),
        SegmentedTabs(
          tabs: [
            l.adminFilterAll,
            l.adminStatusActive,
            l.adminStatusDormant,
            l.adminStatusInactive,
          ],
          selected: _filter,
          onChanged: (i) {
            setState(() => _filter = i);
            _load();
          },
        ),
        const SizedBox(height: 16),
        if (_loading && _families.isEmpty)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_families.isEmpty)
          EmptyState(
            icon: Icons.family_restroom_rounded,
            title: l.adminNoFamiliesTitle,
            body: l.adminNoFamiliesBody,
          )
        else ...[
          for (final fam in _families) _familyRow(context, l, fam as Map),
          if (_families.length < _total)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: VButton(
                type: VButtonType.outline,
                block: true,
                disabled: _loading,
                onPressed: () {
                  _page += 1;
                  _load(append: true);
                },
                child: Text(l.adminLoadMore),
              ),
            ),
        ],
      ],
    );
  }

  Widget _familyRow(BuildContext context, AppLocalizations l, Map fam) {
    final status = fam['status']?.toString() ?? 'inactive';
    final (fg, bg) = _statusColors(status);
    return VCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Tappable(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AdminFamilyDetailScreen(
                  familyId: toNum(fam['id']).toInt(),
                  name: fam['name']?.toString() ?? '')));
          _load();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${fam['name']} · #${fam['id']}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PillBadge(
                    text: _statusLabel(l, status), color: fg, background: bg),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(l.adminMembersCount(toNum(fam['memberCount']).toInt()),
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary)),
                Text(l.adminLastActive(_fmtDate(context, fam['lastActiveAt'])),
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary)),
                if (fam['planCode'] != null)
                  PillBadge(
                      text: fam['planCode'].toString(),
                      color: AppColors.primaryInk,
                      background: AppColors.primarySoft,
                      fontSize: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Family detail ──────────────────────────────────────────────────────────

class AdminFamilyDetailScreen extends StatefulWidget {
  final int familyId;
  final String name;

  const AdminFamilyDetailScreen(
      {super.key, required this.familyId, required this.name});

  @override
  State<AdminFamilyDetailScreen> createState() =>
      _AdminFamilyDetailScreenState();
}

class _AdminFamilyDetailScreenState extends State<AdminFamilyDetailScreen> {
  Map<String, dynamic>? _registry;
  Map<String, dynamic>? _billing;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final api = context.read<AppState>().api;
      final results = await Future.wait([
        api.get('/api/admin/families/${widget.familyId}'),
        api.get('/api/admin/families/${widget.familyId}/billing'),
      ]);
      if (!mounted) return;
      setState(() {
        _registry = (results[0] as Map).cast<String, dynamic>();
        _billing = (results[1] as Map).cast<String, dynamic>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _notifyInactive() async {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminNotifyInactiveBtn),
        content: Text(l.adminNotifyInactiveConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel)),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.confirm)),
        ],
      ),
    );
    if (ok != true) return;
    await app.runAction(() async {
      await app.api
          .post('/api/admin/families/${widget.familyId}/notify-inactive');
    }, l.adminNotifySent);
  }

  Future<void> _grantPlan() async {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    List plans;
    try {
      final data = await app.api.get('/api/admin/plans');
      plans = ((data['plans'] as List?) ?? [])
          .where((p) => p['active'] == true)
          .toList();
    } catch (_) {
      return;
    }
    if (plans.isEmpty || !mounted) return;

    final reason = TextEditingController();
    final days = TextEditingController();
    String planCode = plans.first['code'].toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l.adminGrantBtn),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<String>(
                value: planCode,
                isExpanded: true,
                items: [
                  for (final p in plans)
                    DropdownMenuItem(
                        value: p['code'].toString(),
                        child: Text('${p['name']} (${p['code']})')),
                ],
                onChanged: (v) =>
                    setDialogState(() => planCode = v ?? planCode),
              ),
              const SizedBox(height: 10),
              VInput(controller: reason, label: l.adminGrantReasonLabel),
              const SizedBox(height: 10),
              VInput(
                  controller: days,
                  label: l.adminGrantExpiresLabel,
                  keyboardType: TextInputType.number),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.cancel)),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.confirm)),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final expiresDays = int.tryParse(days.text.trim());
    final done = await app.runAction(() async {
      await app.api.post('/api/admin/families/${widget.familyId}/grants', {
        'planCode': planCode,
        if (reason.text.trim().isNotEmpty) 'reason': reason.text.trim(),
        if (expiresDays != null && expiresDays > 0)
          'expiresAt': DateTime.now()
              .add(Duration(days: expiresDays))
              .toUtc()
              .toIso8601String(),
      });
    }, l.adminGrantCreated);
    if (done) _load();
  }

  Future<void> _revokeGrant(int grantId) async {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    final done = await app.runAction(() async {
      await app.api
          .delete('/api/admin/families/${widget.familyId}/grants/$grantId');
    }, l.adminGrantRevokedToast);
    if (done) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.name,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? LoadErrorState(onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _registryCard(l),
                    _subscriptionCard(l),
                    _grantsCard(l),
                    _eventsCard(l),
                  ],
                ),
    );
  }

  Widget _kv(String label, Widget value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary))),
            value,
          ],
        ),
      );

  Text _v(String text) => Text(text,
      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700));

  Widget _registryCard(AppLocalizations l) {
    final r = _registry!;
    final status = r['status']?.toString() ?? 'inactive';
    final (fg, bg) = _statusColors(status);
    return VCard(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('#${r['id']}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary)),
              ),
              PillBadge(
                  text: _statusLabel(l, status), color: fg, background: bg),
            ],
          ),
          const SizedBox(height: 8),
          _kv(l.adminCreatedLabel, _v(_fmtDate(context, r['createdAt']))),
          _kv(l.adminLastActiveLabel,
              _v(_fmtDate(context, r['lastActiveAt']))),
          _kv(l.adminMembersLabel,
              _v('${toNum(r['memberCount']).toInt()}')),
          _kv(l.adminPendingLabel,
              _v('${toNum(r['pendingMemberCount']).toInt()}')),
          _kv(l.adminActorsLabel, _v('${toNum(r['actorCount']).toInt()}')),
          if (status != 'active') ...[
            const SizedBox(height: 12),
            VButton(
              type: VButtonType.outline,
              block: true,
              onPressed: _notifyInactive,
              child: Text(l.adminNotifyInactiveBtn),
            ),
          ],
        ],
      ),
    );
  }

  Widget _subscriptionCard(AppLocalizations l) {
    final sub =
        (_billing!['subscription'] as Map?)?.cast<String, dynamic>();
    return VCard(
      title: l.adminBillingTitle,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      margin: const EdgeInsets.only(bottom: 16),
      child: sub == null
          ? Text(l.adminNoSubscription,
              style: const TextStyle(
                  fontSize: 13.5, color: AppColors.textSecondary, height: 1.5))
          : Column(
              children: [
                _kv(l.adminPlanLabel, _v(sub['planCode']?.toString() ?? '—')),
                _kv(l.adminStatusColLabel,
                    _v(sub['status']?.toString() ?? '—')),
                if (sub['platform'] != null)
                  _kv(l.adminPlatformLabel, _v(sub['platform'].toString())),
                if (sub['provider'] != null)
                  _kv(l.adminProviderLabel, _v(sub['provider'].toString())),
                if (sub['currentPeriodEnd'] != null)
                  _kv(l.adminPeriodEndLabel,
                      _v(_fmtDate(context, sub['currentPeriodEnd']))),
              ],
            ),
    );
  }

  Widget _grantsCard(AppLocalizations l) {
    final grants = (_billing!['grants'] as List?) ?? [];
    return VCard(
      title: l.adminGrantsTitle,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (grants.isEmpty)
            Text(l.adminNoGrants,
                style: const TextStyle(
                    fontSize: 13.5, color: AppColors.textSecondary))
          else
            for (final g in grants.cast<Map>())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    PillBadge(
                        text: g['planCode'].toString(),
                        color: AppColors.primaryInk,
                        background: AppColors.primarySoft,
                        fontSize: 12),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          if ((g['reason'] ?? '').toString().isNotEmpty)
                            g['reason'].toString(),
                          if (g['expiresAt'] != null)
                            _fmtDate(context, g['expiresAt']),
                          if (g['revokedAt'] != null) l.adminGrantRevoked,
                        ].join(' · '),
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (g['revokedAt'] == null)
                      TextButton(
                        onPressed: () =>
                            _revokeGrant(toNum(g['id']).toInt()),
                        child: Text(l.adminRevokeBtn,
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.danger)),
                      ),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          VButton(
            type: VButtonType.outline,
            block: true,
            onPressed: _grantPlan,
            child: Text(l.adminGrantBtn),
          ),
        ],
      ),
    );
  }

  Widget _eventsCard(AppLocalizations l) {
    final events = (_billing!['recentEvents'] as List?) ?? [];
    return VCard(
      title: l.adminEventsTitle,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: events.isEmpty
          ? Text(l.adminNoEvents,
              style: const TextStyle(
                  fontSize: 13.5, color: AppColors.textSecondary))
          : Column(
              children: [
                for (final e in events.cast<Map>())
                  _kv('${e['eventType']} · ${e['provider']}',
                      _v(_fmtDate(context, e['createdAt']))),
              ],
            ),
    );
  }
}

// ─── Plans tab ──────────────────────────────────────────────────────────────

class _PlansTab extends StatefulWidget {
  const _PlansTab();

  @override
  State<_PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<_PlansTab> {
  List<dynamic> _plans = [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final data = await context.read<AppState>().api.get('/api/admin/plans');
      if (!mounted) return;
      setState(() {
        _plans = (data['plans'] as List?) ?? [];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _editPlan([Map? plan]) async {
    final l = AppLocalizations.of(context);
    final app = context.read<AppState>();
    final isNew = plan == null;
    final limits = (plan?['limits'] as Map?) ?? {};

    final code = TextEditingController(text: plan?['code']?.toString() ?? '');
    final name = TextEditingController(text: plan?['name']?.toString() ?? '');
    final price = TextEditingController(
        text: plan == null ? '0' : toNum(plan['priceCents']).toInt().toString());
    final maxMembers = TextEditingController(
        text: limits['max_members']?.toString() ?? '');
    final maxActors =
        TextEditingController(text: limits['max_actors']?.toString() ?? '');
    final maxRewards = TextEditingController(
        text: limits['max_active_rewards']?.toString() ?? '');
    String period = plan?['billingPeriod']?.toString() ?? 'monthly';
    bool isDefault = plan?['isDefault'] == true;
    bool active = plan == null || plan['active'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isNew ? l.adminNewPlanBtn : l.adminEditPlanTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isNew) ...[
                  VInput(controller: code, label: l.adminPlanCodeLabel),
                  const SizedBox(height: 10),
                ],
                VInput(controller: name, label: l.adminPlanNameLabel),
                const SizedBox(height: 10),
                VInput(
                    controller: price,
                    label: l.adminPlanPriceLabel,
                    keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                Text(l.adminPlanPeriodLabel,
                    style: const TextStyle(
                        fontSize: 13.6,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500)),
                DropdownButton<String>(
                  value: period,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                        value: 'monthly', child: Text(l.adminPeriodMonthly)),
                    DropdownMenuItem(
                        value: 'yearly', child: Text(l.adminPeriodYearly)),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => period = v ?? period),
                ),
                const SizedBox(height: 10),
                VInput(
                    controller: maxMembers,
                    label: l.adminLimitMembersLabel,
                    keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                VInput(
                    controller: maxActors,
                    label: l.adminLimitActorsLabel,
                    keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                VInput(
                    controller: maxRewards,
                    label: l.adminLimitRewardsLabel,
                    keyboardType: TextInputType.number),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.primary,
                  title: Text(l.adminPlanDefaultLabel,
                      style: const TextStyle(fontSize: 13.5)),
                  value: isDefault,
                  onChanged: (v) => setDialogState(() => isDefault = v),
                ),
                if (!isNew)
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.primary,
                    title: Text(l.adminPlanActiveLabel,
                        style: const TextStyle(fontSize: 13.5)),
                    value: active,
                    onChanged: (v) => setDialogState(() => active = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.cancel)),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.adminSaveBtn)),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final newLimits = <String, dynamic>{
      if (int.tryParse(maxMembers.text.trim()) != null)
        'max_members': int.parse(maxMembers.text.trim()),
      if (int.tryParse(maxActors.text.trim()) != null)
        'max_actors': int.parse(maxActors.text.trim()),
      if (int.tryParse(maxRewards.text.trim()) != null)
        'max_active_rewards': int.parse(maxRewards.text.trim()),
    };
    final body = {
      'name': name.text.trim(),
      'priceCents': int.tryParse(price.text.trim()) ?? 0,
      'billingPeriod': period,
      'limits': newLimits,
      'isDefault': isDefault,
      'active': active,
    };

    final done = await app.runAction(() async {
      if (isNew) {
        await app.api
            .post('/api/admin/plans', {...body, 'code': code.text.trim()});
      } else {
        await app.api.patch('/api/admin/plans/${plan['code']}', body);
      }
    }, l.adminPlanSaved);
    if (done) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) return LoadErrorState(onRetry: _load);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        for (final p in _plans.cast<Map>())
          VCard(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            child: Tappable(
              onTap: () => _editPlan(p),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${p['name']} · ${p['code']}',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (p['isDefault'] == true)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: PillBadge(
                              text: l.adminDefaultBadge,
                              color: AppColors.primaryInk,
                              background: AppColors.primarySoft,
                              fontSize: 12),
                        ),
                      if (p['active'] != true)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: PillBadge(
                              text: l.adminInactiveBadge,
                              color: AppColors.dangerInk,
                              background: AppColors.dangerSoft,
                              fontSize: 12),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    toNum(p['priceCents']).toInt() == 0
                        ? l.adminPriceFree
                        : '${(toNum(p['priceCents']).toInt() / 100).toStringAsFixed(2)} ${p['currency']} / ${p['billingPeriod'] == 'yearly' ? l.adminPeriodYearly : l.adminPeriodMonthly}',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        VButton(
          type: VButtonType.outline,
          block: true,
          onPressed: () => _editPlan(),
          child: Text(l.adminNewPlanBtn),
        ),
      ],
    );
  }
}
