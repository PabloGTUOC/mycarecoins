import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/devices_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/services/extensions_bridge.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';

class _FakeDevicesApi extends ApiClient {
  List<Map<String, dynamic>> deviceKeys = [];
  Map<String, dynamic>? lastPosted;
  String? lastPostPath;
  String? lastDeletedPath;
  Completer<dynamic>? postCompleter;

  @override
  Future<dynamic> get(String path) async {
    if (path == '/api/me/device-keys') {
      return {'deviceKeys': deviceKeys};
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    lastPostPath = path;
    if (body is Map) {
      lastPosted = body.cast<String, dynamic>();
    }
    if (postCompleter != null) {
      return postCompleter!.future;
    }
    if (path == '/api/me/device-keys') {
      return {
        'deviceKey': {
          'id': 99,
          'key': 'cck_secret_test_key_123',
        }
      };
    }
    return {};
  }

  @override
  Future<dynamic> delete(String path, [Object? body]) async {
    lastDeletedPath = path;
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final methodCalls = <MethodCall>[];
  late _FakeDevicesApi fakeApi;
  late AppState app;
  bool mockConnected = false;
  String? mockDeviceKeyId;

  setUp(() {
    methodCalls.clear();
    mockConnected = false;
    mockDeviceKeyId = null;
    fakeApi = _FakeDevicesApi();
    app = AppState(api: fakeApi);
    app.families = [
      {
        'family_id': 101,
        'role': 'caregiver',
      }
    ];

    messenger.setMockMethodCallHandler(ExtensionsBridge.channel, (call) async {
      methodCalls.add(call);
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'status':
          return {
            'connected': mockConnected,
            'deviceKeyId': mockDeviceKeyId,
          };
        case 'storeDeviceKey':
          mockConnected = true;
          mockDeviceKeyId = call.arguments['deviceKeyId'] as String?;
          return 'ok';
        case 'clear':
          mockConnected = false;
          mockDeviceKeyId = null;
          return null;
        case 'refresh':
          return 'ok';
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(ExtensionsBridge.channel, null);
  });

  Widget buildScreen() {
    return ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DevicesScreen(),
      ),
    );
  }

  testWidgets(
      'Not connected -> tapping Connect posts {familyId, label}, and channel receives storeDeviceKey',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      mockConnected = false;
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Connect this iPhone'), findsOneWidget);

      await tester.tap(find.text('Connect this iPhone'));
      await tester.pumpAndSettle();

      expect(fakeApi.lastPostPath, '/api/me/device-keys');
      expect(fakeApi.lastPosted, {
        'familyId': 101,
        'label': 'iPhone',
      });

      final storeCall =
          methodCalls.firstWhere((c) => c.method == 'storeDeviceKey');
      expect(storeCall.arguments, {
        'key': 'cck_secret_test_key_123',
        'deviceKeyId': '99',
        'apiBase': ApiClient.apiBase,
      });
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'Connected -> Disconnect calls DELETE /api/me/device-keys/<id> and clear',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      mockConnected = true;
      mockDeviceKeyId = '99';
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('This iPhone and its watch are connected.'),
          findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);

      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(fakeApi.lastDeletedPath, '/api/me/device-keys/99');
      expect(methodCalls.any((c) => c.method == 'clear'), isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'The list renders labels, "Not used yet", and the "This iPhone" marker on matching id',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      mockConnected = true;
      mockDeviceKeyId = '99';
      fakeApi.deviceKeys = [
        {
          'id': 99,
          'label': 'My Phone',
          'last_used_at': null,
        },
        {
          'id': 100,
          'label': 'iPad',
          'last_used_at': '2026-10-23T10:00:00Z',
        },
      ];

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('My Phone'), findsOneWidget);
      expect(find.text('iPad'), findsOneWidget);
      expect(find.text('This iPhone · Not used yet'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Removing a row asks for confirmation first', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      mockConnected = true;
      mockDeviceKeyId = '99';
      fakeApi.deviceKeys = [
        {
          'id': 100,
          'label': 'Old Phone',
          'last_used_at': null,
        },
      ];

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.link_off_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.link_off_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Remove this device? It will stop working until you connect it again.'),
        findsOneWidget,
      );
      expect(fakeApi.lastDeletedPath, isNull);

      expect(find.widgetWithText(TextButton, 'Remove'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(fakeApi.lastDeletedPath, '/api/me/device-keys/100');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'On Android, the iOS-only text shows and there is no Connect button',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(
        find.text('The widget and watch app are available on iPhone.'),
        findsOneWidget,
      );
      expect(find.text('Connect this iPhone'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Connect button is disabled while busy', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      mockConnected = false;
      final completer = Completer<dynamic>();
      fakeApi.postCompleter = completer;

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      final buttonFinder =
          find.widgetWithText(FilledButton, 'Connect this iPhone');
      expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNotNull);

      await tester.tap(buttonFinder);
      await tester.pump();

      // Button should be disabled while post is in flight
      expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);

      completer.complete({
        'deviceKey': {
          'id': 99,
          'key': 'cck_secret_test_key_123',
        }
      });
      await tester.pumpAndSettle();
    } finally {
      fakeApi.postCompleter = null;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
