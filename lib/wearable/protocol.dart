import 'dart:typed_data';

/// BLE identifiers advertised by the ESP32 firmware (esp32_imu_ble.ino).
/// Keep these in sync with the #defines in the sketch.
class WearableProtocol {
  static const deviceName = 'ESP32-IMU';
  static const serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const imuCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const sampleRateHz = 50;
  static const packetLength = 16;
}

/// One IMU reading from the forearm sensor.
class ImuSample {
  const ImuSample({
    required this.timestampMs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  /// Milliseconds since the ESP32 booted.
  final int timestampMs;

  /// Acceleration in g.
  final double ax, ay, az;

  /// Angular velocity in deg/s.
  final double gx, gy, gz;

  /// Decodes the 16-byte little-endian packet:
  ///   [0..3]   uint32 timestamp (ms)
  ///   [4..9]   int16  ax, ay, az (milli-g)
  ///   [10..15] int16  gx, gy, gz (0.1 deg/s)
  /// Returns null if the packet is too short.
  static ImuSample? fromPacket(List<int> bytes) {
    if (bytes.length < WearableProtocol.packetLength) return null;
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    double milliG(int offset) => data.getInt16(offset, Endian.little) / 1000;
    double deciDeg(int offset) => data.getInt16(offset, Endian.little) / 10;
    return ImuSample(
      timestampMs: data.getUint32(0, Endian.little),
      ax: milliG(4),
      ay: milliG(6),
      az: milliG(8),
      gx: deciDeg(10),
      gy: deciDeg(12),
      gz: deciDeg(14),
    );
  }
}

/// Output of the on-board fatigue model. The current firmware only streams
/// IMU data, so for now this comes from the demo wearable only.
class FatigueEstimate {
  const FatigueEstimate({required this.fatigue, required this.repsLeft});

  /// 0 = fresh, 1 = at failure.
  final double fatigue;

  /// Safe reps remaining in the current set.
  final int repsLeft;
}
