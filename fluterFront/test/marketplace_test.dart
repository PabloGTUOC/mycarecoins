import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/marketplace_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class FakeApiClient extends ApiClient {
  final List<String> postCalls = [];
  Completer<dynamic>? pendingPost;

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/marketplace/rewards/')) {
      return {
        'rewards': [
          {
            'id': 'rew-123',
            'title': 'Movie night',
            'description': 'Pick the movie',
            'cost': 40,
            'uses': 0,
          }
        ],
        'claimed': [],
      };
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Parent'},
        'families': [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ],
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    postCalls.add(path);
    if (pendingPost != null && path.contains('/redeem')) {
      return await pendingPost!.future;
    }
    return {'redeemed': true};
  }
}

Widget _app(AppState app, Widget child) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('T2: Marketplace reward redeem confirmation modal sheet', () {
    testWidgets('dismissing the sheet makes no API call', (tester) async {
      final fakeApi = FakeApiClient();
      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_app(app, const MarketplaceScreen()));
      await tester.pumpAndSettle();

      // Card is displayed with reward title and cost.
      expect(find.text('Movie night'), findsOneWidget);
      expect(find.text('Pick the movie'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);

      // No redeem call made yet.
      expect(fakeApi.postCalls.where((p) => p.contains('/redeem')), isEmpty);

      // Tap buy on the card.
      await tester.tap(find.widgetWithText(VButton, 'Buy'));
      await tester.pumpAndSettle();

      // The confirmation modal bottom sheet is shown.
      expect(find.text('Redeem reward'), findsOneWidget);
      expect(find.text('Movie night'), findsNWidgets(2)); // Card + sheet
      expect(find.text('40 cc'), findsOneWidget); // PillBadge in sheet
      // Current balance 150 - cost 40 = 110 cc balance after.
      expect(find.text("You'll have 110 cc left"), findsOneWidget);
      expect(find.widgetWithText(VButton, 'Redeem'), findsOneWidget);
      expect(find.widgetWithText(VButton, 'Not now'), findsOneWidget);

      // Still no redeem call made before confirming.
      expect(fakeApi.postCalls.where((p) => p.contains('/redeem')), isEmpty);

      // Dismiss the sheet with "Not now".
      await tester.tap(find.widgetWithText(VButton, 'Not now'));
      await tester.pumpAndSettle();

      // Sheet is dismissed.
      expect(find.text('Redeem reward'), findsNothing);

      // Proves that dismissing the sheet makes NO API call.
      expect(fakeApi.postCalls.where((p) => p.contains('/redeem')), isEmpty);
    });

    testWidgets('dismissing via barrier tap also makes no API call',
        (tester) async {
      final fakeApi = FakeApiClient();
      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_app(app, const MarketplaceScreen()));
      await tester.pumpAndSettle();

      // Open sheet.
      await tester.tap(find.widgetWithText(VButton, 'Buy'));
      await tester.pumpAndSettle();

      expect(find.text('Redeem reward'), findsOneWidget);
      expect(fakeApi.postCalls.where((p) => p.contains('/redeem')), isEmpty);

      // Tap the barrier (outside the sheet, top left area).
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Sheet is dismissed and no API call made.
      expect(find.text('Redeem reward'), findsNothing);
      expect(fakeApi.postCalls.where((p) => p.contains('/redeem')), isEmpty);
    });

    testWidgets('redeem posts only on Redeem and button is disabled while running',
        (tester) async {
      final fakeApi = FakeApiClient();
      final completer = Completer<dynamic>();
      fakeApi.pendingPost = completer;

      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_app(app, const MarketplaceScreen()));
      await tester.pumpAndSettle();

      // Open sheet.
      await tester.tap(find.widgetWithText(VButton, 'Buy'));
      await tester.pumpAndSettle();

      final redeemBtnFinder = find.widgetWithText(VButton, 'Redeem');
      expect(redeemBtnFinder, findsOneWidget);
      expect(tester.widget<VButton>(redeemBtnFinder).disabled, isFalse);

      // Tap Redeem.
      await tester.tap(redeemBtnFinder);
      await tester.pump();

      // While request runs, Redeem button is disabled.
      expect(tester.widget<VButton>(redeemBtnFinder).disabled, isTrue);

      // Finish the post.
      completer.complete({'redeemed': true});
      await tester.pumpAndSettle();

      // Post was made to redeem endpoint.
      expect(fakeApi.postCalls, contains('/api/marketplace/rewards/rew-123/redeem'));

      // Sheet is dismissed on success.
      expect(find.text('Redeem reward'), findsNothing);

      // Advance past the 3.5s toast auto-dismiss timer.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'with balance 30 and cost 40 the sheet shows "You need 10 more cc" and tapping Redeem makes no API call',
        (tester) async {
      final fakeApi = FakeApiClient();
      final app = AppState(api: fakeApi)
        ..families = [
          {'family_id': 1, 'coin_balance': 30, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Parent'};

      await tester.pumpWidget(_app(app, const MarketplaceScreen()));
      await tester.pumpAndSettle();

      // Open sheet for the reward costing 40 cc.
      await tester.tap(find.widgetWithText(VButton, 'Buy'));
      await tester.pumpAndSettle();

      // Sheet is open and shows "You need 10 more cc" in dangerInk.
      expect(find.text('Redeem reward'), findsOneWidget);
      final needMoreFinder = find.text('You need 10 more cc');
      expect(needMoreFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(needMoreFinder);
      expect(textWidget.style?.color, const Color(0xFFB91C1C)); // AppColors.dangerInk

      final redeemBtnFinder = find.widgetWithText(VButton, 'Redeem');
      expect(redeemBtnFinder, findsOneWidget);
      // Redeem button is disabled.
      expect(tester.widget<VButton>(redeemBtnFinder).disabled, isTrue);

      // Tapping Redeem makes no API call.
      await tester.tap(redeemBtnFinder);
      await tester.pumpAndSettle();

      expect(fakeApi.postCalls.where((p) => p.contains('/redeem')), isEmpty);
    });
  });
}
