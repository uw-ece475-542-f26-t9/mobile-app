import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'demo_wearable.dart';
import 'protocol.dart';

enum LinkStatus { disconnected, scanning, connecting, connected }

/// A wearable seen during a scan.
class FoundWearable {
  const FoundWearable({
    required this.id,
    required this.name,
    required this.rssi,
    this.device,
  });

  /// The wearable in a scan result, or null if the device doesn't advertise
  /// our service.
  ///
  /// The scan filter alone isn't enough on Linux: BlueZ merges it with other
  /// apps' scans (e.g. the desktop's Bluetooth settings), and
  /// flutter_blue_plus passes on every device that turns up. Web results
  /// carry no UUIDs, but Chrome's device picker has already filtered them.
  static FoundWearable? fromScanResult(ScanResult r) {
    final ours = r.advertisementData.serviceUuids.contains(
      WearableController._serviceGuid,
    );
    if (!kIsWeb && !ours) return null;
    final name = r.advertisementData.advName.isNotEmpty
        ? r.advertisementData.advName
        : r.device.platformName;
    return FoundWearable(
      id: r.device.remoteId.str,
      // Never fill in our firmware's name, or anything that slips past the
      // filter would look like our hardware.
      name: name.isNotEmpty ? name : unnamed,
      rssi: r.rssi,
      device: r.device,
    );
  }

  /// Shown for a device that doesn't advertise a name.
  static const unnamed = 'Unnamed device';

  final String id;
  final String name;
  final int rssi;

  /// Null for the demo wearable.
  final BluetoothDevice? device;
}

/// Owns the link to the wearable (real ESP32 over BLE, or the demo) and
/// republishes its data as plain streams the rest of the app listens to.
class WearableController extends ChangeNotifier {
  static final _serviceGuid = Guid(WearableProtocol.serviceUuid);
  static final _imuCharGuid = Guid(WearableProtocol.imuCharUuid);
  static final _emgCharGuid = Guid(WearableProtocol.emgCharUuid);
  static final _repCharGuid = Guid(WearableProtocol.repCharUuid);

  /// Seconds of EMG snapshots kept for the live chart.
  static const emgWindow = 10;

  LinkStatus _status = LinkStatus.disconnected;
  List<FoundWearable> _found = const [];
  bool _scanFinished = false;
  FoundWearable? _connected;
  String? _error;
  int _sampleRate = 0;
  ImuSample? _latest;
  final List<EmgSnapshot> _emgHistory = [];
  RepUpdate? _lastRepUpdate;

  final _samples = StreamController<ImuSample>.broadcast();
  final _emg = StreamController<EmgSnapshot>.broadcast();
  final _reps = StreamController<RepUpdate>.broadcast();
  final _demo = DemoWearable();
  final _subs = <StreamSubscription<dynamic>>[];
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _rateTimer;
  int _samplesThisSecond = 0;
  bool _userDisconnect = false;

  LinkStatus get status => _status;
  List<FoundWearable> get found => _found;

  /// True once a scan has ended, so the UI can say "nothing found".
  bool get scanFinished => _scanFinished;
  FoundWearable? get connected => _connected;
  bool get isConnected => _status == LinkStatus.connected;
  bool get isDemo => isConnected && _connected?.device == null;
  String? get error => _error;

  /// IMU samples received in the last second.
  int get sampleRate => _sampleRate;
  ImuSample? get latest => _latest;

  /// EMG snapshots from the last [emgWindow] seconds, oldest first.
  List<EmgSnapshot> get emgHistory => _emgHistory;
  EmgSnapshot? get latestEmg => _emgHistory.lastOrNull;

  /// The wearable's rep count as of its latest update.
  RepUpdate? get lastRepUpdate => _lastRepUpdate;

  Stream<ImuSample> get samples => _samples.stream;
  Stream<EmgSnapshot> get emg => _emg.stream;
  Stream<RepUpdate> get reps => _reps.stream;

  Future<void> scan() async {
    if (_status != LinkStatus.disconnected) return;
    _error = null;
    _found = const [];
    _scanFinished = false;
    _setStatus(LinkStatus.scanning);

    try {
      if (!await FlutterBluePlus.isSupported) {
        throw 'Bluetooth LE is not available on this device.';
      }
      if (!kIsWeb) await _ensureAdapterOn();

      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        _found = results.map(FoundWearable.fromScanResult).nonNulls.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
        notifyListeners();
      });

      // Filtering on our service UUID hides every other BLE device nearby.
      await FlutterBluePlus.startScan(
        withServices: [_serviceGuid],
        webOptionalServices: [_serviceGuid],
        timeout: const Duration(seconds: 8),
      );
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } catch (e) {
      _error = _describe(e);
    }
    _scanFinished = true;
    if (_status == LinkStatus.scanning) _setStatus(LinkStatus.disconnected);
  }

  Future<void> stopScan() async {
    if (_status != LinkStatus.scanning) return;
    await FlutterBluePlus.stopScan();
  }

  Future<void> _ensureAdapterOn() async {
    if (defaultTargetPlatform == TargetPlatform.android &&
        FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        // The user declined; the check below reports it.
      }
    }
    final state = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () => BluetoothAdapterState.unknown,
        );
    if (state != BluetoothAdapterState.on) {
      throw 'Bluetooth is off. Turn it on and try again.';
    }
  }

  Future<void> connect(FoundWearable wearable) async {
    final device = wearable.device;
    if (device == null) return connectDemo();
    if (_status == LinkStatus.scanning) await stopScan();
    _error = null;
    _userDisconnect = false;
    _setStatus(LinkStatus.connecting);

    try {
      // Every packet fits the default MTU, so no MTU request.
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 12),
        mtu: null,
      );
      final services = await device.discoverServices();
      final chars = services
          .where((s) => s.uuid == _serviceGuid)
          .expand((s) => s.characteristics)
          .toList();
      BluetoothCharacteristic? find(Guid uuid) =>
          chars.where((c) => c.uuid == uuid).firstOrNull;
      final imuChar = find(_imuCharGuid);
      final emgChar = find(_emgCharGuid);
      final repChar = find(_repCharGuid);
      if (imuChar == null || emgChar == null || repChar == null) {
        throw 'This device is not running the Team 9 firmware.';
      }

      await _subscribe(device, imuChar, (bytes) {
        final sample = ImuSample.fromPacket(bytes);
        if (sample != null) _onSample(sample);
      });
      await _subscribe(device, emgChar, (bytes) {
        final snapshot = EmgSnapshot.fromPacket(bytes);
        if (snapshot != null) _onEmg(snapshot);
      });
      await _subscribe(device, repChar, (bytes) {
        final update = RepUpdate.fromPacket(bytes);
        if (update != null) _onReps(update);
      });
      // Notifications only come with new reps, so read where the count is
      // now; the value arrives through the listener above.
      await repChar.read();

      _subs.add(
        device.connectionState.listen((state) {
          if (state == BluetoothConnectionState.disconnected &&
              _status == LinkStatus.connected) {
            if (!_userDisconnect) {
              _error = 'Connection to the wearable was lost.';
            }
            _teardown();
          }
        }),
      );

      _connected = wearable;
      _startRateTimer();
      _setStatus(LinkStatus.connected);
    } catch (e) {
      _error = _describe(e);
      await device.disconnect().catchError((_) {});
      _teardown();
    }
  }

  Future<void> _subscribe(
    BluetoothDevice device,
    BluetoothCharacteristic characteristic,
    void Function(List<int> bytes) onValue,
  ) async {
    final valueSub = characteristic.onValueReceived.listen(onValue);
    device.cancelWhenDisconnected(valueSub);
    _subs.add(valueSub);
    await characteristic.setNotifyValue(true);
  }

  void connectDemo() {
    if (_status == LinkStatus.connected) return;
    _error = null;
    _subs
      ..add(_demo.samples.listen(_onSample))
      ..add(_demo.emg.listen(_onEmg))
      ..add(_demo.reps.listen(_onReps));
    _demo.start();
    _connected = const FoundWearable(
      id: 'demo',
      name: 'Demo wearable',
      rssi: -40,
    );
    _startRateTimer();
    _setStatus(LinkStatus.connected);
  }

  Future<void> disconnect() async {
    _userDisconnect = true;
    final device = _connected?.device;
    if (device != null) await device.disconnect().catchError((_) {});
    _teardown();
  }

  /// Tells the wearable a set started or ended. The demo uses this to begin
  /// curling; the real firmware has no command for it yet.
  void setActive(bool active) => _demo.setActive(active);

  void _onSample(ImuSample sample) {
    _latest = sample;
    _samplesThisSecond++;
    _samples.add(sample);
  }

  void _onEmg(EmgSnapshot snapshot) {
    _emgHistory.add(snapshot);
    const maxSnapshots = emgWindow * WearableProtocol.emgSnapshotHz;
    if (_emgHistory.length > maxSnapshots) _emgHistory.removeAt(0);
    _emg.add(snapshot);
  }

  void _onReps(RepUpdate update) {
    _lastRepUpdate = update;
    _reps.add(update);
    notifyListeners();
  }

  void _startRateTimer() {
    _rateTimer?.cancel();
    _samplesThisSecond = 0;
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sampleRate = _samplesThisSecond;
      _samplesThisSecond = 0;
      notifyListeners();
    });
  }

  void _teardown() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _demo.stop();
    _rateTimer?.cancel();
    _rateTimer = null;
    _sampleRate = 0;
    _latest = null;
    _emgHistory.clear();
    _lastRepUpdate = null;
    _connected = null;
    _setStatus(LinkStatus.disconnected);
  }

  void _setStatus(LinkStatus status) {
    _status = status;
    notifyListeners();
  }

  String _describe(Object e) {
    if (e is String) return e;
    if (e is FlutterBluePlusException) {
      return e.description ?? 'Bluetooth error (${e.function}).';
    }
    if (e is TimeoutException) return 'The wearable did not respond in time.';
    return e.toString();
  }

  @override
  void dispose() {
    _teardown();
    _scanSub?.cancel();
    _demo.dispose();
    _samples.close();
    _emg.close();
    _reps.close();
    super.dispose();
  }
}
