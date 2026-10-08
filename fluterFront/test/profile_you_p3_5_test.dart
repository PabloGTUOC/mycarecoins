import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/profile_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';
import 'package:carecoins_flutter/widgets/subscription_card.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class _FakeProfileApi extends ApiClient {
  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/me/notification-preferences')) {
      return <String, dynamic>{};
    }
    if (path.startsWith('/api/families/') &&
        path.contains('/deletion-requests')) {
      return {'deletionRequests': []};
    }
    if (path.startsWith('/api/me/ledger')) {
      return {'ledger': []};
    }
    if (path.startsWith('/api/activities')) return {'activities': []};
    if (path.startsWith('/api/absences')) return {'absences': []};
    if (path.startsWith('/api/personal-time')) return {'requests': []};
    if (path.startsWith('/api/dashboard/')) {
      return {'members': [], 'calendar': [], 'objectsOfCare': []};
    }
    if (path.startsWith('/api/marketplace/rewards/')) {
      return {'rewards': [], 'claimed': []};
    }
    if (path.startsWith('/api/stats')) {
      return {
        'activeCaregivers': ['Dad'],
        'kpis': {},
        'monthlyChart': [],
        'distribution': [],
      };
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'email': 'dad@example.com', 'display_name': 'Dad'},
        'families': [
          {
            'family_id': 101,
            'name': 'The Henderson Family',
            'role': 'caregiver',
            'alias': 'Dad',
            'coin_balance': 488,
          }
        ],
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async => {'success': true};

  @override
  Future<dynamic> put(String path, [Object? body]) async => {'success': true};

  @override
  Future<dynamic> delete(String path, [Object? body]) async => {'success': true};
}

Widget _wrap(Widget child, AppState app) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      theme: buildAppTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tour.seen.welcome': true,
      'tour.seen.daily': true,
      'tour.seen.dashboard': true,
      'tour.seen.activities': true,
      'tour.seen.profile': true,
      'tour.seen.checklist-dismissed': true,
    });
  });

  group('P3-5: Me, the "You" section', () {
    testWidgets('Update profile is the only filled button in the account section',
        (tester) async {
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeProfileApi();
      final app = AppState(api: api)
        ..families = [
          {
            'family_id': 101,
            'name': 'The Henderson Family',
            'role': 'caregiver',
            'alias': 'Dad',
            'coin_balance': 488,
          }
        ]
        ..profile = {'id': 1, 'display_name': 'Dad', 'email': 'dad@example.com'};

      await tester.pumpWidget(_wrap(const ProfileScreen(), app));
      await tester.pumpAndSettle();

      final accountCard = find.widgetWithText(VCard, 'Account settings');
      expect(accountCard, findsOneWidget);

      // Find all FilledButtons inside Account settings
      final filledButtonsInsideCard = find.descendant(
        of: accountCard,
        matching: find.byType(FilledButton),
      );

      // Only one filled button: Update profile
      expect(filledButtonsInsideCard, findsOneWidget);
      expect(
        find.descendant(
          of: filledButtonsInsideCard,
          matching: find.text('Update profile'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Log out is outlined, labeled "Log out", and Delete account is a TextButton below it that opens confirmation',
        (tester) async {
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeProfileApi();
      final app = AppState(api: api)
        ..families = [
          {
            'family_id': 101,
            'name': 'The Henderson Family',
            'role': 'caregiver',
            'alias': 'Dad',
            'coin_balance': 488,
          }
        ]
        ..profile = {'id': 1, 'display_name': 'Dad', 'email': 'dad@example.com'};

      await tester.pumpWidget(_wrap(const ProfileScreen(), app));
      await tester.pumpAndSettle();

      final accountCard = find.widgetWithText(VCard, 'Account settings');

      // Log out button exists as OutlinedButton with text "Log out" (not "Logout")
      final logoutBtn = find.descendant(
        of: accountCard,
        matching: find.widgetWithText(OutlinedButton, 'Log out'),
      );
      expect(logoutBtn, findsOneWidget);
      expect(find.text('Logout'), findsNothing);

      // Delete account is a TextButton (not VButton or OutlinedButton)
      final deleteBtn = find.descendant(
        of: accountCard,
        matching: find.widgetWithText(TextButton, 'Delete account'),
      );
      expect(deleteBtn, findsOneWidget);

      // Verify Delete account is placed below Log out
      final logoutDy = tester.getTopLeft(logoutBtn).dy;
      final deleteDy = tester.getTopLeft(deleteBtn).dy;
      expect(deleteDy, greaterThan(logoutDy),
          reason: 'Delete account must sit after Log out');

      // Tapping Delete account opens confirmation dialog
      await tester.ensureVisible(deleteBtn);
      await tester.pumpAndSettle();
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete account'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your profile will be anonymized'),
        findsOneWidget,
      );
    });

    testWidgets('with purchases disabled there are no two consecutive Dividers',
        (tester) async {
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final api = _FakeProfileApi();
      final app = AppState(api: api)
        ..families = [
          {
            'family_id': 101,
            'name': 'The Henderson Family',
            'role': 'caregiver',
            'alias': 'Dad',
            'coin_balance': 488,
          }
        ]
        ..profile = {'id': 1, 'display_name': 'Dad', 'email': 'dad@example.com'};

      await tester.pumpWidget(_wrap(const ProfileScreen(), app));
      await tester.pumpAndSettle();

      // SubscriptionCard is not available/rendered
      expect(SubscriptionCard.isAvailable(app), isFalse);
      expect(find.byType(SubscriptionCard), findsNothing);

      // Locate the Column inside the Account settings VCard
      final accountCard = find.widgetWithText(VCard, 'Account settings');
      final columnFinder = find.descendant(
        of: accountCard,
        matching: find.byType(Column),
      ).first;

      final columnWidget = tester.widget<Column>(columnFinder);
      final children = columnWidget.children;

      // Check that no two Divider widgets appear consecutively in the Column
      for (var i = 0; i < children.length - 1; i++) {
        final currentIsDivider = children[i] is Divider;
        final nextIsDivider = children[i + 1] is Divider;
        expect(
          currentIsDivider && nextIsDivider,
          isFalse,
          reason: 'Children at index $i and ${i + 1} must not both be Dividers',
        );
      }
    });
  });
}
