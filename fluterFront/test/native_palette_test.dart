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

  group('Native Palette Guard Tests', () {
    test('ios/Shared/Palette.swift tokens match AppColors in lib/theme/app_theme.dart', () {
      final paletteFile = findFile('ios/Shared/Palette.swift');
      expect(paletteFile.existsSync(), isTrue,
          reason: 'ios/Shared/Palette.swift must exist');

      final themeFile = findFile('lib/theme/app_theme.dart');
      expect(themeFile.existsSync(), isTrue,
          reason: 'lib/theme/app_theme.dart must exist');

      final paletteContent = paletteFile.readAsStringSync();
      final themeContent = themeFile.readAsStringSync();

      // Extract AppColors class body only
      final appColorsMatch = RegExp(r'abstract class AppColors \{([^}]+(?:\{[^}]*\}[^}]*)*)\}')
          .firstMatch(themeContent);
      expect(appColorsMatch, isNotNull,
          reason: 'abstract class AppColors must exist in app_theme.dart');
      final appColorsBody = appColorsMatch!.group(1)!;

      final appColorRegex = RegExp(r'static const (\w+) = Color\(0xFF([0-9A-Fa-f]{6})\)');
      final appColors = <String, String>{};
      for (final match in appColorRegex.allMatches(appColorsBody)) {
        appColors[match.group(1)!] = match.group(2)!.toUpperCase();
      }

      final swiftRegex = RegExp(r'static let (\w+) = Color\(hex: 0x([0-9A-Fa-f]{6})\)');
      final swiftColors = <String, String>{};
      for (final match in swiftRegex.allMatches(paletteContent)) {
        swiftColors[match.group(1)!] = match.group(2)!.toUpperCase();
      }

      // 1. Every Swift token must exist in AppColors with the same hex
      for (final entry in swiftColors.entries) {
        expect(appColors.containsKey(entry.key), isTrue,
            reason: 'Token ${entry.key} from Palette.swift missing in AppColors');
        expect(entry.value, equals(appColors[entry.key]),
            reason: 'Token ${entry.key} hex 0x${entry.value} does not match AppColors 0x${appColors[entry.key]}');
      }

      // 2. The required tokens from §4 must all be present in Palette.swift
      const requiredTokens = [
        'bg', 'surface', 'border', 'textPrimary', 'textSecondary',
        'primary', 'primarySoft', 'primaryInk',
        'success', 'successSoft', 'successInk',
        'warning', 'warningSoft', 'warningInk',
        'danger', 'dangerSoft', 'dangerInk',
        'ink', 'inkMuted', 'successOnDark', 'dangerOnDark',
        'coin', 'coinSoft', 'coinInk',
      ];

      for (final token in requiredTokens) {
        expect(swiftColors.containsKey(token), isTrue,
            reason: 'Required token $token missing from Palette.swift');
      }
    });
  });
}
