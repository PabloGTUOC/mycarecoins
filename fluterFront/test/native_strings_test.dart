import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  File findFile(String relativePath) {
    var file = File(relativePath);
    if (!file.existsSync()) {
      file = File('fluterFront/$relativePath');
    }
    if (!file.existsSync()) {
      file = File('../$relativePath');
    }
    return file;
  }

  group('Native Strings Guard Tests', () {
    test('ios/Shared/Localizable.xcstrings is valid, translated in 4 languages with matching placeholders', () {
      final file = findFile('ios/Shared/Localizable.xcstrings');
      expect(file.existsSync(), isTrue,
          reason: 'ios/Shared/Localizable.xcstrings must exist');

      final content = file.readAsStringSync();
      final Map<String, dynamic> json = jsonDecode(content);

      expect(json['sourceLanguage'], equals('en'));
      expect(json['version'], equals('1.0'));
      expect(json['strings'], isA<Map<String, dynamic>>());

      final strings = json['strings'] as Map<String, dynamic>;

      const requiredKeys = [
        'widget.start',
        'widget.done',
        'widget.stop',
        'widget.undo',
        'widget.careNow',
        'widget.householdNow',
        'widget.title.care',
        'widget.title.household',
        'widget.started',
        'widget.logged',
        'widget.stopped',
        'widget.undone',
        'widget.running',
        'widget.next',
        'widget.needsYou',
        'widget.coins',
        'widget.notConnected',
        'widget.noTasks',
        'widget.error.generic',
        'widget.error.overlap',
        'widget.error.alreadyRunning',
        'widget.error.undoExpired',
        'widget.error.revoked',
        'widget.a11y.start',
        'widget.a11y.done',
        'widget.a11y.balance',
        'widget.tasks.name',
        'widget.tasks.description',
        'widget.balance.name',
        'widget.balance.description',
      ];

      for (final key in requiredKeys) {
        expect(strings.containsKey(key), isTrue,
            reason: 'Required key $key missing from Localizable.xcstrings');
      }

      final placeholderRegex = RegExp(r'%(\d+\$)?(@|lld|d)');
      List<String> extractPlaceholders(String text) {
        final matches = placeholderRegex.allMatches(text);
        final list = matches.map((m) => m.group(0)!).toList()..sort();
        return list;
      }

      const expectedLangs = ['en', 'es', 'fr', 'de'];

      for (final entry in strings.entries) {
        final key = entry.key;
        final keyData = entry.value as Map<String, dynamic>;
        final localizations = keyData['localizations'] as Map<String, dynamic>?;

        expect(localizations, isNotNull,
            reason: 'Key $key missing localizations map');

        final langPlaceholders = <String, List<String>>{};

        for (final lang in expectedLangs) {
          expect(localizations!.containsKey(lang), isTrue,
              reason: 'Key $key missing language "$lang"');
          final langData = localizations[lang] as Map<String, dynamic>?;
          expect(langData, isNotNull,
              reason: 'Key $key has null data for "$lang"');

          final stringUnit = langData!['stringUnit'] as Map<String, dynamic>?;
          expect(stringUnit, isNotNull,
              reason: 'Key $key missing stringUnit for "$lang"');

          expect(stringUnit!['state'], equals('translated'),
              reason: 'Key $key language "$lang" state is not "translated"');

          final value = stringUnit['value'] as String?;
          expect(value, isNotNull,
              reason: 'Key $key language "$lang" value is null');
          expect(value!.isNotEmpty, isTrue,
              reason: 'Key $key language "$lang" value is empty');

          langPlaceholders[lang] = extractPlaceholders(value);
        }

        final enPlaceholders = langPlaceholders['en']!;
        for (final lang in ['es', 'fr', 'de']) {
          expect(langPlaceholders[lang], equals(enPlaceholders),
              reason: 'Key $key language "$lang" placeholders ${langPlaceholders[lang]} do not match English $enPlaceholders');
        }
      }
    });
  });
}
