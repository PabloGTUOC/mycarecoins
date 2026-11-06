import 'package:flutter_test/flutter_test.dart';

import 'package:carecoins_flutter/screens/daily_screen.dart';

Map<String, dynamic> _act(String id, String start, int mins) => {
      'id': id,
      'starts_at': start,
      'duration_minutes': mins,
    };

/// Column rect in grid space: x range [col/count, (col+1)/count], y range from
/// start to start + max(duration, min card height).
({double l, double r, double t, double b}) _rect(Map<String, dynamic> a) {
  final s = DateTime.parse(a['starts_at'] as String);
  final minutes = s.hour * 60.0 + s.minute;
  final px = kGridHeight / (18 * 60);
  final dur = (a['duration_minutes'] as int) * px;
  final h = dur < kChipMinHeight ? kChipMinHeight : dur;
  final count = a['_colCount'] as int;
  final col = a['_colIndex'] as int;
  return (
    l: col / count,
    r: (col + 1) / count,
    t: minutes * px,
    b: minutes * px + h,
  );
}

bool _overlap(Map<String, dynamic> x, Map<String, dynamic> y) {
  final a = _rect(x);
  final b = _rect(y);
  return a.l < b.r && b.l < a.r && a.t < b.b && b.t < a.b;
}

void main() {
  test('back-to-back 30 min tasks go in different columns', () {
    final r = assignDayColumns([
      _act('a', '2026-11-06T11:03:00', 30),
      _act('b', '2026-11-06T11:33:00', 30),
    ]);
    expect(r[0]['_colIndex'], isNot(r[1]['_colIndex']));
    expect(r[0]['_colCount'], 2);
    expect(_overlap(r[0], r[1]), isFalse);
  });

  test('2 h task next to 30 min task 15 min later gets 2 columns', () {
    final r = assignDayColumns([
      _act('a', '2026-11-06T10:00:00', 120),
      _act('b', '2026-11-06T10:15:00', 30),
    ]);
    expect(r[0]['_colCount'], 2);
    expect(r[0]['_colIndex'], isNot(r[1]['_colIndex']));
    expect(_overlap(r[0], r[1]), isFalse);
  });

  test('well separated tasks stay single column', () {
    final r = assignDayColumns([
      _act('a', '2026-11-06T09:00:00', 30),
      _act('b', '2026-11-06T11:00:00', 30),
    ]);
    expect(r.every((a) => a['_colCount'] == 1), isTrue);
  });
}
