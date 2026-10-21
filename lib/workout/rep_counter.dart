import '../wearable/protocol.dart';

/// Counts bicep curls from the forearm gyroscope.
///
/// A curl swings the forearm one way and back, so the gyro axis the elbow
/// rotates around goes strongly positive, then strongly negative. We track
/// whichever axis is moving the most (so it works however the IMU is
/// mounted) and count a rep each time that axis completes a swing past
/// +threshold and back past -threshold.
class RepCounter {
  RepCounter({this.threshold = 30});

  /// deg/s an axis must exceed for a swing to count.
  final double threshold;

  final _energy = [0.0, 0.0, 0.0];
  int _axis = 0;
  bool _swungOut = false;
  int reps = 0;

  /// Adds a sample and returns the angular velocity on the tracked axis.
  double add(ImuSample s) {
    final values = [s.gx, s.gy, s.gz];
    for (var i = 0; i < 3; i++) {
      _energy[i] = 0.97 * _energy[i] + 0.03 * values[i] * values[i];
    }
    // Only switch axes on a clear winner, so noise can't flip it mid-rep.
    for (var i = 0; i < 3; i++) {
      if (_energy[i] > 2 * _energy[_axis]) {
        _axis = i;
        _swungOut = false;
      }
    }

    final v = values[_axis];
    if (!_swungOut && v > threshold) {
      _swungOut = true;
    } else if (_swungOut && v < -threshold) {
      _swungOut = false;
      reps++;
    }
    return v;
  }

  void reset() {
    reps = 0;
    _swungOut = false;
  }
}
