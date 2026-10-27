import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import 'rep_features.dart';

/// Where the trained model is bundled. tools/train_fatigue_model.py writes
/// this file.
const fatigueModelAsset = 'assets/models/fatigue_model.json';

/// Reps to stop short of failure: the goal is ending the set 2–3 reps
/// before failure, not at it.
const safetyMarginReps = 2;

/// The model's view of the set after the latest rep.
class FatigueEstimate {
  const FatigueEstimate({
    required this.fatigue,
    required this.repsToFailure,
    required this.source,
  });

  /// 0 = fresh, 1 = at failure.
  final double fatigue;

  /// Predicted reps left before failure (reps in reserve).
  final double repsToFailure;

  /// Which model produced this, shown in the UI.
  final String source;

  /// Reps left before the safe stopping point.
  int get safeRepsLeft => max(0, repsToFailure.floor() - safetyMarginReps);
}

/// Predicts fatigue from the reps so far in a set.
abstract class FatigueModel {
  String get name;

  /// Null until there are enough reps to say anything.
  FatigueEstimate? predict(List<RepFeatures> reps);
}

/// Velocity-loss baseline, used until a trained model is bundled.
///
/// Reps slow down as the muscle tires. This tracks how much slower the
/// latest rep is than the set's first ones and extrapolates the trend to
/// [failureLoss]. The 50% failure point is a rough figure from the
/// velocity-based-training literature, not something we've calibrated.
class VelocityLossModel implements FatigueModel {
  const VelocityLossModel({this.failureLoss = 0.5});

  final double failureLoss;

  @override
  String get name => 'Velocity baseline';

  @override
  FatigueEstimate? predict(List<RepFeatures> reps) {
    if (reps.length < 3) return null;
    final recent = reps.sublist(reps.length - 2);
    final loss = max(
      0.0,
      recent.map((r) => r.velocityLoss).reduce((a, b) => a + b) / 2,
    );

    // Slope of velocity loss per rep, by least squares over the set.
    final n = reps.length;
    final xs = [for (final r in reps) r.repIndex.toDouble()];
    final ys = [for (final r in reps) r.velocityLoss];
    final mx = xs.reduce((a, b) => a + b) / n;
    final my = ys.reduce((a, b) => a + b) / n;
    var num = 0.0, den = 0.0;
    for (var i = 0; i < n; i++) {
      num += (xs[i] - mx) * (ys[i] - my);
      den += (xs[i] - mx) * (xs[i] - mx);
    }
    final slope = den == 0 ? 0.0 : num / den;
    // Not slowing down yet: plenty left, but we can't say how many.
    final toFailure = slope <= 0.005
        ? 20.0
        : ((failureLoss - loss) / slope).clamp(0.0, 20.0);

    return FatigueEstimate(
      fatigue: (loss / failureLoss).clamp(0.0, 1.0),
      repsToFailure: toFailure,
      source: name,
    );
  }
}

/// A linear model trained by tools/train_fatigue_model.py that predicts
/// reps to failure from a rep's [RepFeatures.modelInputs].
class LinearRirModel implements FatigueModel {
  LinearRirModel({
    required this.name,
    required this.features,
    required this.mean,
    required this.std,
    required this.coef,
    required this.intercept,
  });

  factory LinearRirModel.fromJson(Map<String, Object?> json) {
    List<double> nums(String key) => [
      for (final v in json[key] as List) (v as num).toDouble(),
    ];
    final model = LinearRirModel(
      name: json['name'] as String? ?? 'Trained model',
      features: [for (final f in json['features'] as List) f as String],
      mean: nums('mean'),
      std: nums('std'),
      coef: nums('coef'),
      intercept: (json['intercept'] as num).toDouble(),
    );
    final n = model.features.length;
    if (model.mean.length != n ||
        model.std.length != n ||
        model.coef.length != n) {
      throw const FormatException('features, mean, std and coef must match');
    }
    return model;
  }

  @override
  final String name;
  final List<String> features;
  final List<double> mean, std, coef;
  final double intercept;

  @override
  FatigueEstimate? predict(List<RepFeatures> reps) {
    // The relative features need a baseline to compare against.
    if (reps.length < 2) return null;
    final inputs = reps.last.modelInputs;
    var rir = intercept;
    for (var i = 0; i < features.length; i++) {
      final x = inputs[features[i]];
      if (x == null) return null;
      rir += coef[i] * (x - mean[i]) / (std[i] == 0 ? 1 : std[i]);
    }
    rir = max(0, rir);
    final done = reps.length;
    return FatigueEstimate(
      fatigue: done / (done + rir),
      repsToFailure: rir,
      source: name,
    );
  }
}

/// The bundled trained model, or the velocity baseline if there isn't one.
Future<FatigueModel> loadFatigueModel({AssetBundle? bundle}) async {
  try {
    final raw = await (bundle ?? rootBundle).loadString(fatigueModelAsset);
    return LinearRirModel.fromJson(jsonDecode(raw) as Map<String, Object?>);
  } catch (_) {
    return const VelocityLossModel();
  }
}
