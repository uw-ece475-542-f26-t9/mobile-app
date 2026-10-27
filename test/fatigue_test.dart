import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uw_ece475_542_t9_app/fatigue/fatigue_model.dart';
import 'package:uw_ece475_542_t9_app/fatigue/rep_features.dart';
import 'package:uw_ece475_542_t9_app/fatigue/training_data.dart';
import 'package:uw_ece475_542_t9_app/main.dart';
import 'package:uw_ece475_542_t9_app/screens/workout_screen.dart';
import 'package:uw_ece475_542_t9_app/wearable/protocol.dart';

/// Feeds [extractor] one curl lasting [seconds] that peaks at [peakDps],
/// with EMG at [emgMv], ending in a rep event at [endMs].
RepFeatures _curl(
  RepFeatureExtractor extractor, {
  required int endMs,
  double seconds = 2,
  double peakDps = 200,
  int emgMv = 80,
  double romDeg = 120,
}) {
  final n = (seconds * WearableProtocol.imuRateHz).round();
  final startMs = endMs - (seconds * 1000).round();
  for (var i = 0; i < n; i++) {
    final t = startMs + i * 20;
    // Half a sine: moving the whole time, fastest in the middle.
    final gx = peakDps * (0.2 + 0.8 * (1 - ((i / n) * 2 - 1).abs()));
    extractor.addSample(
      ImuSample(timestampMs: t, ax: 0, ay: 0, az: 1, gx: gx, gy: 0, gz: 0),
    );
    if (i % 5 == 0) {
      extractor.addEmg(
        EmgSnapshot(
          timestampMs: t,
          sampleCount: 200,
          meanMv: 1650,
          rmsMv: emgMv,
          minMv: 1500,
          maxMv: 1800,
        ),
      );
    }
  }
  return extractor.onRep(
    RepUpdate(timestampMs: endMs, reps: 0, romDeg: romDeg),
  )!;
}

/// A set that slows down and needs more EMG every rep.
List<RepFeatures> _tiringSet(int reps) {
  final x = RepFeatureExtractor();
  return [
    for (var i = 0; i < reps; i++)
      _curl(
        x,
        endMs: 10000 + i * 3000,
        peakDps: 200 * (1 - 0.05 * i),
        seconds: 2 + 0.1 * i,
        emgMv: 80 + 5 * i,
        romDeg: 120 - 3.0 * i,
      ),
  ];
}

void main() {
  group('RepFeatureExtractor', () {
    test('first rep is its own baseline', () {
      final r = _curl(RepFeatureExtractor(), endMs: 5000);
      expect(r.repIndex, 1);
      expect(r.velocityLoss, 0);
      expect(r.romRatio, 1);
      expect(r.emgRatio, 1);
      expect(r.peakGyroDps, closeTo(200, 5));
      expect(r.emgRmsMeanMv, 80);
    });

    test('later reps are compared with the start of the set', () {
      final x = RepFeatureExtractor();
      _curl(x, endMs: 3000);
      _curl(x, endMs: 6000);
      final r = _curl(x, endMs: 9000, peakDps: 150, emgMv: 120, romDeg: 90);
      expect(r.repIndex, 3);
      expect(r.velocityLoss, closeTo(0.25, 0.02));
      expect(r.emgRatio, closeTo(1.5, 0.01));
      expect(r.romRatio, closeTo(0.75, 0.01));
      // 1.5x the EMG for 0.75x the speed.
      expect(r.emgPerVelocityRatio, closeTo(2.0, 0.05));
    });

    test('a pause before curling does not count as rep time', () {
      final x = RepFeatureExtractor();
      for (var t = 0; t < 3000; t += 20) {
        x.addSample(
          ImuSample(timestampMs: t, ax: 0, ay: 0, az: 1, gx: 1, gy: 0, gz: 0),
        );
      }
      final r = _curl(x, endMs: 5000);
      expect(r.durationS, closeTo(2, 0.1));
    });
  });

  group('VelocityLossModel', () {
    const model = VelocityLossModel();

    test('needs a few reps first', () {
      expect(model.predict(_tiringSet(2)), isNull);
      expect(model.predict(_tiringSet(3)), isNotNull);
    });

    test('fatigue rises and reps to failure fall as the set slows', () {
      final early = model.predict(_tiringSet(4))!;
      final late = model.predict(_tiringSet(9))!;
      expect(late.fatigue, greaterThan(early.fatigue));
      expect(late.repsToFailure, lessThan(early.repsToFailure));
    });

    test('safe reps left stops short of failure', () {
      const e = FatigueEstimate(fatigue: 0.8, repsToFailure: 3.6, source: '');
      expect(e.safeRepsLeft, 3 - safetyMarginReps);
      const done = FatigueEstimate(fatigue: 1, repsToFailure: 0, source: '');
      expect(done.safeRepsLeft, 0);
    });
  });

  group('LinearRirModel', () {
    // Same shape as the file tools/train_fatigue_model.py writes.
    final json = {
      'name': 'Test model',
      'features': ['rep_index', 'velocity_loss'],
      'mean': [5.0, 0.2],
      'std': [2.0, 0.1],
      'coef': [-2.0, -1.0],
      'intercept': 4.0,
    };

    test('applies standardized coefficients', () {
      final model = LinearRirModel.fromJson(json);
      final reps = _tiringSet(5);
      final x = reps.last.modelInputs;
      final expected =
          4.0 -
          2.0 * (x['rep_index']! - 5) / 2 -
          1.0 * (x['velocity_loss']! - 0.2) / 0.1;
      final e = model.predict(reps)!;
      expect(e.repsToFailure, closeTo(expected.clamp(0, 99), 1e-9));
      expect(e.fatigue, closeTo(5 / (5 + e.repsToFailure), 1e-9));
      expect(e.source, 'Test model');
    });

    test('rejects mismatched lengths', () {
      expect(
        () => LinearRirModel.fromJson({
          ...json,
          'coef': [1.0],
        }),
        throwsFormatException,
      );
    });

    test('app falls back to the baseline without a bundled model', () async {
      final model = await loadFatigueModel(bundle: _EmptyBundle());
      expect(model, isA<VelocityLossModel>());
    });

    test('app loads a bundled model', () async {
      final model = await loadFatigueModel(
        bundle: _JsonBundle(jsonEncode(json)),
      );
      expect(model.name, 'Test model');
    });
  });

  test('exported set has labels, features and raw streams', () {
    final rec =
        SetRecording(startedAt: DateTime(2026, 10, 27, 9, 5), deviceName: 'X')
          ..reps.addAll(_tiringSet(3))
          ..predictedRepsToFailure.addAll([null, null, 4.5])
          ..imu.add(
            const ImuSample(
              timestampMs: 1,
              ax: 0,
              ay: 0,
              az: 1,
              gx: 2,
              gy: 3,
              gz: 4,
            ),
          );
    const labels = SetLabels(
      subjectId: 'S 01!',
      weightKg: 12.5,
      reachedFailure: false,
      repsInReserve: 2,
    );
    final out = jsonDecode(jsonEncode(rec.toJson(labels))) as Map;
    expect(out['schema'], trainingSchema);
    expect(
      SetLabels.fromJson(out['labels'] as Map<String, Object?>).weightKg,
      12.5,
    );
    final reps = out['reps'] as List;
    expect(reps, hasLength(3));
    expect((reps.last as Map)['predicted_reps_to_failure'], 4.5);
    expect((reps.last as Map)['velocity_loss'], isA<num>());
    expect((out['raw'] as Map)['imu'], [
      [1, 0.0, 0.0, 1.0, 2.0, 3.0, 4.0],
    ]);
    expect(rec.toJson(labels, includeRaw: false).containsKey('raw'), isFalse);
    expect(rec.fileName(labels), 'fatigue-set_S01_20261027-090500.json');
  });

  testWidgets('a recorded set is labelled and saved for training', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const FatigueCoachApp());
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No hardware? Try the demo wearable'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.fitness_center));
    await tester.pumpAndSettle();

    // The other tabs have their own lists, so scroll the Workout one.
    final workoutList = find
        .descendant(
          of: find.byType(WorkoutScreen),
          matching: find.byType(Scrollable),
        )
        .first;

    await tester.scrollUntilVisible(
      find.text('Record for model training'),
      200,
      scrollable: workoutList,
    );
    expect(find.textContaining('0 training sets saved'), findsOneWidget);
    await tester.tap(find.text('Record for model training'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Start'),
      -200,
      scrollable: workoutList,
    );
    await tester.tap(find.text('Start'));
    await tester.pump();

    // Enough demo curls for the model to start estimating.
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('REC'), findsOneWidget);
    expect(find.textContaining('reps to failure'), findsOneWidget);
    await tester.tap(find.text('End set'));
    await tester.pumpAndSettle();

    expect(find.text('Label this set'), findsOneWidget);
    final save = find.text('Save & export');
    bool saveEnabled() => tester
        .widget<ButtonStyleButton>(
          find.ancestor(
            of: save,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        )
        .enabled;
    await tester.scrollUntilVisible(save, 200, scrollable: workoutList);
    expect(saveEnabled(), isFalse); // needs a subject and weight
    await tester.enterText(find.widgetWithText(TextField, 'Subject ID'), 'S01');
    await tester.enterText(find.widgetWithText(TextField, 'Weight (kg)'), '10');
    await tester.pump();
    await tester.scrollUntilVisible(save, 200, scrollable: workoutList);
    expect(saveEnabled(), isTrue);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    // Saved on the device (the share sheet isn't available in tests, so
    // the export itself reports an error).
    expect(find.text('Label this set'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Record for model training'),
      200,
      scrollable: workoutList,
    );
    expect(find.textContaining('1 training set saved'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('training_sets_v1')!;
    final set = jsonDecode(stored.single) as Map;
    expect((set['labels'] as Map)['subject_id'], 'S01');
    expect(set.containsKey('raw'), isFalse);

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
  });
}

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw FlutterError('Unable to load asset: $key');
}

class _JsonBundle extends CachingAssetBundle {
  _JsonBundle(this.json);

  final String json;

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(json)));
}
