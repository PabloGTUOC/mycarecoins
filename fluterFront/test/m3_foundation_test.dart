import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/shell.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';
import 'package:carecoins_flutter/widgets/ui.dart';

class FakeM3ApiClient extends ApiClient {
  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) return {'activities': []};
    if (path.startsWith('/api/absences')) return {'absences': []};
    if (path.startsWith('/api/personal-time')) return {'requests': []};
    if (path.startsWith('/api/dashboard/')) {
      return {'members': [], 'calendar': [], 'objectsOfCare': []};
    }
    if (path.startsWith('/api/marketplace/rewards/')) {
      return {'rewards': [], 'claimed': []};
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Me'},
        'families': [
          {'family_id': 1, 'alias': 'Familia', 'coin_balance': 250, 'role': 'caregiver'}
        ],
      };
    }
    if (path.startsWith('/api/me/ledger')) return {'ledger': []};
    if (path.startsWith('/api/me/deletion-requests')) return {'requests': []};
    return {};
  }

  @override
  Future<dynamic> post(String path, [Object? body]) async => {'success': true};
}

Widget _wrap(Widget child, AppState app, {ThemeData? theme}) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      theme: theme ?? buildAppTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
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
      'tour.seen.marketplace': true,
      'tour.seen.profile': true,
      'tour.seen.checklist-dismissed': true,
    });
  });

  group('P2-3a: Component themes and CareColors ThemeExtension', () {
    testWidgets('buildAppTheme configures M3 component themes and CareColors',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ));
      await tester.pumpAndSettle();

      final theme = Theme.of(ctx);
      final careColors = theme.extension<CareColors>();
      expect(careColors, isNotNull);
      expect(careColors!.primaryInk, AppColors.primaryInk);
      expect(careColors.successInk, AppColors.successInk);
      expect(careColors.successStrong, AppColors.successStrong);
      expect(careColors.warningInk, AppColors.warningInk);
      expect(careColors.warningStrong, AppColors.warningStrong);
      expect(careColors.dangerInk, AppColors.dangerInk);

      expect(theme.appBarTheme.backgroundColor, AppColors.surface);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);
      expect(theme.appBarTheme.centerTitle, false);

      expect(theme.navigationBarTheme.indicatorColor, AppColors.primarySoft);
      expect(theme.navigationBarTheme.labelBehavior,
          NavigationDestinationLabelBehavior.alwaysShow);

      expect(theme.bottomSheetTheme.showDragHandle, true);
      expect(theme.bottomSheetTheme.backgroundColor, AppColors.surface);
      expect(theme.badgeTheme.backgroundColor, AppColors.primary);
    });
  });

  group('P2-3a: Top app bar on narrow layouts', () {
    testWidgets('AppBar shows tab title and actions on narrow layouts',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: FakeM3ApiClient())
        ..families = [
          {'family_id': 1, 'alias': 'Familia', 'coin_balance': 250, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      // Launch on Family tab (index 1)
      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      // Top AppBar is present with tab title "Family"
      final appBarFinder = find.byType(AppBar);
      expect(appBarFinder, findsOneWidget);
      expect(
          find.descendant(of: appBarFinder, matching: find.text('Family')),
          findsOneWidget);

      // Actions: help icon and balance pill
      expect(
          find.descendant(
              of: appBarFinder, matching: find.byIcon(Icons.help_outline_rounded)),
          findsOneWidget);
      expect(
          find.descendant(
              of: appBarFinder, matching: find.byType(CoinBalancePill)),
          findsOneWidget);
      expect(
          find.descendant(of: appBarFinder, matching: find.text('250')),
          findsOneWidget);
    });

    testWidgets('Wide layout does not show Shell AppBar but keeps _PillHeader',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: FakeM3ApiClient())
        ..families = []
        ..profile = {'id': 1, 'display_name': 'Me'};

      // Launch on Family tab (index 1)
      await tester.pumpWidget(_wrap(const Shell(initialIndex: 1), app));
      await tester.pumpAndSettle();

      // No Shell AppBar
      expect(find.byType(AppBar), findsNothing);
      // Pill header with logo is present on wide
      expect(find.text('CareCoins'), findsOneWidget);
    });
  });

  group('P2-3a: PageHeading title on narrow vs wide', () {
    testWidgets('PageHeading does not render title on narrow layouts',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PageHeading(
            title: 'Family Hub',
            subtitle: 'This subtitle should be dropped on narrow',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Title is not rendered
      expect(find.text('Family Hub'), findsNothing);
      // Non-tappable subtitle is dropped
      expect(find.text('This subtitle should be dropped on narrow'), findsNothing);
    });

    testWidgets('PageHeading keeps tappable subtitle on narrow layouts',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PageHeading(
            title: 'Family Hub',
            subtitle: 'Good morning Alex. Tap to see today.',
            onSubtitleTap: () => tapped = true,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Title is still omitted
      expect(find.text('Family Hub'), findsNothing);
      // Tappable subtitle is preserved as a body line
      expect(find.text('Good morning Alex. Tap to see today.'), findsOneWidget);

      await tester.tap(find.text('Good morning Alex. Tap to see today.'));
      expect(tapped, isTrue);
    });

    testWidgets('PageHeading renders both title and subtitle on wide layouts',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PageHeading(
            title: 'Family Hub',
            subtitle: 'Wide subtitle should remain',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Family Hub'), findsOneWidget);
      expect(find.text('Wide subtitle should remain'), findsOneWidget);
    });
  });

  group('P2-3a: NavigationBar selected index follows taps', () {
    testWidgets('NavigationBar selected index follows destination taps',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final app = AppState(api: FakeM3ApiClient())
        ..families = [
          {'family_id': 1, 'alias': 'Familia', 'coin_balance': 250, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      await tester.pumpWidget(_wrap(const Shell(initialIndex: 0), app));
      await tester.pumpAndSettle();

      NavigationBar navBar() =>
          tester.widget<NavigationBar>(find.byType(NavigationBar));

      expect(navBar().selectedIndex, 0);

      // Tap Family
      await tester.tap(find.text('Family'));
      await tester.pumpAndSettle();
      expect(navBar().selectedIndex, 1);

      // Tap Tasks
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();
      expect(navBar().selectedIndex, 2);

      // Tap Rewards
      await tester.tap(find.text('Rewards'));
      await tester.pumpAndSettle();
      expect(navBar().selectedIndex, 3);

      // Tap Me
      await tester.tap(find.text('Me'));
      await tester.pumpAndSettle();
      expect(navBar().selectedIndex, 4);

      // Tap Today
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(navBar().selectedIndex, 0);
    });
  });
}
