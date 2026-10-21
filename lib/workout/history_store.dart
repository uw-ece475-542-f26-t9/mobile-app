import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A finished set of bicep curls.
class WorkoutSet {
  const WorkoutSet({
    required this.startedAt,
    required this.duration,
    required this.reps,
    this.peakFatigue,
  });

  final DateTime startedAt;
  final Duration duration;
  final int reps;

  /// Highest fatigue the model reported, if it was streaming.
  final double? peakFatigue;

  Map<String, Object?> toJson() => {
    'startedAt': startedAt.toIso8601String(),
    'durationMs': duration.inMilliseconds,
    'reps': reps,
    'peakFatigue': peakFatigue,
  };

  factory WorkoutSet.fromJson(Map<String, Object?> json) => WorkoutSet(
    startedAt: DateTime.parse(json['startedAt'] as String),
    duration: Duration(milliseconds: json['durationMs'] as int),
    reps: json['reps'] as int,
    peakFatigue: (json['peakFatigue'] as num?)?.toDouble(),
  );
}

/// Saves finished sets on the phone.
class HistoryStore {
  static const _key = 'workout_sets_v1';

  Future<List<WorkoutSet>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    return [
      for (final s in raw)
        WorkoutSet.fromJson(jsonDecode(s) as Map<String, Object?>),
    ];
  }

  Future<void> save(List<WorkoutSet> sets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [
      for (final s in sets) jsonEncode(s.toJson()),
    ]);
  }
}
