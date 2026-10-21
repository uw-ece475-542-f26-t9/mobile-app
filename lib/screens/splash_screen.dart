import 'dart:math';

import 'package:flutter/material.dart';

/// Animated intro: a ring sweeps green → amber → red like a set building
/// fatigue, the dumbbell pops in, then the name and tagline rise into place.
/// Tap anywhere to skip.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward().whenComplete(_finish);

  bool _done = false;

  late final _ring = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.55, curve: Curves.easeInOutCubic),
  );
  late final _icon = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.15, 0.5, curve: Curves.elasticOut),
  );
  late final _title = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.45, 0.75, curve: Curves.easeOutCubic),
  );
  late final _tagline = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.6, 0.9, curve: Curves.easeOutCubic),
  );

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B3C49), Color(0xFF0F7C8C)],
            ),
          ),
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 168,
                    child: CustomPaint(
                      painter: _SweepRingPainter(_ring.value),
                      child: Center(
                        child: Transform.scale(
                          scale: _icon.value,
                          child: Transform.rotate(
                            angle: -pi / 4 * (1 - _icon.value),
                            child: const Icon(
                              Icons.fitness_center,
                              size: 72,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _Rise(
                    t: _title.value,
                    child: Text(
                      'Fatigue Coach',
                      style: text.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Rise(
                    t: _tagline.value,
                    child: Text(
                      'Know when to stop.',
                      style: text.titleMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades a child in while sliding it up into place.
class _Rise extends StatelessWidget {
  const _Rise({required this.t, required this.child});

  final double t;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: t.clamp(0.0, 1.0),
    child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
  );
}

class _SweepRingPainter extends CustomPainter {
  _SweepRingPainter(this.progress);

  final double progress;

  static const _green = Color(0xFF2E9E6A);
  static const _amber = Color(0xFFE0A100);
  static const _red = Color(0xFFD9452B);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - stroke / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      0,
      2 * pi,
      false,
      paint..color = Colors.white.withValues(alpha: 0.12),
    );
    if (progress <= 0) return;

    // The track's translucent color would also fade the gradient; reset it.
    paint
      ..color = Colors.white
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: 2 * pi,
        colors: [_green, _green, _amber, _red],
        stops: [0, 0.5, 0.8, 1],
        // Start slightly early so the rounded start cap is green, not red.
        transform: GradientRotation(-pi / 2 - 0.12),
      ).createShader(rect);
    canvas.drawArc(rect, -pi / 2, 2 * pi * progress, false, paint);
  }

  @override
  bool shouldRepaint(_SweepRingPainter old) => old.progress != progress;
}
