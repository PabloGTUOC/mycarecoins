import 'package:flutter_test/flutter_test.dart';
import 'package:carecoins_flutter/widgets/charts.dart';

void main() {
  group('xLabelLeft', () {
    test('centres the label on its point', () {
      expect(xLabelLeft(200, 60, 400), 170);
    });

    test('keeps the last label inside the right edge', () {
      // "Sep 2026" at the last point, 12 px from a 340 px chart's edge.
      expect(xLabelLeft(328, 56, 340), 284);
    });

    test('keeps the first label inside the left edge', () {
      expect(xLabelLeft(10, 56, 340), 0);
    });

    test('a label wider than the chart starts at 0', () {
      expect(xLabelLeft(50, 120, 100), 0);
    });
  });
}
