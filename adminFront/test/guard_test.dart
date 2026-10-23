import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_front/theme.dart';

void main() {
  group('Guard tests', () {
    test(
        'AppColors.primary, primarySoft, primaryInk match fluterFront app_theme.dart',
        () {
      var file = File('../fluterFront/lib/theme/app_theme.dart');
      if (!file.existsSync()) {
        file = File('fluterFront/lib/theme/app_theme.dart');
      }
      expect(file.existsSync(), isTrue,
          reason: 'fluterFront/lib/theme/app_theme.dart must exist');

      final content = file.readAsStringSync();

      Color parseToken(String tokenName) {
        final match = RegExp(
          'static\\s+const\\s+$tokenName\\s*=\\s*Color\\((0x[0-9a-fA-F]+)\\);',
        ).firstMatch(content);
        expect(match, isNotNull,
            reason: 'Token $tokenName not found in fluterFront app_theme.dart');
        return Color(int.parse(match!.group(1)!));
      }

      expect(AppColors.primary, equals(parseToken('primary')));
      expect(AppColors.primarySoft, equals(parseToken('primarySoft')));
      expect(AppColors.primaryInk, equals(parseToken('primaryInk')));
    });

    test(
        'no file under adminFront/lib imports from fluterFront (package or relative path)',
        () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue,
          reason: 'adminFront/lib must exist when running test from adminFront');

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        final lines = content.split('\n');

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('import ') || line.startsWith('export ')) {
            expect(
              line.contains('package:carecoins'),
              isFalse,
              reason:
                  'Forbidden app import in ${file.path}:${i + 1}: "$line"',
            );
            expect(
              line.contains('package:carecoins_flutter'),
              isFalse,
              reason:
                  'Forbidden app import in ${file.path}:${i + 1}: "$line"',
            );
            expect(
              line.contains('fluterFront'),
              isFalse,
              reason:
                  'Forbidden fluterFront path in ${file.path}:${i + 1}: "$line"',
            );
          }
        }
      }
    });

    test(
        'no string literal shown to the user outside strings.dart via Text("...") or Text(\'...\')',
        () {
      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('strings.dart'));

      // Matches Text(' or Text(" (including whitespace between Text and quote)
      final textSingleQuoteRegex = RegExp(r"Text\s*\(\s*'");
      final textDoubleQuoteRegex = RegExp(r'Text\s*\(\s*"');

      final violations = <String>[];

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        if (textSingleQuoteRegex.hasMatch(content) ||
            textDoubleQuoteRegex.hasMatch(content)) {
          violations.add(file.path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'String literals found in Text(...) widgets outside strings.dart:\n${violations.join('\n')}',
      );
    });
  });
}
