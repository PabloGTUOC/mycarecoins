import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:carecoins_flutter/theme/app_theme.dart';

/// Relative luminance according to WCAG 2.1 specs.
double relativeLuminance(Color c) {
  double channel(double value) {
    return value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channel(c.r);
  final g = channel(c.g);
  final b = channel(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Contrast ratio (L1 + 0.05) / (L2 + 0.05).
double contrastRatio(Color c1, Color c2) {
  final l1 = relativeLuminance(c1);
  final l2 = relativeLuminance(c2);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('Wada Palette Contrast Ratios (PAL-1)', () {
    test('Every people entry has ink on soft >= 4.5 and ink on white >= 4.5', () {
      expect(AppColors.people, hasLength(4));
      for (final person in AppColors.people) {
        final inkOnSoft = contrastRatio(person.ink, person.soft);
        expect(
          inkOnSoft,
          greaterThanOrEqualTo(4.5),
          reason: 'ink on soft contrast $inkOnSoft must be >= 4.5',
        );

        final inkOnWhite = contrastRatio(person.ink, Colors.white);
        expect(
          inkOnWhite,
          greaterThanOrEqualTo(4.5),
          reason: 'ink on white contrast $inkOnWhite must be >= 4.5',
        );
      }
    });

    test('coinInk on coinSoft >= 4.5', () {
      final ratio = contrastRatio(AppColors.coinInk, AppColors.coinSoft);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('textPrimary on coin >= 4.5', () {
      final ratio = contrastRatio(AppColors.textPrimary, AppColors.coin);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('white on primary >= 4.5', () {
      final ratio = contrastRatio(Colors.white, AppColors.primary);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('primaryInk on primarySoft >= 4.5', () {
      final ratio = contrastRatio(AppColors.primaryInk, AppColors.primarySoft);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });
  });

  group('Static scan of lib/ (except lib/theme/)', () {
    test('No deprecated AppColors tokens and no withValues on PersonColor mark', () {
      final forbiddenPattern = RegExp(
          r'AppColors\.(indigo|violet|gold|accentGradient|softAccents|accents\b|badge(Child|Pet|Elderly|Caregiver|Member))');
      final alphaMarkTextPattern = RegExp(r'\.mark\.withValues\(alpha:');

      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.contains('lib/theme/'));

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        final forbiddenMatches = forbiddenPattern.allMatches(content);
        expect(
          forbiddenMatches.isEmpty,
          isTrue,
          reason:
              '${file.path} contains deprecated AppColors tokens: ${forbiddenMatches.map((m) => m.group(0)).toList()}',
        );

        final alphaMatches = alphaMarkTextPattern.allMatches(content);
        expect(
          alphaMatches.isEmpty,
          isTrue,
          reason:
              '${file.path} uses withValues(alpha:) on a PersonColor mark for text',
        );
      }
    });
  });
}
