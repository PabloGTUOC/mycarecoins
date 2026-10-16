import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api.dart';
import '../app_state.dart';
import '../strings.dart';
import '../theme.dart';

class OverviewScreen extends StatefulWidget {
  final DateTime Function()? nowFn;

  const OverviewScreen({super.key, this.nowFn});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  Future<void> _loadOverview({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final path = refresh ? '/overview?refresh=1' : '/overview';
      final res = await context.read<AppState>().api.get(path);
      if (!mounted) return;
      setState(() {
        _data = res;
        _loading = false;
      });
    } on AdminApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = Strings.errorFor(
          code: e.code,
          statusCode: e.statusCode,
          serverMessage: e.message,
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = Strings.errGenericFallback;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(Strings.overviewTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(Strings.refreshBtn),
              onPressed: _loading ? null : () => _loadOverview(refresh: true),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _data == null) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.danger, size: 40),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => _loadOverview(),
                  child: Text(Strings.retry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final data = _data!;
    final families =
        (data['families'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final freePlans =
        (data['freePlans'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final mirror =
        (data['mirror'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final webhooks =
        (data['webhooks'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final revenueCat = (data['revenueCat'] as Map?)?.cast<String, dynamic>();

    return RefreshIndicator(
      onRefresh: () => _loadOverview(refresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopCardsRow(families, freePlans, mirror, webhooks),
            const SizedBox(height: 24),
            _buildBreakdownTablesRow(families),
            const SizedBox(height: 24),
            _buildRevenueCatCard(revenueCat),
          ],
        ),
      ),
    );
  }

  Widget _buildTopCardsRow(
    Map<String, dynamic> families,
    Map<String, dynamic> freePlans,
    Map<String, dynamic> mirror,
    Map<String, dynamic> webhooks,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1200
            ? 4
            : (constraints.maxWidth >= 640 ? 2 : 1);
        final cardWidth = (constraints.maxWidth - ((cols - 1) * 16)) / cols;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: cardWidth,
              child: _buildFamiliesCard(families),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildFreePlansCard(freePlans),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildMirrorCard(mirror),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildWebhooksCard(webhooks),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFamiliesCard(Map<String, dynamic> families) {
    final heartbeat =
        (families['byHeartbeat'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = families['total'];
    final active = heartbeat['active'];
    final dormant = heartbeat['dormant'];
    final inactive = heartbeat['inactive'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.groups_rounded,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  Strings.cardFamiliesTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              Strings.count(total),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              Strings.labelTotal,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Divider(height: 24),
            _buildStatRow(Strings.labelActive, Strings.count(active),
                color: AppColors.successStrong),
            const SizedBox(height: 8),
            _buildStatRow(Strings.labelDormant, Strings.count(dormant),
                color: AppColors.warningStrong),
            const SizedBox(height: 8),
            _buildStatRow(Strings.labelInactive, Strings.count(inactive),
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildFreePlansCard(Map<String, dynamic> freePlans) {
    final activeGrants = freePlans['activeGrants'];
    final familiesCount = freePlans['familiesCount'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.card_giftcard_rounded,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  Strings.cardFreePlansTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              Strings.count(activeGrants),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              Strings.labelActiveGrants,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Divider(height: 24),
            _buildStatRow(
              Strings.labelFamiliesWithGrant,
              Strings.count(familiesCount),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMirrorCard(Map<String, dynamic> mirror) {
    final isMirrorOn = mirror['mirror'] == 'on';
    final synced = mirror['synced'];
    final pending = mirror['pending'];
    final failed = mirror['failed'];
    final oldestPendingMinutes = mirror['oldestPendingAgeMinutes'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sync_rounded,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      Strings.cardMirrorTitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isMirrorOn
                        ? AppColors.successSoft
                        : AppColors.inputBg,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    isMirrorOn ? Strings.labelMirrorOn : Strings.labelMirrorOff,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isMirrorOn
                          ? AppColors.successInk
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow(Strings.labelSynced, Strings.count(synced),
                color: AppColors.successStrong),
            const SizedBox(height: 8),
            _buildStatRow(Strings.labelPending, Strings.count(pending),
                color: AppColors.warningStrong),
            const SizedBox(height: 8),
            _buildStatRow(Strings.labelFailed, Strings.count(failed),
                color: (failed is num && failed > 0)
                    ? AppColors.dangerInk
                    : AppColors.textSecondary),
            const Divider(height: 24),
            _buildStatRow(
              Strings.labelOldestPending,
              Strings.formatAgeMinutes(oldestPendingMinutes),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebhooksCard(Map<String, dynamic> webhooks) {
    final lastEventAt = webhooks['lastEventAt'];
    final events30Days = webhooks['eventsLast30Days'];
    final unattributed30Days = webhooks['unattributedLast30Days'];
    final unprocessed30Days = webhooks['unprocessedLast30Days'];
    final recentEvents = (webhooks['recentEvents'] as List?) ?? [];

    final now = widget.nowFn?.call() ?? DateTime.now();
    final lastEventText = Strings.formatTimeAgo(lastEventAt, now: now);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.webhook_rounded,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  Strings.cardWebhooksTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow(Strings.labelLastEvent, lastEventText),
            const SizedBox(height: 8),
            _buildStatRow(
                Strings.labelEvents30Days, Strings.count(events30Days)),
            const SizedBox(height: 8),
            _buildStatRow(Strings.labelUnattributed30Days,
                Strings.count(unattributed30Days),
                color: (unattributed30Days is num && unattributed30Days > 0)
                    ? AppColors.warningStrong
                    : AppColors.textSecondary),
            const SizedBox(height: 8),
            _buildStatRow(
                Strings.labelUnprocessed30Days, Strings.count(unprocessed30Days),
                color: (unprocessed30Days is num && unprocessed30Days > 0)
                    ? AppColors.dangerInk
                    : AppColors.textSecondary),
            const Divider(height: 24),
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 8),
                dense: true,
                title: Text(
                  Strings.recentWebhookIssues,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryInk,
                  ),
                ),
                children: [
                  if (recentEvents.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        Strings.noRecentWebhookIssues,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  else
                    ...recentEvents.map((evt) {
                      final item = (evt as Map).cast<String, dynamic>();
                      final id = item['id'];
                      final type = item['eventType']?.toString() ??
                          Strings.emptyDash;
                      final date = Strings.formatDate(item['createdAt']);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Text(
                              Strings.formatId(id),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                type,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            Text(
                              date,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownTablesRow(Map<String, dynamic> families) {
    final byPlan =
        (families['byPlan'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final byStatus =
        (families['byStatus'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final byStore =
        (families['byStore'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 900
            ? 3
            : (constraints.maxWidth >= 600 ? 2 : 1);
        final colWidth = (constraints.maxWidth - ((cols - 1) * 16)) / cols;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: colWidth,
              child: _buildBreakdownCard(
                title: Strings.byPlanTitle,
                keyColLabel: Strings.colPlan,
                entries: byPlan.entries.toList(),
              ),
            ),
            SizedBox(
              width: colWidth,
              child: _buildBreakdownCard(
                title: Strings.byStatusTitle,
                keyColLabel: Strings.colStatus,
                entries: byStatus.entries.toList(),
              ),
            ),
            SizedBox(
              width: colWidth,
              child: _buildBreakdownCard(
                title: Strings.byStoreTitle,
                keyColLabel: Strings.colStore,
                entries: byStore.entries.toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBreakdownCard({
    required String title,
    required String keyColLabel,
    required List<MapEntry<String, dynamic>> entries,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  Strings.noData,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(1),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          keyColLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          Strings.colCount,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ...entries.map((e) {
                    final key = e.key;
                    final count = Strings.count(e.value);
                    return TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            key,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            count,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueCatCard(Map<String, dynamic>? rc) {
    Widget content;

    if (rc == null) {
      content = Text(
        Strings.revenueCatNotConfigured,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
      );
    } else if (rc['error'] != null) {
      final err = rc['error']?.toString();
      final message = err == 'rejected'
          ? Strings.revenueCatRejected
          : Strings.revenueCatUnavailable;
      content = Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: AppColors.warningStrong),
          const SizedBox(width: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.warningStrong,
            ),
          ),
        ],
      );
    } else {
      final metrics = (rc['metrics'] as List?) ?? [];
      if (metrics.isEmpty) {
        content = Text(
          Strings.noMetricsAvailable,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        );
      } else {
        content = Wrap(
          spacing: 24,
          runSpacing: 16,
          children: metrics.map((m) {
            final metric = (m as Map).cast<String, dynamic>();
            final name = metric['name']?.toString() ??
                metric['id']?.toString() ??
                Strings.emptyDash;
            final valStr =
                Strings.formatMetricValue(metric['value'], metric['unit']);

            return SizedBox(
              width: 220,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      valStr,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart_rounded,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  Strings.cardRevenueCatTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            content,
          ],
        ),
      ),
    );
  }
}
