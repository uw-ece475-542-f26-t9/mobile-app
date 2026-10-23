import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../wearable/protocol.dart';
import '../wearable/wearable_controller.dart';
import 'history_store.dart';

/// Runs a set: counts reps from the wearable's rep counter, and keeps the
/// history.
class WorkoutController extends ChangeNotifier {
  WorkoutController(this.wearable, {HistoryStore? store})
    : _store = store ?? HistoryStore() {
    _subs
      ..add(wearable.samples.listen(_onSample))
      ..add(wearable.reps.listen(_onReps));
    wearable.addListener(_onWearableChanged);
    _loadHistory();
  }

  /// Seconds of arm motion kept for the live chart.
  static const motionWindow = 4;

  final WearableController wearable;
  final HistoryStore _store;
  final _subs = <StreamSubscription<dynamic>>[];

  bool _active = false;
  DateTime? _startedAt;
  Timer? _clock;
  int _repsAtStart = 0;
  int _reps = 0;
  double? _lastRomDeg;
  List<WorkoutSet> _history = const [];
  final List<double> _motion = [];
  int _sinceRedraw = 0;

  bool get active => _active;
  int get reps => _reps;
  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  /// How far the forearm swung on the set's latest rep, in degrees.
  double? get lastRomDeg => _lastRomDeg;

  /// How fast the forearm is turning (deg/s), oldest first.
  List<double> get motion => _motion;

  /// Newest first.
  List<WorkoutSet> get history => _history;

  void startSet() {
    if (_active || !wearable.isConnected) return;
    _active = true;
    _startedAt = DateTime.now();
    // The wearable counts reps since it booted, so this set's reps are the
    // ones after this count.
    _repsAtStart = wearable.lastRepUpdate?.reps ?? 0;
    _reps = 0;
    _lastRomDeg = null;
    _motion.clear();
    wearable.setActive(true);
    _clock = Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );
    notifyListeners();
  }

  Future<void> endSet() async {
    if (!_active) return;
    final set = WorkoutSet(
      startedAt: _startedAt!,
      duration: elapsed,
      reps: _reps,
    );
    _stop();
    if (set.reps > 0) {
      _history = [set, ..._history];
      await _store.save(_history);
    }
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history = const [];
    await _store.save(_history);
    notifyListeners();
  }

  void _stop() {
    _active = false;
    _startedAt = null;
    _clock?.cancel();
    _clock = null;
    wearable.setActive(false);
  }

  void _onSample(ImuSample s) {
    if (!_active) return;
    _motion.add(sqrt(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz));
    const maxPoints = motionWindow * WearableProtocol.imuRateHz;
    if (_motion.length > maxPoints) _motion.removeAt(0);
    // Redraw at ~10 fps rather than on every 50 Hz packet.
    if (++_sinceRedraw >= 5) {
      _sinceRedraw = 0;
      notifyListeners();
    }
  }

  void _onReps(RepUpdate update) {
    if (!_active) return;
    _reps = max(0, update.reps - _repsAtStart);
    _lastRomDeg = update.romDeg;
    notifyListeners();
  }

  void _onWearableChanged() {
    // Losing the wearable mid-set ends the set so the reps aren't lost.
    if (_active && !wearable.isConnected) endSet();
  }

  Future<void> _loadHistory() async {
    _history = await _store.load();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    wearable.removeListener(_onWearableChanged);
    _clock?.cancel();
    super.dispose();
  }
}
