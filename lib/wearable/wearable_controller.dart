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

  /// Seconds of EMG snapshots kept for the live chart.
  static const emgWindow = 10;

  LinkStatus _status = LinkStatus.disconnected;
  List<FoundWearable> _found = const [];
  bool _scanFinished = false;
  FoundWearable? _connected;
  String? _error;
  int _sampleRate = 0;
  ImuSample? _latest;
  bool _hasImu = false;
  bool _hasEmg = false;
  final List<EmgSnapshot> _emgHistory = [];

  final _samples = StreamController<ImuSample>.broadcast();
  final _emg = StreamController<EmgSnapshot>.broadcast();
  final _fatigue = StreamController<FatigueEstimate>.broadcast();
  final _demo = DemoWearable();
  final _subs = <StreamSubscription<dynamic>>[];
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _rateTimer;
  int _packetsThisSecond = 0;
  bool _userDisconnect = false;

  LinkStatus get status => _status;
  List<FoundWearable> get found => _found;

  /// True once a scan has ended, so the UI can say "nothing found".
  bool get scanFinished => _scanFinished;
  FoundWearable? get connected => _connected;
  bool get isConnected => _status == LinkStatus.connected;
  bool get isDemo => isConnected && _connected?.device == null;
  String? get error => _error;

  /// Packets received in the last second.
  int get sampleRate => _sampleRate;
  ImuSample? get latest => _latest;

  /// Which sensors the connected wearable streams. The IMU and EMG run as
  /// separate sketches for now, so a real device may have only one.
  bool get hasImu => _hasImu;
  bool get hasEmg => _hasEmg;

  /// EMG snapshots from the last [emgWindow] seconds, oldest first.
  List<EmgSnapshot> get emgHistory => _emgHistory;
  EmgSnapshot? get latestEmg => _emgHistory.lastOrNull;

  Stream<ImuSample> get samples => _samples.stream;
  Stream<EmgSnapshot> get emg => _emg.stream;
  Stream<FatigueEstimate> get fatigue => _fatigue.stream;

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
        _found = [
          for (final r in results)
            FoundWearable(
              id: r.device.remoteId.str,
              name: r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : (r.device.platformName.isNotEmpty
                        ? r.device.platformName
                        : WearableProtocol.deviceName),
              rssi: r.rssi,
              device: r.device,
            ),
        ]..sort((a, b) => b.rssi.compareTo(a.rssi));
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
      // The 16-byte packet fits the default MTU, so no MTU request.
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
      final imuChar = chars.where((c) => c.uuid == _imuCharGuid).firstOrNull;
      final emgChar = chars.where((c) => c.uuid == _emgCharGuid).firstOrNull;
      if (imuChar == null && emgChar == null) {
        throw 'This device is not running the Team 9 firmware.';
      }

      if (imuChar != null) {
        await _subscribe(device, imuChar, (bytes) {
          final sample = ImuSample.fromPacket(bytes);
          if (sample != null) _onSample(sample);
        });
      }
      if (emgChar != null) {
        await _subscribe(device, emgChar, (bytes) {
          final snapshot = EmgSnapshot.fromPacket(bytes);
          if (snapshot != null) _onEmg(snapshot);
        });
      }
      _hasImu = imuChar != null;
      _hasEmg = emgChar != null;

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
      ..add(_demo.fatigue.listen(_fatigue.add));
    _demo.start();
    _hasImu = true;
    _hasEmg = true;
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
    _packetsThisSecond++;
    _samples.add(sample);
  }

  void _onEmg(EmgSnapshot snapshot) {
    _packetsThisSecond++;
    _emgHistory.add(snapshot);
    const maxSnapshots = emgWindow * WearableProtocol.emgSnapshotHz;
    if (_emgHistory.length > maxSnapshots) _emgHistory.removeAt(0);
    _emg.add(snapshot);
  }

  void _startRateTimer() {
    _rateTimer?.cancel();
    _packetsThisSecond = 0;
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sampleRate = _packetsThisSecond;
      _packetsThisSecond = 0;
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
    _hasImu = false;
    _hasEmg = false;
    _emgHistory.clear();
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
    _fatigue.close();
    super.dispose();
  }
}
