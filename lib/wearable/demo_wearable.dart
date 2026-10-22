import 'dart:async';
import 'dart:math';

import 'protocol.dart';

/// A simulated wearable so the app can be designed and demoed without the
/// ESP32. It idles until a set starts, then streams bicep-curl motion that
/// slows down as simulated fatigue builds, EMG snapshots that rise with each
/// curl, and a fatigue estimate like the on-board model will eventually send.
class DemoWearable {
  static const _failureReps = 12;
  static const _safeReps = 10;

  final _samples = StreamController<ImuSample>.broadcast();
  final _emg = StreamController<EmgSnapshot>.broadcast();
  final _fatigue = StreamController<FatigueEstimate>.broadcast();
  final _random = Random();

  Timer? _timer;
  int _clockMs = 0;
  bool _active = false;
  double _phase = 0; // completed curl cycles, fractional

  Stream<ImuSample> get samples => _samples.stream;
  Stream<EmgSnapshot> get emg => _emg.stream;
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
    var effort = 0.0; // biceps activation, 0 = relaxed

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
      // Holding the weight takes some effort, lifting it the most, and a
      // tiring muscle recruits more fibres for the same curl.
      effort = (0.45 + 0.35 * sin(angle)) * (1 + 0.5 * progress);

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

    if (_clockMs % (1000 ~/ WearableProtocol.emgSnapshotHz) == 0) {
      // Made-up levels, not measured ones: a few mV of noise at rest, ~100+
      // mV RMS when working, on a DC level near the middle of the ADC range.
      final mean = 1650 + noise(6);
      final rms = 4 + 140 * effort * (1 + noise(0.2));
      final peak = rms * (3 + noise(0.6));
      _emg.add(
        EmgSnapshot(
          timestampMs: _clockMs,
          sampleCount: 200,
          meanMv: mean.round(),
          rmsMv: rms.round(),
          minMv: (mean - peak).round(),
          maxMv: (mean + peak).round(),
        ),
      );
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
    _emg.close();
    _fatigue.close();
  }
}
