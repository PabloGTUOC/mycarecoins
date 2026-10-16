import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../app_state.dart';
import '../strings.dart';
import '../theme.dart';

class AppStoreScreen extends StatefulWidget {
  final Future<bool> Function(Uri uri)? launchUrlFn;

  const AppStoreScreen({super.key, this.launchUrlFn});

  @override
  State<AppStoreScreen> createState() => _AppStoreScreenState();
}

class _AppStoreScreenState extends State<AppStoreScreen> {
  bool _loadingCatalog = true;
  bool _notConfigured = false;
  String? _catalogError;
  Map<String, dynamic>? _catalogData;

  final _txController = TextEditingController();
  String _selectedEnv = 'production';
  bool _lookingUpTx = false;
  String? _txError;
  Map<String, dynamic>? _txResult;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _txController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog({bool refresh = false}) async {
    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });

    try {
      final path =
          refresh ? '/appstore/catalog?refresh=1' : '/appstore/catalog';
      final res = await context.read<AppState>().api.get(path);
      if (!mounted) return;
      setState(() {
        _catalogData = res;
        _loadingCatalog = false;
      });
    } on AdminApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 503 || e.code == 'appStoreNotConfigured') {
        setState(() {
          _notConfigured = true;
          _loadingCatalog = false;
        });
      } else {
        setState(() {
          _catalogError = Strings.errorFor(
            code: e.code,
            statusCode: e.statusCode,
            serverMessage: e.message,
          );
          _loadingCatalog = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _catalogError = Strings.errGenericFallback;
        _loadingCatalog = false;
      });
    }
  }

  Future<void> _openUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    final fn = widget.launchUrlFn ??
        (u) => launchUrl(u, mode: LaunchMode.externalApplication);
    await fn(uri);
  }

  Future<void> _lookupTx() async {
    final id = _txController.text.trim();
    if (id.isEmpty) return;

    setState(() {
      _lookingUpTx = true;
      _txError = null;
      _txResult = null;
    });

    try {
      final res = await context.read<AppState>().api.get(
            '/appstore/transactions/$id?environment=$_selectedEnv',
          );
      if (!mounted) return;
      setState(() {
        _txResult = res;
        _lookingUpTx = false;
      });
    } on AdminApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _lookingUpTx = false;
        if (e.statusCode == 404 || e.code == 'notFound') {
          _txError = Strings.txNotFound;
        } else {
          _txError = Strings.errorFor(
            code: e.code,
            statusCode: e.statusCode,
            serverMessage: e.message,
          );
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lookingUpTx = false;
        _txError = Strings.errGenericFallback;
      });
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
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

  @override
  Widget build(BuildContext context) {
    if (_loadingCatalog && _catalogData == null && !_notConfigured) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_notConfigured) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.store_outlined,
                    size: 48,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    Strings.appStoreNotConfiguredTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    Strings.appStoreNotConfiguredBody,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final groups = (_catalogData?['subscriptionGroups'] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & External Links
          Row(
            children: [
              Text(
                Strings.appStoreTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(Strings.linkAppStoreConnect),
                onPressed: () => _openUrl(Strings.appStoreConnectUrl),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(Strings.linkRevenueCat),
                onPressed: () => _openUrl(Strings.revenueCatCustomersUrl),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Catalog Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        Strings.catalogTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(Strings.refreshCatalogBtn),
                        onPressed: () => _loadCatalog(refresh: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_loadingCatalog)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_catalogError != null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text(
                            _catalogError!,
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => _loadCatalog(refresh: true),
                            child: Text(Strings.retry),
                          ),
                        ],
                      ),
                    )
                  else if (groups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          Strings.noSubscriptionGroups,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  else
                    ...groups.map((g) {
                      final groupMap = (g as Map).cast<String, dynamic>();
                      final subs = (groupMap['subscriptions'] as List?) ?? [];
                      final groupName = groupMap['referenceName']?.toString() ??
                          Strings.emptyDash;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              groupName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (subs.isEmpty)
                              Text(
                                Strings.noSubscriptionsFound,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              )
                            else
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: [
                                    DataColumn(
                                      label: Text(Strings.colProduct),
                                    ),
                                    DataColumn(
                                      label: Text(Strings.colName),
                                    ),
                                    DataColumn(
                                      label: Text(Strings.colState),
                                    ),
                                    DataColumn(
                                      label: Text(Strings.colPrice),
                                    ),
                                  ],
                                  rows: subs.map((s) {
                                    final subMap =
                                        (s as Map).cast<String, dynamic>();
                                    final prices =
                                        (subMap['prices'] as List?) ?? [];
                                    final priceText = prices.isEmpty
                                        ? Strings.emptyDash
                                        : prices
                                            .map((p) => Strings.formatCatalogPrice(
                                                  p['customerPrice'],
                                                  p['currency'],
                                                  p['territory'],
                                                ))
                                            .join(', ');

                                    return DataRow(
                                      cells: [
                                        DataCell(Text(
                                          subMap['productId']?.toString() ??
                                              Strings.emptyDash,
                                        )),
                                        DataCell(Text(
                                          subMap['name']?.toString() ??
                                              Strings.emptyDash,
                                        )),
                                        DataCell(Text(
                                          subMap['state']?.toString() ??
                                              Strings.emptyDash,
                                        )),
                                        DataCell(Text(priceText)),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Transaction Lookup Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Strings.lookupTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _txController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: Strings.transactionIdLabel,
                            isDense: true,
                          ),
                          onSubmitted: (_) => _lookupTx(),
                        ),
                      ),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment<String>(
                            value: 'production',
                            label: Text(Strings.envProduction),
                          ),
                          ButtonSegment<String>(
                            value: 'sandbox',
                            label: Text(Strings.envSandbox),
                          ),
                        ],
                        selected: {_selectedEnv},
                        onSelectionChanged: (val) {
                          setState(() {
                            _selectedEnv = val.first;
                          });
                        },
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.search_rounded, size: 18),
                        label: Text(Strings.lookupBtn),
                        onPressed: _lookingUpTx ? null : _lookupTx,
                      ),
                    ],
                  ),
                  if (_lookingUpTx)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_txError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        _txError!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else if (_txResult != null) ...[
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    _infoRow(
                      Strings.colProduct,
                      _txResult!['productId']?.toString() ?? Strings.emptyDash,
                    ),
                    _infoRow(
                      Strings.colTxId,
                      _txResult!['transactionId']?.toString() ??
                          Strings.emptyDash,
                    ),
                    _infoRow(
                      Strings.colOrigTxId,
                      _txResult!['originalTransactionId']?.toString() ??
                          Strings.emptyDash,
                    ),
                    _infoRow(
                      Strings.colPurchaseDate,
                      Strings.formatDate(_txResult!['purchaseDate']),
                    ),
                    _infoRow(
                      Strings.colExpiresDate,
                      Strings.formatDate(_txResult!['expiresDate']),
                    ),
                    _infoRow(
                      Strings.colEnvironment,
                      _txResult!['environment']?.toString() ??
                          Strings.emptyDash,
                    ),
                    _infoRow(
                      Strings.colType,
                      _txResult!['type']?.toString() ?? Strings.emptyDash,
                    ),
                    _infoRow(
                      Strings.colOwnership,
                      _txResult!['inAppOwnershipType']?.toString() ??
                          Strings.emptyDash,
                    ),
                    _infoRow(
                      Strings.colRevocationDate,
                      Strings.formatDate(_txResult!['revocationDate']),
                    ),
                    _infoRow(
                      Strings.colRevocationReason,
                      _txResult!['revocationReason']?.toString() ??
                          Strings.emptyDash,
                    ),
                    _infoRow(
                      Strings.colAutoRenew,
                      Strings.formatAutoRenew(_txResult!['autoRenewStatus']),
                    ),
                    _infoRow(
                      Strings.colAutoRenewProduct,
                      _txResult!['autoRenewProductId']?.toString() ??
                          Strings.emptyDash,
                    ),
                    _infoRow(
                      Strings.colExpirationIntent,
                      _txResult!['expirationIntent']?.toString() ??
                          Strings.emptyDash,
                    ),
                    _infoRow(
                      Strings.colStatus,
                      _txResult!['status']?.toString() ?? Strings.emptyDash,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
