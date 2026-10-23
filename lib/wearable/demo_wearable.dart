import 'dart:async';
import 'dart:math';

import 'protocol.dart';

/// A simulated wearable so the app can be designed and demoed without the
/// ESP32. It idles until a set starts, then streams bicep-curl motion that
/// slows down and shortens as simulated fatigue builds, EMG snapshots that
/// rise with each curl, and rep updates like the firmware's rep counter.
class DemoWearable {
  static const _failureReps = 12;

  final _samples = StreamController<ImuSample>.broadcast();
  final _emg = StreamController<EmgSnapshot>.broadcast();
  final _reps = StreamController<RepUpdate>.broadcast();
  final _random = Random();

  Timer? _timer;
  int _clockMs = 0;
  bool _active = false;
  double _phase = 0; // completed curl cycles, fractional
  int _repCount = 0; // since "boot", like the firmware
  int _repsThisSet = 0;

  Stream<ImuSample> get samples => _samples.stream;
  Stream<EmgSnapshot> get emg => _emg.stream;
  Stream<RepUpdate> get reps => _reps.stream;

  void start() {
    _timer ??= Timer.periodic(
      const Duration(milliseconds: 1000 ~/ WearableProtocol.imuRateHz),
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
    _repsThisSet = 0;
  }

  void _tick() {
    const dt = 1 / WearableProtocol.imuRateHz;
    _clockMs += 1000 ~/ WearableProtocol.imuRateHz;
    double noise(double scale) => (_random.nextDouble() - 0.5) * scale;

    var gx = noise(4.0), gy = noise(4.0), gz = noise(4.0);
    var ax = noise(0.02), ay = noise(0.02), az = 1.0 + noise(0.02);
    var effort = 0.0; // biceps activation, 0 = relaxed

    if (_active) {
      final progress = min(_phase / _failureReps, 1.0);
      // Reps get slower and shorter as fatigue builds.
      final periodS = 2.2 + 1.8 * progress * progress;
      final romDeg = 130 - 50 * progress;
      _phase += dt / periodS;
      final angle = 2 * pi * _phase;
      // The elbow angle goes 0 -> romDeg -> 0 each cycle; gx is its rate.
      gx = romDeg * pi / periodS * sin(angle) + noise(8);
      gy += 15 * progress * sin(angle * 2); // late-set wobble
      ax += 0.4 * sin(angle);
      ay += 0.3 * cos(angle);
      // Holding the weight takes some effort, lifting it the most, and a
      // tiring muscle recruits more fibres for the same curl.
      effort = (0.45 + 0.35 * sin(angle)) * (1 + 0.5 * progress);

      // Like the firmware, count each curl part way down (~3/4 cycle).
      if ((_phase + 0.25).floor() > _repsThisSet) {
        _repsThisSet++;
        _repCount++;
        _reps.add(
          RepUpdate(timestampMs: _clockMs, reps: _repCount, romDeg: romDeg),
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
    _reps.close();
  }
}
