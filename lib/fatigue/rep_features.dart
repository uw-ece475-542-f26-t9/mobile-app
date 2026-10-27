import 'dart:math';

import '../wearable/protocol.dart';

/// What one curl looked like, measured from the wearable's streams.
///
/// The absolute values depend on the person, the weight and where the
/// sensor sits, so the model mostly uses the *relative* features: each
/// rep compared with the start of the same set. Those carry over between
/// people, which is what lets a model trained on ~20 subjects work on a new
/// one.
class RepFeatures {
  const RepFeatures({
    required this.repIndex,
    required this.durationS,
    required this.romDeg,
    required this.peakGyroDps,
    required this.meanGyroDps,
    required this.emgRmsMeanMv,
    required this.emgRmsPeakMv,
    required this.velocityLoss,
    required this.durationRatio,
    required this.romRatio,
    required this.emgRatio,
    required this.emgPerVelocityRatio,
  });

  /// 1 for the set's first rep.
  final int repIndex;

  /// Time the forearm was actually moving during the rep, so a pause
  /// before the first curl or between reps doesn't count.
  final double durationS;

  /// Range of motion the wearable reported for this rep.
  final double romDeg;

  /// Fastest and average forearm rotation speed during the rep. Peak speed
  /// is our stand-in for bar velocity.
  final double peakGyroDps, meanGyroDps;

  /// Average and highest EMG RMS during the rep.
  final double emgRmsMeanMv, emgRmsPeakMv;

  /// 1 - peak speed / baseline peak speed. 0.2 means 20% slower than the
  /// first reps. Velocity loss is the standard velocity-based-training
  /// fatigue measure, and our velocity-only baseline.
  final double velocityLoss;

  /// This rep's duration, ROM and EMG level divided by the baseline's.
  final double durationRatio, romRatio, emgRatio;

  /// (EMG per unit speed) / baseline. A tiring muscle needs more
  /// activation for the same movement, so this climbs with fatigue.
  final double emgPerVelocityRatio;

  /// Inputs to the trained model, in this order. The training script
  /// (tools/train_fatigue_model.py) uses the same names.
  Map<String, double> get modelInputs => {
    'rep_index': repIndex.toDouble(),
    'velocity_loss': velocityLoss,
    'duration_ratio': durationRatio,
    'rom_ratio': romRatio,
    'emg_ratio': emgRatio,
    'emg_per_velocity_ratio': emgPerVelocityRatio,
  };

  Map<String, Object> toJson() => {
    'rep_index': repIndex,
    'duration_s': _round(durationS),
    'rom_deg': _round(romDeg),
    'peak_gyro_dps': _round(peakGyroDps),
    'mean_gyro_dps': _round(meanGyroDps),
    'emg_rms_mean_mv': _round(emgRmsMeanMv),
    'emg_rms_peak_mv': _round(emgRmsPeakMv),
    'velocity_loss': _round(velocityLoss),
    'duration_ratio': _round(durationRatio),
    'rom_ratio': _round(romRatio),
    'emg_ratio': _round(emgRatio),
    'emg_per_velocity_ratio': _round(emgPerVelocityRatio),
  };

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;
}

/// Turns the raw streams of one set into [RepFeatures], one per rep.
///
/// Feed it every IMU sample and EMG snapshot during the set, and call
/// [onRep] each time the wearable counts a curl. A rep spans from the
/// previous rep (or the set start) up to the rep event.
class RepFeatureExtractor {
  /// Reps averaged for the baseline the relative features compare against.
  static const baselineReps = 2;

  /// Rotation speed (deg/s) above which the forearm counts as moving.
  static const movingDps = 20.0;

  final List<RepFeatures> reps = [];
  final List<double> _gyro = [];
  final List<double> _emg = [];
  int? _repStartMs;

  void addSample(ImuSample s) {
    _repStartMs ??= s.timestampMs;
    _gyro.add(sqrt(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz));
  }

  void addEmg(EmgSnapshot e) {
    _repStartMs ??= e.timestampMs;
    _emg.add(e.rmsMv.toDouble());
  }

  /// Closes the current rep window and returns its features, or null if
  /// no data arrived for it.
  RepFeatures? onRep(RepUpdate update) {
    final start = _repStartMs;
    if (start == null || _gyro.isEmpty) {
      _reset(update.timestampMs);
      return null;
    }
    final moving = _gyro.where((g) => g > movingDps).length;
    final durationS = moving > 0
        ? moving / WearableProtocol.imuRateHz
        : max(0.0, (update.timestampMs - start) / 1000);
    final peakGyro = _gyro.reduce(max);
    final meanGyro = _gyro.reduce((a, b) => a + b) / _gyro.length;
    final emgMean = _emg.isEmpty
        ? 0.0
        : _emg.reduce((a, b) => a + b) / _emg.length;
    final emgPeak = _emg.isEmpty ? 0.0 : _emg.reduce(max);

    // The baseline is the set's first reps; the first rep is compared with
    // itself.
    final base = reps.take(baselineReps).toList();
    double avg(Iterable<double> v) => v.reduce((a, b) => a + b) / v.length;
    final basePeak = base.isEmpty
        ? peakGyro
        : avg(base.map((r) => r.peakGyroDps));
    // Rep 1 runs from the set start to the first rep event, so it's only
    // part of a curl; time the baseline from rep 2 on.
    final fullReps = reps.skip(1).take(baselineReps);
    final baseDuration = fullReps.isEmpty
        ? durationS
        : avg(fullReps.map((r) => r.durationS));
    final baseRom = base.isEmpty
        ? update.romDeg
        : avg(base.map((r) => r.romDeg));
    final baseEmg = base.isEmpty
        ? emgMean
        : avg(base.map((r) => r.emgRmsMeanMv));

    double ratio(double a, double b) => b <= 0 ? 1 : a / b;
    final features = RepFeatures(
      repIndex: reps.length + 1,
      durationS: durationS,
      romDeg: update.romDeg,
      peakGyroDps: peakGyro,
      meanGyroDps: meanGyro,
      emgRmsMeanMv: emgMean,
      emgRmsPeakMv: emgPeak,
      velocityLoss: 1 - ratio(peakGyro, basePeak),
      durationRatio: ratio(durationS, baseDuration),
      romRatio: ratio(update.romDeg, baseRom),
      emgRatio: ratio(emgMean, baseEmg),
      emgPerVelocityRatio: ratio(
        ratio(emgMean, peakGyro),
        ratio(baseEmg, basePeak),
      ),
    );
    reps.add(features);
    _reset(update.timestampMs);
    return features;
  }

  void _reset(int startMs) {
    _gyro.clear();
    _emg.clear();
    _repStartMs = startMs;
  }
}
