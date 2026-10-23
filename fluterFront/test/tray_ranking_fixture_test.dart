import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:carecoins_flutter/utils/tray_ranking.dart';

void main() {
  var file = File('../backend/tests/fixtures/tray_ranking_cases.json');
  if (!file.existsSync()) {
    file = File('backend/tests/fixtures/tray_ranking_cases.json');
  }

  if (!file.existsSync()) {
    throw StateError('tray_ranking_cases.json fixture not found');
  }

  final casesJson = jsonDecode(file.readAsStringSync()) as List<dynamic>;

  group('rankTemplates fixture suite (Dart reference)', () {
    test('constants match specification', () {
      expect(kTrayQuickMax, equals(8));
      expect(kTrayQuickMin, equals(3));
    });

    for (final rawCase in casesJson) {
      final c = rawCase as Map<String, dynamic>;
      final name = c['name'] as String;

      test(name, () {
        final templates = (c['templates'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final activities = (c['activities'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final userId = c['userId']?.toString();
        final now = DateTime.parse(c['now'] as String);

        final result = rankTemplates(
          templates: templates,
          activities: activities,
          userId: userId,
          now: now,
        );

        final actualOrdered =
            result.ordered.map((t) => t['title'] as String).toList();
        final actualQuick =
            result.quick.map((t) => t['title'] as String).toList();

        final expectedOrdered = List<String>.from(c['ordered'] as List<dynamic>);
        final expectedQuick = List<String>.from(c['quick'] as List<dynamic>);

        expect(actualOrdered, equals(expectedOrdered),
            reason: 'Ordered titles mismatch for case: $name');
        expect(actualQuick, equals(expectedQuick),
            reason: 'Quick titles mismatch for case: $name');
      });
    }
  });
}
