import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../fatigue/fatigue_model.dart';
import '../fatigue/file_export.dart';
import '../fatigue/rep_features.dart';
import '../fatigue/training_data.dart';
import '../wearable/protocol.dart';
import '../wearable/wearable_controller.dart';
import 'history_store.dart';

/// How close the lifter is to the safe end of the set.
enum SetAdvice { keepGoing, almostDone, stop }

/// Runs a set: counts reps from the wearable's rep counter, estimates
/// fatigue after every rep, optionally records the set for model training,
/// and keeps the history.
class WorkoutController extends ChangeNotifier {
  WorkoutController(
    this.wearable, {
    HistoryStore? store,
    TrainingStore? training,
    FatigueModel? model,
  }) : _store = store ?? HistoryStore(),
       _training = training ?? TrainingStore(),
       _model = model ?? const VelocityLossModel() {
    _subs
      ..add(wearable.samples.listen(_onSample))
      ..add(wearable.emg.listen(_onEmg))
      ..add(wearable.reps.listen(_onReps));
    wearable.addListener(_onWearableChanged);
    _loadHistory();
    if (model == null) _loadModel();
  }

  /// Seconds of arm motion kept for the live chart.
  static const motionWindow = 4;

  final WearableController wearable;
  final HistoryStore _store;
  final TrainingStore _training;
  final _subs = <StreamSubscription<dynamic>>[];

  FatigueModel _model;
  bool _active = false;
  DateTime? _startedAt;
  Timer? _clock;
  int _repsAtStart = 0;
  int _reps = 0;
  double? _lastRomDeg;
  List<WorkoutSet> _history = const [];
  final List<double> _motion = [];
  int _sinceRedraw = 0;

  RepFeatureExtractor _extractor = RepFeatureExtractor();
  FatigueEstimate? _fatigue;
  double? _peakFatigue;

  bool _recordForTraining = false;
  SetRecording? _recording;
  SetRecording? _pendingRecording;
  int _trainingSetCount = 0;
  String? _lastSubject;

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

  /// The model's latest estimate, or null early in the set.
  FatigueEstimate? get fatigue => _fatigue;
  String get modelName => _model.name;

  /// Features of each rep so far in the set.
  List<RepFeatures> get repFeatures => _extractor.reps;

  SetAdvice get advice {
    final f = _fatigue;
    if (f == null || f.safeRepsLeft > 1) return SetAdvice.keepGoing;
    if (f.safeRepsLeft > 0) return SetAdvice.almostDone;
    return SetAdvice.stop;
  }

  /// Whether the next set is recorded for training.
  bool get recordForTraining => _recordForTraining;
  set recordForTraining(bool value) {
    _recordForTraining = value;
    notifyListeners();
  }

  /// A finished recorded set waiting for its labels.
  SetRecording? get pendingRecording => _pendingRecording;
  int get trainingSetCount => _trainingSetCount;
  String? get lastSubject => _lastSubject;

  void startSet() {
    if (_active || !wearable.isConnected || _pendingRecording != null) return;
    _active = true;
    _startedAt = DateTime.now();
    // The wearable counts reps since it booted, so this set's reps are the
    // ones after this count.
    _repsAtStart = wearable.lastRepUpdate?.reps ?? 0;
    _reps = 0;
    _lastRomDeg = null;
    _motion.clear();
    _extractor = RepFeatureExtractor();
    _fatigue = null;
    _peakFatigue = null;
    _recording = _recordForTraining
        ? (SetRecording(
            startedAt: _startedAt!,
            deviceName: wearable.connected?.name ?? '',
          )..modelName = _model.name)
        : null;
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
      peakFatigue: _peakFatigue,
    );
    final recording = _recording;
    _stop();
    if (recording != null && recording.reps.isNotEmpty) {
      _pendingRecording = recording;
    }
    if (set.reps > 0) {
      _history = [set, ..._history];
      await _store.save(_history);
    }
    notifyListeners();
  }

  /// Saves the pending recording with its labels: keeps the features on
  /// the phone and exports the full file (with raw streams).
  Future<void> saveRecording(SetLabels labels) async {
    final recording = _pendingRecording;
    if (recording == null) return;
    _pendingRecording = null;
    await _training.add(recording.toJson(labels, includeRaw: false));
    await _training.setLastSubject(labels.subjectId);
    _lastSubject = labels.subjectId;
    _trainingSetCount++;
    notifyListeners();
    await exportJsonFile(
      recording.fileName(labels),
      jsonEncode(recording.toJson(labels)),
    );
  }

  void discardRecording() {
    _pendingRecording = null;
    notifyListeners();
  }

  /// Exports every stored training set (features and labels) as one file.
  Future<void> exportTrainingData() async {
    final sets = await _training.load();
    final t = DateTime.now();
    await exportJsonFile(
      'fatigue-training-data_${t.millisecondsSinceEpoch}.json',
      exportAllJson(sets),
    );
  }

  Future<void> clearTrainingData() async {
    await _training.clear();
    _trainingSetCount = 0;
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
    _recording = null;
    _clock?.cancel();
    _clock = null;
    wearable.setActive(false);
  }

  void _onSample(ImuSample s) {
    if (!_active) return;
    _extractor.addSample(s);
    _recording?.imu.add(s);
    _motion.add(sqrt(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz));
    const maxPoints = motionWindow * WearableProtocol.imuRateHz;
    if (_motion.length > maxPoints) _motion.removeAt(0);
    // Redraw at ~10 fps rather than on every 50 Hz packet.
    if (++_sinceRedraw >= 5) {
      _sinceRedraw = 0;
      notifyListeners();
    }
  }

  void _onEmg(EmgSnapshot e) {
    if (!_active) return;
    _extractor.addEmg(e);
    _recording?.emg.add(e);
  }

  void _onReps(RepUpdate update) {
    if (!_active) return;
    final reps = max(0, update.reps - _repsAtStart);
    _recording?.repEvents.add(update);
    _lastRomDeg = update.romDeg;
    // One feature row per new rep; the wearable may repeat a count we
    // already have (e.g. the read on connect).
    if (reps > _reps) {
      _reps = reps;
      if (_extractor.onRep(update) != null) {
        final before = advice;
        _fatigue = _model.predict(_extractor.reps);
        final recording = _recording;
        if (recording != null) {
          recording.reps
            ..clear()
            ..addAll(_extractor.reps);
          recording.predictedRepsToFailure.add(_fatigue?.repsToFailure);
        }
        if (_fatigue != null) {
          _peakFatigue = max(_peakFatigue ?? 0, _fatigue!.fatigue);
        }
        if (advice != before && advice != SetAdvice.keepGoing) {
          HapticFeedback.heavyImpact();
        }
      }
    }
    notifyListeners();
  }

  void _onWearableChanged() {
    // Losing the wearable mid-set ends the set so the reps aren't lost.
    if (_active && !wearable.isConnected) endSet();
  }

  Future<void> _loadHistory() async {
    _history = await _store.load();
    _trainingSetCount = (await _training.load()).length;
    _lastSubject = await _training.lastSubject();
    notifyListeners();
  }

  Future<void> _loadModel() async {
    _model = await loadFatigueModel();
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
