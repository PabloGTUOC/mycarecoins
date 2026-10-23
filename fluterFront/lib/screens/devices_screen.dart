import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/api_client.dart';
import '../services/extensions_bridge.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/ui.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool _loading = true;
  bool _busy = false;
  ({bool connected, String? deviceKeyId}) _status =
      (connected: false, deviceKeyId: null);
  List<Map<String, dynamic>> _deviceKeys = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _fetch() async {
    final app = context.read<AppState>();
    final status = await ExtensionsBridge.status();
    final res = await app.api.get('/api/me/device-keys');
    final list = (res is Map ? res['deviceKeys'] as List? : null) ?? [];
    if (!mounted) return;
    setState(() {
      _status = status;
      _deviceKeys =
          list.map((e) => (e as Map).cast<String, dynamic>()).toList();
    });
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (mounted) setState(() => _loading = true);
    await app.runAction(() async {
      await _fetch();
    });
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _connect() async {
    if (_busy) return;
    if (mounted) setState(() => _busy = true);
    final app = context.read<AppState>();
    final l = AppLocalizations.of(context);
    try {
      await app.runAction(() async {
        final res = await app.api.post('/api/me/device-keys', {
          'familyId': app.familyId,
          'label': l.devicesLabelIphone,
        });
        final data = (res as Map).cast<String, dynamic>();
        final deviceKey = (data['deviceKey'] as Map).cast<String, dynamic>();
        final key = deviceKey['key'] as String;
        final deviceKeyId = '${deviceKey['id']}';
        await ExtensionsBridge.storeDeviceKey(
          key: key,
          deviceKeyId: deviceKeyId,
          apiBase: ApiClient.apiBase,
        );
        await _fetch();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    if (mounted) setState(() => _busy = true);
    final app = context.read<AppState>();
    try {
      await app.runAction(() async {
        final id = _status.deviceKeyId;
        if (id != null) {
          try {
            await app.api.delete('/api/me/device-keys/$id');
          } on ApiException catch (e) {
            if (e.statusCode != 404 && e.errorCode != 'deviceKeyNotFound') {
              rethrow;
            }
          }
        }
        await ExtensionsBridge.clear();
        await _fetch();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeDevice(String id) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l.devicesRemove,
      body: l.devicesRemoveConfirm,
      danger: true,
      confirmLabel: l.devicesRemove,
    );
    if (!confirmed) return;
    if (!mounted) return;
    final app = context.read<AppState>();
    await app.runAction(() async {
      await app.api.delete('/api/me/device-keys/$id');
      if (id == _status.deviceKeyId) {
        await ExtensionsBridge.clear();
      }
      await _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          l.devicesTitle,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l.devicesIntro,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildIphoneCard(l),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l.devicesListTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                if (_deviceKeys.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      l.devicesNone,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  ..._deviceKeys.map((d) {
                    final id = '${d['id']}';
                    final isThisIphone = id == _status.deviceKeyId;
                    final label = (d['label'] ?? '') as String;
                    final lastUsedAt = d['last_used_at'];
                    final dateStr = lastUsedAt != null
                        ? l.devicesLastUsed(formatShortDate(
                            lastUsedAt,
                            Localizations.localeOf(context).toString(),
                          ))
                        : l.devicesNeverUsed;
                    final subtitleText = isThisIphone
                        ? '${l.devicesThisIphone} · $dateStr'
                        : dateStr;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        subtitleText,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.link_off_rounded),
                        tooltip: l.devicesRemove,
                        onPressed: () => _removeDevice(id),
                      ),
                    );
                  }),
                const SizedBox(height: 16),
                Text(
                  l.devicesWatchNote,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildIphoneCard(AppLocalizations l) {
    if (!ExtensionsBridge.available) {
      return Text(
        l.devicesIosOnly,
        style: const TextStyle(color: AppColors.textSecondary),
      );
    }
    if (_status.connected) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.devicesConnected,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _disconnect,
            child: Text(l.devicesDisconnect),
          ),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton(
        onPressed: _busy ? null : _connect,
        child: Text(l.devicesConnect),
      ),
    );
  }
}
