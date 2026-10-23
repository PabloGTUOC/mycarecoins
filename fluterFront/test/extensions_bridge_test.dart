import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carecoins_flutter/services/extensions_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final methodCalls = <MethodCall>[];

  setUp(() {
    methodCalls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(ExtensionsBridge.channel, (call) async {
      methodCalls.add(call);
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'storeDeviceKey':
          return 'ok';
        case 'status':
          return {'connected': true, 'deviceKeyId': '42'};
        case 'refresh':
          return 'ok';
        case 'clear':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(ExtensionsBridge.channel, null);
  });

  test('storeDeviceKey sends the three arguments', () async {
    final result = await ExtensionsBridge.storeDeviceKey(
      key: 'test_key',
      deviceKeyId: '123',
      apiBase: 'https://example.com',
    );
    expect(result, 'ok');
    expect(methodCalls.length, 1);
    expect(methodCalls.first.method, 'storeDeviceKey');
    expect(methodCalls.first.arguments, {
      'key': 'test_key',
      'deviceKeyId': '123',
      'apiBase': 'https://example.com',
    });
  });

  test('status parses {connected, deviceKeyId}', () async {
    final status = await ExtensionsBridge.status();
    expect(status.connected, isTrue);
    expect(status.deviceKeyId, '42');
  });

  test('A PlatformException -> no throw', () async {
    messenger.setMockMethodCallHandler(ExtensionsBridge.channel, (call) async {
      throw PlatformException(code: 'ERROR', message: 'Failed');
    });
    expect(
      () async => await ExtensionsBridge.storeDeviceKey(
        key: 'k',
        deviceKeyId: 'd',
        apiBase: 'a',
      ),
      returnsNormally,
    );
    final status = await ExtensionsBridge.status();
    expect(status.connected, isFalse);
    expect(status.deviceKeyId, isNull);
    expect(() async => await ExtensionsBridge.clear(), returnsNormally);
  });

  test('MissingPluginException (no handler) -> no throw', () async {
    messenger.setMockMethodCallHandler(ExtensionsBridge.channel, null);
    expect(
      () async => await ExtensionsBridge.storeDeviceKey(
        key: 'k',
        deviceKeyId: 'd',
        apiBase: 'a',
      ),
      returnsNormally,
    );
    final status = await ExtensionsBridge.status();
    expect(status.connected, isFalse);
    expect(status.deviceKeyId, isNull);
    expect(() async => await ExtensionsBridge.clear(), returnsNormally);
  });

  test('On Android, nothing reaches the channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await ExtensionsBridge.storeDeviceKey(
      key: 'k',
      deviceKeyId: 'd',
      apiBase: 'a',
    );
    await ExtensionsBridge.status();
    await ExtensionsBridge.refresh();
    await ExtensionsBridge.clear();
    expect(methodCalls, isEmpty);
  });

  test('Two concurrent refresh() calls -> a single platform call', () async {
    final completer = Completer<String?>();
    messenger.setMockMethodCallHandler(ExtensionsBridge.channel, (call) {
      methodCalls.add(call);
      return completer.future;
    });

    final f1 = ExtensionsBridge.refresh();
    final f2 = ExtensionsBridge.refresh();

    expect(methodCalls.length, 1);
    completer.complete('ok');
    final results = await Future.wait([f1, f2]);
    expect(results, ['ok', 'ok']);
    expect(methodCalls.length, 1);
  });
}
