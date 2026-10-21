import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../wearable/protocol.dart';
import '../wearable/wearable_controller.dart';
import 'history_store.dart';
import 'rep_counter.dart';

/// How close the lifter is to the end of the set.
enum SetAdvice { keepGoing, almostDone, stop }

/// Runs a set: counts reps, tracks fatigue, and keeps the history.
class WorkoutController extends ChangeNotifier {
  WorkoutController(this.wearable, {HistoryStore? store})
    : _store = store ?? HistoryStore() {
    _subs
      ..add(wearable.samples.listen(_onSample))
      ..add(wearable.fatigue.listen(_onFatigue));
    wearable.addListener(_onWearableChanged);
    _loadHistory();
  }

  /// Seconds of arm motion kept for the live chart.
  static const motionWindow = 4;

  final WearableController wearable;
  final HistoryStore _store;
  final _subs = <StreamSubscription<dynamic>>[];
  final _counter = RepCounter();

  bool _active = false;
  DateTime? _startedAt;
  Timer? _clock;
  FatigueEstimate? _fatigue;
  double? _peakFatigue;
  List<WorkoutSet> _history = const [];
  final List<double> _motion = [];
  int _sinceRedraw = 0;

  bool get active => _active;
  int get reps => _counter.reps;
  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);
  FatigueEstimate? get fatigue => _fatigue;
  List<double> get motion => _motion;

  /// Newest first.
  List<WorkoutSet> get history => _history;

  SetAdvice get advice {
    final left = _fatigue?.repsLeft;
    if (left == null || left > 2) return SetAdvice.keepGoing;
    if (left > 0) return SetAdvice.almostDone;
    return SetAdvice.stop;
  }

  void startSet() {
    if (_active || !wearable.isConnected) return;
    _active = true;
    _startedAt = DateTime.now();
    _counter.reset();
    _fatigue = null;
    _peakFatigue = null;
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
      reps: _counter.reps,
      peakFatigue: _peakFatigue,
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
    final before = _counter.reps;
    final v = _counter.add(s);
    _motion.add(v);
    const maxPoints = motionWindow * WearableProtocol.sampleRateHz;
    if (_motion.length > maxPoints) _motion.removeAt(0);
    // Redraw at ~10 fps rather than on every 50 Hz packet.
    if (_counter.reps != before || ++_sinceRedraw >= 5) {
      _sinceRedraw = 0;
      notifyListeners();
    }
  }

  void _onFatigue(FatigueEstimate f) {
    if (!_active) return;
    final before = advice;
    _fatigue = f;
    _peakFatigue = max(_peakFatigue ?? 0, f.fatigue);
    if (advice != before && advice != SetAdvice.keepGoing) {
      HapticFeedback.heavyImpact();
    }
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
