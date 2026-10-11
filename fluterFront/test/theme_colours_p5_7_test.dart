import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P5-7: Colours from the theme', () {
    test(
        'no opaque raw Color literals outside lib/theme/, landing_screen, and Google logo in login_screen',
        () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib directory must exist');

      final pattern = RegExp(r'Color\(0x[Ff]{2}[0-9A-Fa-f]{6}\)');
      final violations = <String>[];
      int loginMatches = 0;

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        // Skip lib/theme/ directory and lib/screens/landing_screen.dart
        final normalizedPath = entity.path.replaceAll(r'\', '/');
        if (normalizedPath.contains('lib/theme/') ||
            normalizedPath.endsWith('lib/screens/landing_screen.dart')) {
          continue;
        }

        final isLoginScreen =
            normalizedPath.endsWith('lib/screens/login_screen.dart');
        final lines = entity.readAsLinesSync();

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final matches = pattern.allMatches(line);
          for (final _ in matches) {
            if (isLoginScreen) {
              loginMatches++;
            } else {
              violations.add('${entity.path}:${i + 1}: ${line.trim()}');
            }
          }
        }
      }

      expect(
        loginMatches,
        equals(5),
        reason:
            'lib/screens/login_screen.dart must contain exactly 5 Google logo color literals',
      );

      expect(
        violations,
        isEmpty,
        reason:
            'Found opaque Color(0xFF...) literals outside allowed files:\n${violations.join('\n')}',
      );
    });
  });
}
