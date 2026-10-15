import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Guard tests', () {
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
