import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../wearable/protocol.dart';
import 'rep_features.dart';

/// Version tag in every exported file, so the training script can tell
/// formats apart if this one changes.
const trainingSchema = 'team9-fatigue-set/v1';

/// What the lifter tells us after a recorded set. This is the ground truth
/// the model learns from.
class SetLabels {
  const SetLabels({
    required this.subjectId,
    required this.weightKg,
    required this.reachedFailure,
    required this.repsInReserve,
    this.rpe,
    this.notes = '',
  });

  /// Anonymous ID like "S01", so sets can be grouped per person without
  /// storing names.
  final String subjectId;
  final double weightKg;

  /// True if the last rep was the last one they could do with good form.
  final bool reachedFailure;

  /// Reps they think they had left at the end (0 at failure).
  final int repsInReserve;

  /// Optional rating of perceived exertion, 1–10.
  final double? rpe;
  final String notes;

  Map<String, Object?> toJson() => {
    'subject_id': subjectId,
    'weight_kg': weightKg,
    'reached_failure': reachedFailure,
    'reps_in_reserve': repsInReserve,
    'rpe': rpe,
    'notes': notes,
  };

  factory SetLabels.fromJson(Map<String, Object?> json) => SetLabels(
    subjectId: json['subject_id'] as String,
    weightKg: (json['weight_kg'] as num).toDouble(),
    reachedFailure: json['reached_failure'] as bool,
    repsInReserve: json['reps_in_reserve'] as int,
    rpe: (json['rpe'] as num?)?.toDouble(),
    notes: json['notes'] as String? ?? '',
  );
}

/// Everything captured during one set while recording for training.
class SetRecording {
  SetRecording({required this.startedAt, required this.deviceName});

  final DateTime startedAt;
  final String deviceName;
  final List<ImuSample> imu = [];
  final List<EmgSnapshot> emg = [];
  final List<RepUpdate> repEvents = [];
  final List<RepFeatures> reps = [];

  /// The live model's predicted reps to failure after each rep (null while
  /// it had too few reps), to compare against the labels later.
  final List<double?> predictedRepsToFailure = [];
  String modelName = '';

  /// The file written for this set: features, labels and the raw streams,
  /// so features can be recomputed later without re-recording.
  Map<String, Object?> toJson(SetLabels labels, {bool includeRaw = true}) => {
    'schema': trainingSchema,
    'started_at': startedAt.toIso8601String(),
    'device': deviceName,
    'model': modelName,
    'labels': labels.toJson(),
    'reps': [
      for (var i = 0; i < reps.length; i++)
        {
          ...reps[i].toJson(),
          'predicted_reps_to_failure': predictedRepsToFailure.elementAtOrNull(
            i,
          ),
        },
    ],
    if (includeRaw)
      'raw': {
        'imu_columns': [
          't_ms',
          'ax_g',
          'ay_g',
          'az_g',
          'gx_dps',
          'gy_dps',
          'gz_dps',
        ],
        'imu': [
          for (final s in imu)
            [s.timestampMs, s.ax, s.ay, s.az, s.gx, s.gy, s.gz],
        ],
        'emg_columns': [
          't_ms',
          'samples',
          'mean_mv',
          'rms_mv',
          'min_mv',
          'max_mv',
        ],
        'emg': [
          for (final e in emg)
            [e.timestampMs, e.sampleCount, e.meanMv, e.rmsMv, e.minMv, e.maxMv],
        ],
        'rep_columns': ['t_ms', 'reps_since_boot', 'rom_deg'],
        'rep_events': [
          for (final r in repEvents) [r.timestampMs, r.reps, r.romDeg],
        ],
      },
  };

  String fileName(SetLabels labels) {
    final t = startedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
    final subject = labels.subjectId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return 'fatigue-set_${subject}_$stamp.json';
  }
}

/// Keeps recorded sets on the phone (features and labels only; the raw
/// streams are too big and are exported per set instead), plus the last
/// subject ID so it doesn't have to be retyped.
class TrainingStore {
  static const _setsKey = 'training_sets_v1';
  static const _subjectKey = 'training_subject_id';

  Future<List<Map<String, Object?>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return [
      for (final s in prefs.getStringList(_setsKey) ?? const <String>[])
        jsonDecode(s) as Map<String, Object?>,
    ];
  }

  Future<void> add(Map<String, Object?> set) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_setsKey, [
      ...prefs.getStringList(_setsKey) ?? const <String>[],
      jsonEncode(set),
    ]);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_setsKey);
  }

  Future<String?> lastSubject() async =>
      (await SharedPreferences.getInstance()).getString(_subjectKey);

  Future<void> setLastSubject(String id) async =>
      (await SharedPreferences.getInstance()).setString(_subjectKey, id);
}

/// Every stored set in one file, for the training script.
String exportAllJson(List<Map<String, Object?>> sets) =>
    const JsonEncoder.withIndent(' ').convert({
      'schema': trainingSchema,
      'exported_at': DateTime.now().toIso8601String(),
      'sets': sets,
    });
