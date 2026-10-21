import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:uw_ece475_542_t9_app/wearable/protocol.dart';
import 'package:uw_ece475_542_t9_app/workout/rep_counter.dart';

List<int> _packet(int t, List<int> values) {
  final bytes = <int>[t & 0xFF, t >> 8 & 0xFF, t >> 16 & 0xFF, t >> 24 & 0xFF];
  for (final v in values) {
    bytes
      ..add(v & 0xFF)
      ..add(v >> 8 & 0xFF);
  }
  return bytes;
}

ImuSample _gyro(double gx, {double gy = 0}) =>
    ImuSample(timestampMs: 0, ax: 0, ay: 0, az: 1, gx: gx, gy: gy, gz: 0);

void main() {
  test('decodes the firmware packet layout', () {
    // Same scaling as esp32_imu_ble.ino: milli-g and 0.1 deg/s.
    final s = ImuSample.fromPacket(
      _packet(123456, [500, -250, 1000, 900, -450, 0]),
    )!;
    expect(s.timestampMs, 123456);
    expect(s.ax, 0.5);
    expect(s.ay, -0.25);
    expect(s.az, 1.0);
    expect(s.gx, 90.0);
    expect(s.gy, -45.0);
    expect(s.gz, 0.0);
  });

  test('rejects short packets', () {
    expect(ImuSample.fromPacket(List.filled(10, 0)), isNull);
  });

  test('counts one rep per curl cycle on the dominant axis', () {
    final counter = RepCounter();
    // 5 curls at 50 Hz, 2 s each, like the firmware's fake sine data.
    for (var i = 0; i < 5 * 100; i++) {
      final t = i / 50;
      counter.add(_gyro(90 * sin(pi * t), gy: 10 * cos(3 * t)));
    }
    expect(counter.reps, 5);
  });

  test('ignores small jitter', () {
    final counter = RepCounter();
    for (var i = 0; i < 500; i++) {
      counter.add(_gyro(15 * sin(i / 3)));
    }
    expect(counter.reps, 0);
  });
}
