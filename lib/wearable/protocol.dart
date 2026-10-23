import 'dart:typed_data';

/// BLE identifiers advertised by the fatigue sensor firmware
/// (fatigue_sensor.ino in the embedded repo). Keep these in sync with the
/// #defines in the sketch.
class WearableProtocol {
  static const deviceName = 'Team9-Fatigue-Sensor';
  static const serviceUuid = '7fc2f476-4996-49df-b915-54e84d61fedb';
  static const imuCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const emgCharUuid = '53e27fb3-6de1-4f27-8303-d663c79b818b';
  static const repCharUuid = '65719722-b91f-43b3-adbc-7c455a80c50c';
  static const imuRateHz = 50;
  static const imuPacketLength = 16;
  static const emgSnapshotHz = 10;
  static const emgPacketLength = 14;
  static const repPacketLength = 8;
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

  /// Angular velocity in deg/s, with the gyro's bias removed.
  final double gx, gy, gz;

  /// Decodes the 16-byte little-endian packet:
  ///   [0..3]   uint32 timestamp (ms)
  ///   [4..9]   int16  ax, ay, az (milli-g)
  ///   [10..15] int16  gx, gy, gz (0.1 deg/s)
  /// Returns null if the packet is too short.
  static ImuSample? fromPacket(List<int> bytes) {
    if (bytes.length < WearableProtocol.imuPacketLength) return null;
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

/// A summary of the raw MyoWare EMG signal over one short window. The
/// firmware samples at 2 kHz and sends one of these every 100 ms. Voltages
/// are as measured at the ESP32's ADC pin.
class EmgSnapshot {
  const EmgSnapshot({
    required this.timestampMs,
    required this.sampleCount,
    required this.meanMv,
    required this.rmsMv,
    required this.minMv,
    required this.maxMv,
  });

  /// Milliseconds since the ESP32 booted, at the end of the window.
  final int timestampMs;

  /// Raw samples in the window (about 200).
  final int sampleCount;

  /// DC level the raw signal sits on, in mV.
  final int meanMv;

  /// RMS of the signal around [meanMv], in mV. Rises when the muscle
  /// contracts.
  final int rmsMv;

  /// Lowest and highest raw sample in the window, in mV.
  final int minMv, maxMv;

  /// Decodes the 14-byte little-endian packet:
  ///   [0..3]   uint32 timestamp (ms)
  ///   [4..5]   uint16 sample count
  ///   [6..13]  uint16 mean, rms, min, max (mV)
  /// Returns null if the packet is too short.
  static EmgSnapshot? fromPacket(List<int> bytes) {
    if (bytes.length < WearableProtocol.emgPacketLength) return null;
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    int u16(int offset) => data.getUint16(offset, Endian.little);
    return EmgSnapshot(
      timestampMs: data.getUint32(0, Endian.little),
      sampleCount: u16(4),
      meanMv: u16(6),
      rmsMv: u16(8),
      minMv: u16(10),
      maxMv: u16(12),
    );
  }
}

/// The wearable's rep counter. Sent each time it counts a curl, and read
/// once on connecting.
class RepUpdate {
  const RepUpdate({
    required this.timestampMs,
    required this.reps,
    required this.romDeg,
  });

  /// Milliseconds since the ESP32 booted.
  final int timestampMs;

  /// Reps counted since the wearable booted. A set's reps are the difference
  /// from the count when the set started.
  final int reps;

  /// How far the forearm swung on the latest rep, in degrees (0 before the
  /// first rep).
  final double romDeg;

  /// Decodes the 8-byte little-endian packet:
  ///   [0..3] uint32 timestamp (ms)
  ///   [4..5] uint16 reps since boot
  ///   [6..7] uint16 range of motion of the latest rep (0.1 deg)
  /// Returns null if the packet is too short.
  static RepUpdate? fromPacket(List<int> bytes) {
    if (bytes.length < WearableProtocol.repPacketLength) return null;
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return RepUpdate(
      timestampMs: data.getUint32(0, Endian.little),
      reps: data.getUint16(4, Endian.little),
      romDeg: data.getUint16(6, Endian.little) / 10,
    );
  }
}
