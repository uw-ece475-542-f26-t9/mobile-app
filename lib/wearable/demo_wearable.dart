import 'dart:async';
import 'dart:math';

import 'protocol.dart';

/// A simulated wearable so the app can be designed and demoed without the
/// ESP32. It idles until a set starts, then streams bicep-curl motion that
/// slows down as simulated fatigue builds, plus a fatigue estimate like the
/// on-board model will eventually send.
class DemoWearable {
  static const _failureReps = 12;
  static const _safeReps = 10;

  final _samples = StreamController<ImuSample>.broadcast();
  final _fatigue = StreamController<FatigueEstimate>.broadcast();
  final _random = Random();

  Timer? _timer;
  int _clockMs = 0;
  bool _active = false;
  double _phase = 0; // completed curl cycles, fractional

  Stream<ImuSample> get samples => _samples.stream;
  Stream<FatigueEstimate> get fatigue => _fatigue.stream;

  void start() {
    _timer ??= Timer.periodic(
      const Duration(milliseconds: 1000 ~/ WearableProtocol.sampleRateHz),
      (_) => _tick(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _active = false;
  }

  void setActive(bool active) {
    _active = active;
    _phase = 0;
  }

  void _tick() {
    const dt = 1 / WearableProtocol.sampleRateHz;
    _clockMs += 1000 ~/ WearableProtocol.sampleRateHz;
    double noise(double scale) => (_random.nextDouble() - 0.5) * scale;

    var gx = noise(4.0), gy = noise(4.0), gz = noise(4.0);
    var ax = noise(0.02), ay = noise(0.02), az = 1.0 + noise(0.02);

    if (_active) {
      final progress = min(_phase / _failureReps, 1.0);
      // Reps get slower and weaker as fatigue builds.
      final periodS = 2.2 + 1.8 * progress * progress;
      final amplitude = 140 - 60 * progress;
      _phase += dt / periodS;
      final angle = 2 * pi * _phase;
      gx = amplitude * sin(angle) + noise(8);
      gy += 15 * progress * sin(angle * 2); // late-set wobble
      ax += 0.4 * sin(angle);
      ay += 0.3 * cos(angle);

      if (_clockMs % 100 == 0) {
        // The rep counter registers a curl on the way down (~3/4 cycle).
        final reps = (_phase + 0.25).floor();
        _fatigue.add(
          FatigueEstimate(
            fatigue: min(_phase / _failureReps, 1.0),
            repsLeft: max(0, _safeReps - reps),
          ),
        );
      }
    }

    _samples.add(
      ImuSample(
        timestampMs: _clockMs,
        ax: ax,
        ay: ay,
        az: az,
        gx: gx,
        gy: gy,
        gz: gz,
      ),
    );
  }

  void dispose() {
    stop();
    _samples.close();
    _fatigue.close();
  }
}
