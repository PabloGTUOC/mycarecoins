import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../app_state.dart';
import '../strings.dart';
import '../theme.dart';

class FamilyDetailScreen extends StatefulWidget {
  final int familyId;
  final String initialName;
  final Future<bool> Function(Uri uri)? launchUrlFn;

  const FamilyDetailScreen({
    super.key,
    required this.familyId,
    required this.initialName,
    this.launchUrlFn,
  });

  @override
  State<FamilyDetailScreen> createState() => _FamilyDetailScreenState();
}

class _FamilyDetailScreenState extends State<FamilyDetailScreen> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _registry;
  Map<String, dynamic>? _billing;

  bool _rcLoading = true;
  bool _rcNotConfigured = false;
  String? _rcError;
  Map<String, dynamic>? _rcData;

  @override
  void initState() {
    super.initState();
    _load();
    _loadRevenueCat();
  }

  Future<void> _loadRevenueCat({bool refresh = false}) async {
    setState(() {
      _rcLoading = true;
      _rcError = null;
      _rcNotConfigured = false;
    });

    try {
      final api = context.read<AppState>().api;
      final path = refresh
          ? '/families/${widget.familyId}/revenuecat?refresh=1'
          : '/families/${widget.familyId}/revenuecat';
      final res = await api.get(path);
      if (!mounted) return;
      setState(() {
        _rcData = res;
        _rcLoading = false;
      });
    } on AdminApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 503 || e.code == 'revenueCatNotConfigured') {
        setState(() {
          _rcNotConfigured = true;
          _rcLoading = false;
        });
      } else {
        setState(() {
          _rcLoading = false;
          _rcError = Strings.errorFor(
            code: e.code,
            statusCode: e.statusCode,
            serverMessage: e.message,
          );
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rcLoading = false;
        _rcError = Strings.errGenericFallback;
      });
    }
  }

  Future<void> _openUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    final fn = widget.launchUrlFn ??
        (u) => launchUrl(u, mode: LaunchMode.externalApplication);
    await fn(uri);
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

  Future<void> _retryRcSync(int grantId) async {
    final app = context.read<AppState>();
    final done = await app.runMutation(
      context,
      () => app.api.post('/families/${widget.familyId}/grants/$grantId/rc-sync'),
      successMessage: Strings.rcSyncRetrySuccess,
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

  Widget _buildRcCustomerBlock(
    String sectionTitle,
    Map<String, dynamic>? customer, {
    bool isBillingOwner = false,
  }) {
    if (customer == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sectionTitle,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isBillingOwner ? Strings.rcNoBillingOwner : Strings.rcStatusNotFound,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    }

    final customerId = customer['customerId']?.toString() ?? Strings.emptyDash;
    final found = customer['found'] == true;
    final rawEntitlements = (customer['entitlements'] as List?) ?? [];
    final entitlements =
        rawEntitlements.map((e) => (e as Map).cast<String, dynamic>()).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              sectionTitle,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _openUrl(Strings.rcCustomerDashboardUrl(customerId)),
              icon: const Icon(Icons.open_in_new_rounded, size: 14),
              label: Text(Strings.rcOpenInDashboard),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _infoRow(Strings.rcCustomerIdLabel, customerId),
        _infoRow(
          Strings.rcStatusLabel,
          found ? Strings.rcStatusFound : Strings.rcStatusNotFound,
        ),
        if (found) ...[
          _infoRow(
            Strings.rcLastSeenLabel,
            Strings.formatDate(customer['lastSeenAt']),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 180,
                  child: Text(
                    Strings.rcActiveEntitlementsTitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: entitlements.isEmpty
                      ? Text(
                          Strings.rcNoActiveEntitlements,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final e in entitlements)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  Strings.rcEntitlementSummary(
                                    id: e['id']?.toString() ?? Strings.emptyDash,
                                    expiresAt: e['expiresAt'],
                                    store: e['store']?.toString(),
                                    grantType: e['grantType']?.toString(),
                                  ),
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRevenueCatCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  Strings.rcCardTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: Strings.rcRefreshBtn,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed:
                      _rcLoading ? null : () => _loadRevenueCat(refresh: true),
                ),
              ],
            ),
            const Divider(height: 24),
            if (_rcLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        Strings.rcLoading,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_rcNotConfigured)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  Strings.errRevenueCatNotConfigured,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                  ),
                ),
              )
            else if (_rcError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _rcError!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _loadRevenueCat(refresh: true),
                      child: Text(Strings.retry),
                    ),
                  ],
                ),
              )
            else if (_rcData != null) ...[
              () {
                final rawMismatches = (_rcData!['mismatches'] as List?) ?? [];
                final mismatches = rawMismatches
                    .map((m) => (m as Map).cast<String, dynamic>())
                    .toList();
                if (mismatches.isEmpty) return const SizedBox.shrink();
                return Column(
                  children: [
                    for (final m in mismatches)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warningSoft,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          border: Border.all(color: AppColors.warning),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: AppColors.warningStrong,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    Strings.rcMismatchTitle(
                                      m['code']?.toString() ?? '',
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppColors.warningInk,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    m['message']?.toString() ??
                                        Strings.emptyDash,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.warningInk,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                );
              }(),
              _buildRcCustomerBlock(
                Strings.rcFamilyCustomerTitle,
                (_rcData!['familyCustomer'] as Map?)?.cast<String, dynamic>(),
              ),
              const Divider(height: 24),
              _buildRcCustomerBlock(
                Strings.rcBillingOwnerCustomerTitle,
                (_rcData!['billingOwnerCustomer'] as Map?)
                    ?.cast<String, dynamic>(),
                isBillingOwner: true,
              ),
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

  Widget _buildRcSyncCell(Map<String, dynamic> g) {
    final rcSync = (g['rcSync'] as Map?)?.cast<String, dynamic>();
    if (rcSync == null) {
      return Text(
        Strings.emptyDash,
        style: const TextStyle(color: AppColors.textSecondary),
      );
    }

    final status = rcSync['status']?.toString();
    if (status == 'synced') {
      return Text(
        Strings.rcSyncSynced,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.successInk,
        ),
      );
    } else if (status == 'pending') {
      return Text(
        Strings.rcSyncPending,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.warningStrong,
        ),
      );
    } else if (status == 'failed') {
      final errorMsg = rcSync['lastError']?.toString();
      final textWidget = Text(
        Strings.rcSyncFailed,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.dangerInk,
        ),
      );
      if (errorMsg != null && errorMsg.isNotEmpty) {
        return Tooltip(
          message: errorMsg,
          child: textWidget,
        );
      }
      return textWidget;
    }

    return Text(
      Strings.emptyDash,
      style: const TextStyle(color: AppColors.textSecondary),
    );
  }

  DataRow _buildGrantRow(Map<String, dynamic> g) {
    final status = _grantStatus(g);
    final rcSync = (g['rcSync'] as Map?)?.cast<String, dynamic>();
    final canRetry = rcSync != null &&
        (rcSync['status'] == 'pending' || rcSync['status'] == 'failed');

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
          _buildRcSyncCell(g),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canRetry)
                TextButton(
                  onPressed: () => _retryRcSync(
                    (g['id'] as num).toInt(),
                  ),
                  child: Text(
                    Strings.rcSyncRetryBtn,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (g['revokedAt'] == null)
                TextButton(
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
                ),
            ],
          ),
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
                    DataColumn(label: Text(Strings.colRevenueCat)),
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
            onPressed: () {
              _load();
              _loadRevenueCat(refresh: true);
            },
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
                      _buildRevenueCatCard(),
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
