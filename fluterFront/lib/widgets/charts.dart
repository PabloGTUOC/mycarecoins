import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Minimal chart widgets for the Stats screen.
/// Kept dependency-free: a smooth area line chart and a stacked bar chart.

class LineAreaChart extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final Color color;
  final double height;

  const LineAreaChart({
    super.key,
    required this.labels,
    required this.values,
    this.color = AppColors.primary,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _LinePainter(labels, values, color)),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<String> labels;
  final List<double> values;
  final Color color;
  _LinePainter(this.labels, this.values, this.color);

  static const _pad = EdgeInsets.fromLTRB(36, 12, 12, 26);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final plot = Rect.fromLTRB(_pad.left, _pad.top, size.width - _pad.right,
        size.height - _pad.bottom);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final top = maxV <= 0 ? 1.0 : maxV * 1.15;

    // gridlines + y labels
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = plot.bottom - plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _text(canvas, (top * i / 3).round().toString(), Offset(2, y - 6), 10,
          AppColors.textSecondary);
    }

    Offset pt(int i) {
      final x = values.length == 1
          ? plot.center.dx
          : plot.left + plot.width * i / (values.length - 1);
      final y = plot.bottom - plot.height * (values[i] / top);
      return Offset(x, y);
    }

    // area + line
    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p0 = pt(i - 1), p1 = pt(i);
      final cx = (p0.dx + p1.dx) / 2;
      line.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }
    final area = Path.from(line)
      ..lineTo(pt(values.length - 1).dx, plot.bottom)
      ..lineTo(pt(0).dx, plot.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0)],
        ).createShader(plot),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(pt(i), 3.5, Paint()..color = color);
      canvas.drawCircle(pt(i), 2, Paint()..color = Colors.white);
    }

    // x labels (skip to avoid crowding)
    final step = (labels.length / 6).ceil().clamp(1, 100);
    for (var i = 0; i < labels.length; i += step) {
      _text(canvas, labels[i], Offset(pt(i).dx - 16, plot.bottom + 6), 10,
          AppColors.textSecondary);
    }
  }

  void _text(Canvas canvas, String s, Offset o, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: size, color: color, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.values != values || old.labels != labels;
}

class LineSeries {
  final String label;
  final Color color;
  final List<double> values; // one per x label
  const LineSeries(this.label, this.color, this.values);
}

/// Multi-series smooth line chart (compare-caregivers mode of the ECharts
/// trend panel). No area fill; a legend row sits above the plot.
class MultiLineChart extends StatelessWidget {
  final List<String> labels;
  final List<LineSeries> series;
  final double height;

  const MultiLineChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: s.color, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(s.label,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _MultiLinePainter(labels, series)),
        ),
      ],
    );
  }
}

class _MultiLinePainter extends CustomPainter {
  final List<String> labels;
  final List<LineSeries> series;
  _MultiLinePainter(this.labels, this.series);

  static const _pad = EdgeInsets.fromLTRB(36, 12, 12, 26);

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty || series.isEmpty) return;
    final plot = Rect.fromLTRB(_pad.left, _pad.top, size.width - _pad.right,
        size.height - _pad.bottom);
    var maxV = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        if (v > maxV) maxV = v;
      }
    }
    final top = maxV <= 0 ? 1.0 : maxV * 1.15;

    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = plot.bottom - plot.height * i / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _text(canvas, (top * i / 3).round().toString(), Offset(2, y - 6), 10,
          AppColors.textSecondary);
    }

    for (final s in series) {
      Offset pt(int i) {
        final x = labels.length == 1
            ? plot.center.dx
            : plot.left + plot.width * i / (labels.length - 1);
        final v = i < s.values.length ? s.values[i] : 0.0;
        return Offset(x, plot.bottom - plot.height * (v / top));
      }

      final line = Path()..moveTo(pt(0).dx, pt(0).dy);
      for (var i = 1; i < labels.length; i++) {
        final p0 = pt(i - 1), p1 = pt(i);
        final cx = (p0.dx + p1.dx) / 2;
        line.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      for (var i = 0; i < labels.length; i++) {
        canvas.drawCircle(pt(i), 3, Paint()..color = s.color);
      }
    }

    final step = (labels.length / 6).ceil().clamp(1, 100);
    for (var i = 0; i < labels.length; i += step) {
      final x = labels.length == 1
          ? plot.center.dx
          : plot.left + plot.width * i / (labels.length - 1);
      _text(canvas, labels[i], Offset(x - 16, plot.bottom + 6), 10,
          AppColors.textSecondary);
    }
  }

  void _text(Canvas canvas, String s, Offset o, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: size, color: color, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant _MultiLinePainter old) =>
      old.labels != labels || old.series != series;
}

class DonutSegment {
  final String label;
  final double value;
  final Color color;
  const DonutSegment(this.label, this.value, this.color);
}

/// Donut chart with centred total and legend (the ECharts 40%/65% pies).
class DonutChart extends StatelessWidget {
  final List<DonutSegment> segments;
  final double size;

  const DonutChart({super.key, required this.segments, this.size = 180});

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (acc, s) => acc + s.value);
    return Column(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DonutPainter(segments, total),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(total.round().toString(),
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800)),
                  Text(AppLocalizations.of(context).totalLower,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            for (final s in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: s.color, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('${s.label} (${s.value.round()})',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<DonutSegment> segments;
  final double total;
  _DonutPainter(this.segments, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 8;
    final stroke = radius * 0.42;
    var start = -1.5708; // 12 o'clock
    for (final s in segments) {
      if (s.value <= 0) continue;
      final sweep = 6.28318 * (s.value / total);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - stroke / 2),
        start,
        sweep - 0.03,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = s.color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.segments != segments || old.total != total;
}

class StackedBarSeries {
  final String label;
  final Color color;
  final List<double> values; // one per x label
  const StackedBarSeries(this.label, this.color, this.values);
}

class StackedBarChart extends StatelessWidget {
  final List<String> labels;
  final List<StackedBarSeries> series;
  final double height;

  const StackedBarChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: s.color, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(s.label,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _StackedBarPainter(labels, series)),
        ),
      ],
    );
  }
}

class _StackedBarPainter extends CustomPainter {
  final List<String> labels;
  final List<StackedBarSeries> series;
  _StackedBarPainter(this.labels, this.series);

  static const _pad = EdgeInsets.fromLTRB(36, 8, 12, 26);

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty) return;
    final plot = Rect.fromLTRB(_pad.left, _pad.top, size.width - _pad.right,
        size.height - _pad.bottom);

    double maxPos = 0, maxNeg = 0;
    for (var i = 0; i < labels.length; i++) {
      double pos = 0, neg = 0;
      for (final s in series) {
        final v = i < s.values.length ? s.values[i] : 0;
        if (v >= 0) {
          pos += v;
        } else {
          neg += v;
        }
      }
      if (pos > maxPos) maxPos = pos;
      if (neg < maxNeg) maxNeg = neg;
    }
    final top = maxPos <= 0 ? 1.0 : maxPos * 1.1;
    final bottom = maxNeg * 1.1; // <= 0
    final range = top - bottom;
    double yFor(double v) => plot.bottom - plot.height * ((v - bottom) / range);

    // zero line + edges
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(plot.left, yFor(0)), Offset(plot.right, yFor(0)), grid);
    _text(canvas, '0', Offset(20, yFor(0) - 6), 10, AppColors.textSecondary);
    _text(canvas, top.round().toString(), Offset(2, plot.top - 4), 10,
        AppColors.textSecondary);
    if (bottom < 0) {
      _text(canvas, bottom.round().toString(), Offset(2, plot.bottom - 8), 10,
          AppColors.textSecondary);
    }

    final slot = plot.width / labels.length;
    final barW = (slot * 0.55).clamp(6.0, 44.0);
    for (var i = 0; i < labels.length; i++) {
      final cx = plot.left + slot * (i + 0.5);
      double posCursor = 0, negCursor = 0;
      for (final s in series) {
        final v = i < s.values.length ? s.values[i] : 0.0;
        if (v == 0) continue;
        late Rect r;
        if (v > 0) {
          r = Rect.fromLTRB(cx - barW / 2, yFor(posCursor + v), cx + barW / 2,
              yFor(posCursor));
          posCursor += v;
        } else {
          r = Rect.fromLTRB(cx - barW / 2, yFor(negCursor), cx + barW / 2,
              yFor(negCursor + v));
          negCursor += v;
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(2)),
          Paint()..color = s.color,
        );
      }
      final step = (labels.length / 6).ceil().clamp(1, 100);
      if (i % step == 0) {
        _text(canvas, labels[i], Offset(cx - 18, plot.bottom + 6), 10,
            AppColors.textSecondary);
      }
    }
  }

  void _text(Canvas canvas, String s, Offset o, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: size, color: color, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant _StackedBarPainter old) =>
      old.labels != labels || old.series != series;
}
