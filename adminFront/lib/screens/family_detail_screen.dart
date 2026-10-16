import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../strings.dart';
import '../theme.dart';

class FamilyDetailScreen extends StatefulWidget {
  final int familyId;
  final String initialName;

  const FamilyDetailScreen({
    super.key,
    required this.familyId,
    required this.initialName,
  });

  @override
  State<FamilyDetailScreen> createState() => _FamilyDetailScreenState();
}

class _FamilyDetailScreenState extends State<FamilyDetailScreen> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _registry;
  Map<String, dynamic>? _billing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<AppState>().api;
      final results = await Future.wait([
        api.get('/families/${widget.familyId}'),
        api.get('/families/${widget.familyId}/billing'),
      ]);

      if (!mounted) return;
      setState(() {
        _registry = results[0];
        _billing = results[1];
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

  Future<void> _notifyInactive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.notifyInactiveConfirmTitle),
        content: Text(Strings.notifyInactiveConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(Strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(Strings.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final app = context.read<AppState>();
    final done = await app.runMutation(
      context,
      () => app.api.post('/families/${widget.familyId}/notify-inactive'),
      successMessage: Strings.notifyInactiveQueued,
    );

    if (done && mounted) {
      _load();
    }
  }

  Future<void> _grantPlan() async {
    final app = context.read<AppState>();
    List<Map<String, dynamic>> plans = [];

    try {
      final data = await app.api.get('/plans');
      final list = (data['plans'] as List?) ?? [];
      plans = list
          .map((p) => (p as Map).cast<String, dynamic>())
          .where((p) => p['active'] == true)
          .toList();
    } catch (_) {
      return;
    }

    if (plans.isEmpty || !mounted) return;

    String selectedPlan = plans.first['code']?.toString() ?? '';
    final reasonController = TextEditingController();
    final daysController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(Strings.grantPlanDialogTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Strings.grantPlanPickerLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButton<String>(
                  value: selectedPlan,
                  isExpanded: true,
                  items: [
                    for (final p in plans)
                      DropdownMenuItem(
                        value: p['code'].toString(),
                        child: Text(
                          Strings.planOption(p['name'], p['code']),
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedPlan = val);
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reasonController,
                  decoration: InputDecoration(
                    labelText: Strings.grantReasonLabel,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: daysController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: Strings.grantExpiresDaysLabel,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(Strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(Strings.confirm),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final days = int.tryParse(daysController.text.trim());
    final payload = <String, dynamic>{
      'planCode': selectedPlan,
      if (reasonController.text.trim().isNotEmpty)
        'reason': reasonController.text.trim(),
      if (days != null && days > 0)
        'expiresAt':
            DateTime.now().add(Duration(days: days)).toUtc().toIso8601String(),
    };

    final done = await app.runMutation(
      context,
      () => app.api.post('/families/${widget.familyId}/grants', payload),
      successMessage: Strings.grantSuccess,
    );

    if (done && mounted) {
      _load();
    }
  }

  Future<void> _revokeGrant(int grantId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Strings.revokeGrantConfirmTitle),
        content: Text(Strings.revokeGrantConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(Strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(Strings.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final app = context.read<AppState>();
    final done = await app.runMutation(
      context,
      () => app.api.delete('/families/${widget.familyId}/grants/$grantId'),
      successMessage: Strings.revokeGrantSuccess,
    );

    if (done && mounted) {
      _load();
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistryCard() {
    final r = _registry!;
    final status = r['status']?.toString() ?? 'inactive';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  Strings.registryCardTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (status != 'active')
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.warningStrong,
                    ),
                    onPressed: _notifyInactive,
                    icon: const Icon(Icons.notifications_active_rounded, size: 16),
                    label: Text(Strings.notifyInactiveBtn),
                  ),
              ],
            ),
            const Divider(height: 24),
            _infoRow(Strings.colId, Strings.formatId(r['id'])),
            _infoRow(Strings.colName, r['name']?.toString() ?? Strings.emptyDash),
            _infoRow(Strings.colHeartbeat, status.toUpperCase()),
            _infoRow(Strings.colCreated, Strings.formatDate(r['createdAt'])),
            _infoRow(Strings.colLastActive, Strings.formatDate(r['lastActiveAt'])),
            _infoRow(Strings.colMembers, Strings.count(r['memberCount'])),
            _infoRow(Strings.colPending, Strings.count(r['pendingMemberCount'])),
            _infoRow(Strings.colActors, Strings.count(r['actorCount'])),
          ],
        ),
      ),
    );
  }

  Widget _buildBillingCard() {
    final sub = (_billing?['subscription'] as Map?)?.cast<String, dynamic>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Strings.billingCardTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Divider(height: 24),
            if (sub == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  Strings.noSubscription,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                  ),
                ),
              )
            else ...[
              _infoRow(Strings.subPlan, sub['planCode']?.toString() ?? Strings.emptyDash),
              _infoRow(Strings.subStatus, sub['status']?.toString() ?? Strings.emptyDash),
              _infoRow(Strings.subPlatform, sub['platform']?.toString() ?? Strings.emptyDash),
              _infoRow(Strings.subProvider, sub['provider']?.toString() ?? Strings.emptyDash),
              _infoRow(Strings.subRenewal, Strings.formatDate(sub['currentPeriodEnd'])),
              _infoRow(Strings.subBillingOwner, Strings.formatBillingOwner(sub['billingOwnerUserId'])),
            ],
          ],
        ),
      ),
    );
  }

  (String, Color) _grantStatus(Map<String, dynamic> g) {
    if (g['revokedAt'] != null) {
      return (Strings.grantStatusRevoked, AppColors.dangerInk);
    }
    final expiresAtStr = g['expiresAt']?.toString();
    if (expiresAtStr != null) {
      final exp = DateTime.tryParse(expiresAtStr);
      if (exp != null && exp.isBefore(DateTime.now())) {
        return (Strings.grantStatusExpired, AppColors.textSecondary);
      }
    }
    return (Strings.grantStatusActive, AppColors.successInk);
  }

  DataRow _buildGrantRow(Map<String, dynamic> g) {
    final status = _grantStatus(g);
    return DataRow(
      cells: [
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius:
                  BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              g['planCode']?.toString() ?? Strings.emptyDash,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryInk,
              ),
            ),
          ),
        ),
        DataCell(
          Text(g['reason']?.toString() ?? Strings.emptyDash),
        ),
        DataCell(
          Text(Strings.formatDate(g['createdAt'])),
        ),
        DataCell(
          Text(Strings.formatDate(g['expiresAt'])),
        ),
        DataCell(
          Text(
            status.$1,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: status.$2,
            ),
          ),
        ),
        DataCell(
          g['revokedAt'] == null
              ? TextButton(
                  onPressed: () => _revokeGrant(
                    (g['id'] as num).toInt(),
                  ),
                  child: Text(
                    Strings.revokeGrantBtn,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildGrantsCard() {
    final rawGrants = (_billing?['grants'] as List?) ?? [];
    final grants =
        rawGrants.map((g) => (g as Map).cast<String, dynamic>()).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  Strings.grantsCardTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _grantPlan,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(Strings.grantPlanBtn),
                ),
              ],
            ),
            const Divider(height: 24),
            if (grants.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  Strings.noGrants,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(Strings.colPlan)),
                    DataColumn(label: Text(Strings.colReason)),
                    DataColumn(label: Text(Strings.colGranted)),
                    DataColumn(label: Text(Strings.colExpires)),
                    DataColumn(label: Text(Strings.colStatus)),
                    DataColumn(label: Text(Strings.colActions)),
                  ],
                  rows: [
                    for (final g in grants) _buildGrantRow(g),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsCard() {
    final rawEvents = (_billing?['recentEvents'] as List?) ?? [];
    final events =
        rawEvents.map((e) => (e as Map).cast<String, dynamic>()).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Strings.eventsCardTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Divider(height: 24),
            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  Strings.noEvents,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(Strings.eventType)),
                    DataColumn(label: Text(Strings.eventProvider)),
                    DataColumn(label: Text(Strings.eventDate)),
                    DataColumn(label: Text(Strings.eventProcessed)),
                  ],
                  rows: [
                    for (final e in events)
                      DataRow(
                        cells: [
                          DataCell(
                            Text(
                              e['eventType']?.toString() ?? Strings.emptyDash,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataCell(
                            Text(e['provider']?.toString() ?? Strings.emptyDash),
                          ),
                          DataCell(
                            Text(Strings.formatDate(e['createdAt'])),
                          ),
                          DataCell(
                            Text(
                              e['processed'] == true
                                  ? Strings.eventProcessedYes
                                  : Strings.eventProcessedNo,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: e['processed'] == true
                                    ? AppColors.successInk
                                    : AppColors.warningInk,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final familyName =
        _registry?['name']?.toString() ?? widget.initialName;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          tooltip: Strings.backToFamilies,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          Strings.familyHeader(familyName, widget.familyId),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: Strings.retry,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                        onPressed: _load,
                        child: Text(Strings.retry),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildRegistryCard(),
                      const SizedBox(height: 16),
                      _buildBillingCard(),
                      const SizedBox(height: 16),
                      _buildGrantsCard(),
                      const SizedBox(height: 16),
                      _buildEventsCard(),
                    ],
                  ),
                ),
    );
  }
}
