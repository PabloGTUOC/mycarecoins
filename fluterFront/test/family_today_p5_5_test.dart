import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:carecoins_flutter/l10n/app_localizations.dart';
import 'package:carecoins_flutter/screens/daily_screen.dart';
import 'package:carecoins_flutter/screens/dashboard_screen.dart';
import 'package:carecoins_flutter/services/api_client.dart';
import 'package:carecoins_flutter/state/app_state.dart';

class _FakeApiClient extends ApiClient {
  final List<Map<String, dynamic>> activities;

  _FakeApiClient({this.activities = const []});

  @override
  Future<dynamic> get(String path) async {
    if (path.startsWith('/api/activities')) {
      return {'activities': activities};
    }
    if (path.startsWith('/api/absences')) {
      return {'absences': []};
    }
    if (path.startsWith('/api/personal-time')) {
      return {'requests': []};
    }
    if (path.startsWith('/api/dashboard/')) {
      return {
        'members': [],
        'calendar': [],
        'objectsOfCare': [],
      };
    }
    if (path.startsWith('/api/marketplace/rewards/')) {
      return {'rewards': [], 'claimed': []};
    }
    if (path.startsWith('/api/stats')) {
      return {'kpis': {}, 'trend': [], 'categories': []};
    }
    if (path == '/api/me') {
      return {
        'user': {'id': 1, 'display_name': 'Me'},
        'families': [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ],
      };
    }
    return {};
  }
}

Widget _wrap(Widget child, AppState app, [Locale locale = const Locale('en')]) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tour.seen.daily': true,
      'tour.seen.dashboard': true,
    });
  });

  group('P5-5: Family and Today leftovers', () {
    test('greetingFor returns appropriate greeting by hour', () {
      final l = lookupAppLocalizations(const Locale('en'));
      expect(greetingFor(0, l), l.greetingEvening);
      expect(greetingFor(4, l), l.greetingEvening);
      expect(greetingFor(5, l), l.greetingMorning);
      expect(greetingFor(11, l), l.greetingMorning);
      expect(greetingFor(12, l), l.greetingAfternoon);
      expect(greetingFor(13, l), l.greetingAfternoon);
      expect(greetingFor(17, l), l.greetingAfternoon);
      expect(greetingFor(18, l), l.greetingEvening);
      expect(greetingFor(23, l), l.greetingEvening);
    });

    test('dayToday is not all-caps in any language, and is Today in en', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final es = lookupAppLocalizations(const Locale('es'));
      final fr = lookupAppLocalizations(const Locale('fr'));
      final de = lookupAppLocalizations(const Locale('de'));

      expect(en.dayToday, 'Today');
      expect(es.dayToday, 'Hoy');
      expect(fr.dayToday, 'Auj.');
      expect(de.dayToday, 'Heute');

      for (final l in [en, es, fr, de]) {
        expect(l.dayToday != l.dayToday.toUpperCase(), isTrue,
            reason: '${l.localeName} dayToday (${l.dayToday}) must not be all-caps');
      }
    });

    test('dashMyTasksWaiting contains someone else in en and localized in other locales', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.dashMyTasksWaiting(1), contains('someone else'));
      expect(en.dashMyTasksWaiting(4), contains('someone else'));

      final es = lookupAppLocalizations(const Locale('es'));
      expect(es.dashMyTasksWaiting(4), contains('otra persona'));

      final fr = lookupAppLocalizations(const Locale('fr'));
      expect(fr.dashMyTasksWaiting(4), contains('autre personne'));

      final de = lookupAppLocalizations(const Locale('de'));
      expect(de.dashMyTasksWaiting(4), contains('anderen Person'));
    });

    testWidgets('Today label fits in 44 px without overflow', (tester) async {
      final l = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 44,
              child: Text(
                l.dayToday,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.text('Today'));
      expect(size.width, lessThanOrEqualTo(44.0));
    });

    testWidgets('Today on a past day: no _TaskTray text drag onto the day, banner dayHasPassed shown',
        (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final template = {
        'id': 201,
        'title': 'Vacuuming',
        'type': 'household',
        'category': 'care',
        'is_template': true,
        'status': 'approved',
        'coin_value': 10,
        'duration_minutes': 30,
      };

      final api = _FakeApiClient(activities: [template]);
      final app = AppState(api: api)
        ..families = [
          {'family_id': 1, 'coin_balance': 150, 'role': 'caregiver'}
        ]
        ..profile = {'id': 1, 'display_name': 'Me'};

      final now = DateTime.parse('2026-10-10T12:00:00Z');
      await tester.pumpWidget(_wrap(DailyScreen(date: '2026-10-07', now: now, isTab: true), app));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('en'));

      // No tray header label "Tasks · drag onto the day"
      expect(find.text(l.trayHeaderLabel), findsNothing);
      expect(find.text('Vacuuming'), findsNothing);

      // Banner "This day has passed" is shown
      expect(find.text(l.dayHasPassed), findsOneWidget);
    });
  });
}
