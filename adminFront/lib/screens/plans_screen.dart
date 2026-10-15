import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../strings.dart';
import '../theme.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _plans = [];

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await context.read<AppState>().api.get('/plans');
      if (!mounted) return;
      final raw = (data['plans'] as List?) ?? [];
      setState(() {
        _plans = raw.map((p) => (p as Map).cast<String, dynamic>()).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Strings.errGenericFallback;
      });
    }
  }

  Future<void> _openPlanDialog([Map<String, dynamic>? existingPlan]) async {
    final isNew = existingPlan == null;
    final limits = (existingPlan?['limits'] as Map?) ?? {};

    final codeCtrl = TextEditingController(
      text: existingPlan?['code']?.toString() ?? '',
    );
    final nameCtrl = TextEditingController(
      text: existingPlan?['name']?.toString() ?? '',
    );
    final priceCtrl = TextEditingController(
      text: (existingPlan?['priceCents'] as num?)?.toInt().toString() ?? '0',
    );
    final maxMembersCtrl = TextEditingController(
      text: limits['max_members']?.toString() ?? '',
    );
    final maxActorsCtrl = TextEditingController(
      text: limits['max_actors']?.toString() ?? '',
    );
    final maxRewardsCtrl = TextEditingController(
      text: limits['max_active_rewards']?.toString() ?? '',
    );

    String period = existingPlan?['billingPeriod']?.toString() ?? 'monthly';
    bool isDefault = existingPlan?['isDefault'] == true;
    bool active = existingPlan == null || existingPlan['active'] == true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            isNew ? Strings.newPlanDialogTitle : Strings.editPlanDialogTitle,
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: codeCtrl,
                    enabled: isNew,
                    decoration: InputDecoration(
                      labelText: Strings.planCodeLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: Strings.planNameLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: Strings.planPriceLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    Strings.planPeriodLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButton<String>(
                    value: period,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(
                        value: 'monthly',
                        child: Text(Strings.periodMonthly),
                      ),
                      DropdownMenuItem(
                        value: 'yearly',
                        child: Text(Strings.periodYearly),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => period = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: maxMembersCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: Strings.planLimitMembersLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: maxActorsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: Strings.planLimitActorsLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: maxRewardsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: Strings.planLimitRewardsLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(Strings.planDefaultLabel),
                    value: isDefault,
                    onChanged: (val) => setDialogState(() => isDefault = val),
                  ),
                  SwitchListTile(
                    title: Text(Strings.planActiveLabel),
                    value: active,
                    onChanged: (val) => setDialogState(() => active = val),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(Strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(Strings.save),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final parsedLimits = <String, dynamic>{
      if (int.tryParse(maxMembersCtrl.text.trim()) != null)
        'max_members': int.parse(maxMembersCtrl.text.trim()),
      if (int.tryParse(maxActorsCtrl.text.trim()) != null)
        'max_actors': int.parse(maxActorsCtrl.text.trim()),
      if (int.tryParse(maxRewardsCtrl.text.trim()) != null)
        'max_active_rewards': int.parse(maxRewardsCtrl.text.trim()),
    };

    final payload = <String, dynamic>{
      'name': nameCtrl.text.trim(),
      'priceCents': int.tryParse(priceCtrl.text.trim()) ?? 0,
      'billingPeriod': period,
      'limits': parsedLimits,
      'isDefault': isDefault,
      'active': active,
    };

    final app = context.read<AppState>();
    final done = await app.runMutation(
      context,
      () async {
        if (isNew) {
          await app.api.post('/plans', {
            ...payload,
            'code': codeCtrl.text.trim(),
          });
        } else {
          await app.api.patch('/plans/${existingPlan['code']}', payload);
        }
      },
      successMessage: Strings.planSaveSuccess,
    );

    if (done && mounted) {
      _loadPlans();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  Strings.plansTitle,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: Strings.retry,
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _loadPlans,
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _openPlanDialog(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(Strings.newPlanBtn),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _error != null
                        ? Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _loadPlans,
                                  child: Text(Strings.retry),
                                ),
                              ],
                            ),
                          )
                        : _plans.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(48),
                                child: Center(
                                  child: Text(
                                    Strings.noData,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: [
                                    DataColumn(
                                        label: Text(Strings.colPlanCode)),
                                    DataColumn(
                                        label: Text(Strings.colPlanName)),
                                    DataColumn(
                                        label: Text(Strings.colPlanPrice)),
                                    DataColumn(
                                        label: Text(Strings.colPlanPeriod)),
                                    DataColumn(
                                        label: Text(Strings.colPlanDefault)),
                                    DataColumn(
                                        label: Text(Strings.colPlanActive)),
                                    DataColumn(
                                        label: Text(Strings.colActions)),
                                  ],
                                  rows: [
                                    for (final p in _plans)
                                      DataRow(
                                        cells: [
                                          DataCell(
                                            Text(
                                              p['code']?.toString() ??
                                                  Strings.emptyDash,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              p['name']?.toString() ??
                                                  Strings.emptyDash,
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              Strings.formatPrice(
                                                (p['priceCents'] as num?)
                                                        ?.toInt() ??
                                                    0,
                                                p['currency']?.toString() ??
                                                    'EUR',
                                                p['billingPeriod']
                                                        ?.toString() ??
                                                    'monthly',
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              p['billingPeriod'] == 'yearly'
                                                  ? Strings.periodYearly
                                                  : Strings.periodMonthly,
                                            ),
                                          ),
                                          DataCell(
                                            p['isDefault'] == true
                                                ? Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          AppColors.primarySoft,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        AppRadii.pill,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      Strings.badgeDefault,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color:
                                                            AppColors.primaryInk,
                                                      ),
                                                    ),
                                                  )
                                                : Text(Strings.emptyDash),
                                          ),
                                          DataCell(
                                            Text(
                                              p['active'] == true
                                                  ? Strings.badgeActive
                                                  : Strings.badgeInactive,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: p['active'] == true
                                                    ? AppColors.successInk
                                                    : AppColors.dangerInk,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            TextButton(
                                              onPressed: () =>
                                                  _openPlanDialog(p),
                                              child: Text(Strings.editPlanBtn),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
