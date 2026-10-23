import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uw_ece475_542_t9_app/wearable/protocol.dart';
import 'package:uw_ece475_542_t9_app/wearable/wearable_controller.dart';

List<int> _packet(int t, List<int> values) {
  final bytes = <int>[t & 0xFF, t >> 8 & 0xFF, t >> 16 & 0xFF, t >> 24 & 0xFF];
  for (final v in values) {
    bytes
      ..add(v & 0xFF)
      ..add(v >> 8 & 0xFF);
  }
  return bytes;
}

ScanResult _scanResult({String name = '', List<Guid> services = const []}) =>
    ScanResult(
      device: BluetoothDevice.fromId('14:C1:9F:C7:F9:05'),
      advertisementData: AdvertisementData(
        advName: name,
        txPowerLevel: null,
        appearance: null,
        connectable: true,
        manufacturerData: const {},
        serviceData: const {},
        serviceUuids: services,
      ),
      rssi: -40,
      timeStamp: DateTime(2026),
    );

final _ourService = [Guid(WearableProtocol.serviceUuid)];

void main() {
  test('decodes the firmware packet layout', () {
    // Same scaling as fatigue_sensor.ino: milli-g and 0.1 deg/s.
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

  test('decodes the EMG snapshot packet', () {
    // Same layout as fatigue_sensor.ino: sample count, then mean, rms, min and
    // max in mV.
    final s = EmgSnapshot.fromPacket(
      _packet(123456, [200, 1650, 42, 1520, 2900]),
    )!;
    expect(s.timestampMs, 123456);
    expect(s.sampleCount, 200);
    expect(s.meanMv, 1650);
    expect(s.rmsMv, 42);
    expect(s.minMv, 1520);
    expect(s.maxMv, 2900);
  });

  test('decodes the rep counter packet', () {
    // Same layout as fatigue_sensor.ino: reps since boot, then the latest
    // rep's range of motion in 0.1 deg.
    final r = RepUpdate.fromPacket(_packet(98765, [42, 1234]))!;
    expect(r.timestampMs, 98765);
    expect(r.reps, 42);
    expect(r.romDeg, 123.4);
  });

  test('rejects short packets', () {
    expect(ImuSample.fromPacket(List.filled(10, 0)), isNull);
    expect(EmgSnapshot.fromPacket(List.filled(10, 0)), isNull);
    expect(RepUpdate.fromPacket(List.filled(6, 0)), isNull);
  });

  test('lists devices with our service under their own name', () {
    final w = FoundWearable.fromScanResult(
      _scanResult(name: 'Team9-Fatigue-Sensor', services: _ourService),
    )!;
    expect(w.name, 'Team9-Fatigue-Sensor');
    expect(w.id, '14:C1:9F:C7:F9:05');
  });

  test('never gives a nameless device our firmware name', () {
    final w = FoundWearable.fromScanResult(_scanResult(services: _ourService))!;
    expect(w.name, FoundWearable.unnamed);
    expect(w.name, isNot(WearableProtocol.deviceName));
  });

  test('drops devices without our service', () {
    expect(FoundWearable.fromScanResult(_scanResult(name: 'iPhone')), isNull);
    expect(FoundWearable.fromScanResult(_scanResult()), isNull);
  });
}
