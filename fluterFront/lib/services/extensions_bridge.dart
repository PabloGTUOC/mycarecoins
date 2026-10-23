import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ExtensionsBridge {
  static const channel = MethodChannel('carecoins/extensions');

  /// iOS only, never on web. Everything else is a no-op that returns null/false.
  static bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<String?>? _inFlightRefresh;

  static Future<String?> storeDeviceKey({
    required String key,
    required String deviceKeyId,
    required String apiBase,
  }) async {
    if (!available) return null;
    try {
      return await channel.invokeMethod<String>('storeDeviceKey', {
        'key': key,
        'deviceKeyId': deviceKeyId,
        'apiBase': apiBase,
      });
    } on PlatformException catch (e) {
      debugPrint('ExtensionsBridge.storeDeviceKey platform error: $e');
      return null;
    } on MissingPluginException catch (e) {
      debugPrint('ExtensionsBridge.storeDeviceKey missing plugin: $e');
      return null;
    } catch (e) {
      debugPrint('ExtensionsBridge.storeDeviceKey error: $e');
      return null;
    }
  }

  static Future<({bool connected, String? deviceKeyId})> status() async {
    if (!available) return (connected: false, deviceKeyId: null);
    try {
      final res = await channel.invokeMapMethod<String, dynamic>('status');
      if (res == null) return (connected: false, deviceKeyId: null);
      final connected = res['connected'] == true;
      final rawId = res['deviceKeyId'];
      final deviceKeyId = rawId == null ? null : '$rawId';
      return (connected: connected, deviceKeyId: deviceKeyId);
    } on PlatformException catch (e) {
      debugPrint('ExtensionsBridge.status platform error: $e');
      return (connected: false, deviceKeyId: null);
    } on MissingPluginException catch (e) {
      debugPrint('ExtensionsBridge.status missing plugin: $e');
      return (connected: false, deviceKeyId: null);
    } catch (e) {
      debugPrint('ExtensionsBridge.status error: $e');
      return (connected: false, deviceKeyId: null);
    }
  }

  static Future<String?> refresh() {
    if (!available) return Future.value(null);
    if (_inFlightRefresh != null) {
      return _inFlightRefresh!;
    }
    final future = _doRefresh();
    _inFlightRefresh = future;
    return future;
  }

  static Future<String?> _doRefresh() async {
    try {
      final res = await channel.invokeMethod<String>('refresh');
      return res;
    } on PlatformException catch (e) {
      debugPrint('ExtensionsBridge.refresh platform error: $e');
      return null;
    } on MissingPluginException catch (e) {
      debugPrint('ExtensionsBridge.refresh missing plugin: $e');
      return null;
    } catch (e) {
      debugPrint('ExtensionsBridge.refresh error: $e');
      return null;
    } finally {
      _inFlightRefresh = null;
    }
  }

  static Future<void> clear() async {
    if (!available) return;
    try {
      await channel.invokeMethod<void>('clear');
    } on PlatformException catch (e) {
      debugPrint('ExtensionsBridge.clear platform error: $e');
    } on MissingPluginException catch (e) {
      debugPrint('ExtensionsBridge.clear missing plugin: $e');
    } catch (e) {
      debugPrint('ExtensionsBridge.clear error: $e');
    }
  }
}
