import 'dart:math';

import 'package:flutter/material.dart';

/// A live line of recent values centered on zero, e.g. arm angular velocity,
/// or rising from the bottom edge when [signed] is false, e.g. EMG amplitude.
class MotionLine extends StatelessWidget {
  const MotionLine({
    super.key,
    required this.values,
    this.range = 180,
    this.signed = true,
  });

  final List<double> values;

  /// Value that maps to the top edge (and -range, or 0 when not [signed], to
  /// the bottom).
  final double range;

  /// Whether values go negative. If not, zero sits on the bottom edge.
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _MotionPainter(
        values: List.of(values),
        range: range,
        signed: signed,
        line: scheme.primary,
        axis: scheme.outlineVariant,
      ),
      size: Size.infinite,
    );
  }
}

class _MotionPainter extends CustomPainter {
  _MotionPainter({
    required this.values,
    required this.range,
    required this.signed,
    required this.line,
    required this.axis,
  });

  final List<double> values;
  final double range;
  final bool signed;
  final Color line;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    // y of the zero line, and pixels per unit of range above it.
    final zero = signed ? size.height / 2 : size.height;
    final scale = zero / range;
    canvas.drawLine(
      Offset(0, zero),
      Offset(size.width, zero),
      Paint()
        ..color = axis
        ..strokeWidth = 1,
    );
    if (values.length < 2) return;

    final path = Path();
    final dx = size.width / (values.length - 1);
    for (var i = 0; i < values.length; i++) {
      final y = zero - values[i].clamp(signed ? -range : 0, range) * scale;
      i == 0 ? path.moveTo(0, y) : path.lineTo(i * dx, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MotionPainter old) => true;
}

/// A ring that fills with fatigue, green to red.
class FatigueRing extends StatelessWidget {
  const FatigueRing({super.key, required this.fatigue, required this.child});

  /// 0..1, or null when the model isn't streaming.
  final double? fatigue;
  final Widget child;

  static Color colorFor(double fatigue) {
    if (fatigue < 0.6) return const Color(0xFF2E9E6A);
    if (fatigue < 0.85) return const Color(0xFFE0A100);
    return const Color(0xFFD9452B);
  }

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: fatigue ?? 0),
      duration: const Duration(milliseconds: 400),
      builder: (context, value, child) => CustomPaint(
        painter: _RingPainter(
          value: value,
          track: track,
          fill: colorFor(value),
        ),
        child: child,
      ),
      child: Center(child: child),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.track, required this.fill});

  final double value;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: min(size.width, size.height) / 2 - stroke / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * pi, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(rect, -pi / 2, 2 * pi * value, false, paint..color = fill);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.fill != fill || old.track != track;
}

/// Simple vertical bars, oldest on the left, in [slots] fixed-width columns.
class RepBars extends StatelessWidget {
  const RepBars({super.key, required this.values, this.slots = 10});

  final List<int> values;
  final int slots;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.labelSmall;
    final top = values.fold<int>(1, max);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final v in values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('$v', style: text),
                  const SizedBox(height: 4),
                  Container(
                    height: max(4, 80 * v / top),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        for (var i = values.length; i < slots; i++)
          const Expanded(child: SizedBox()),
      ],
    );
  }
}

/// One bar per day with a weekday label; the last bar (today) is
/// highlighted.
class DayBars extends StatelessWidget {
  const DayBars({super.key, required this.values, required this.labels});

  final List<int> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final top = values.fold<int>(1, max);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (values[i] > 0) Text('${values[i]}', style: text.labelSmall),
                const SizedBox(height: 4),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: values[i] / top),
                  duration: Duration(milliseconds: 500 + 60 * i),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => Container(
                    height: max(6, 72 * t),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: i == values.length - 1
                          ? scheme.primary
                          : scheme.primary.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  labels[i],
                  style: text.labelSmall?.copyWith(
                    fontWeight: i == values.length - 1
                        ? FontWeight.w700
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
