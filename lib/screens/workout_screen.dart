import 'package:flutter/material.dart';

import '../fatigue/fatigue_model.dart';
import '../fatigue/training_data.dart';
import '../widgets/charts.dart';
import '../workout/workout_controller.dart';

class WorkoutScreen extends StatelessWidget {
  const WorkoutScreen({
    super.key,
    required this.workout,
    required this.onConnect,
  });

  final WorkoutController workout;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([workout, workout.wearable]),
      builder: (context, _) {
        // Labelling comes first, even if the wearable dropped.
        if (workout.pendingRecording != null) {
          return _LabelSet(workout: workout);
        }
        if (!workout.wearable.isConnected) {
          return _NotConnected(onConnect: onConnect);
        }
        return workout.active
            ? _ActiveSet(workout: workout)
            : _Ready(workout: workout);
      },
    );
  }
}

class _NotConnected extends StatelessWidget {
  const _NotConnected({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bluetooth_disabled,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No wearable connected', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Connect your sensor to start tracking a set.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Connect wearable'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({required this.workout});

  final WorkoutController workout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final last = workout.history.firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        Icon(Icons.fitness_center, size: 56, color: scheme.primary),
        const SizedBox(height: 16),
        Text(
          'Bicep curls',
          textAlign: TextAlign.center,
          style: text.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Tap Start, then curl. The wearable counts each rep, and the app '
          'estimates your fatigue from the third rep on.',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 160,
          child: Center(
            child: SizedBox.square(
              dimension: 160,
              child: FilledButton(
                onPressed: workout.startSet,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  textStyle: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Start'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        _TrainingCard(workout: workout),
        if (last != null) ...[
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: Text('Last set: ${last.reps} reps'),
              subtitle: Text(_formatDuration(last.duration)),
            ),
          ),
        ],
      ],
    );
  }
}

/// Turns on recording for model training and manages what's been saved.
class _TrainingCard extends StatelessWidget {
  const _TrainingCard({required this.workout});

  final WorkoutController workout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final count = workout.trainingSetCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              value: workout.recordForTraining,
              onChanged: (v) => workout.recordForTraining = v,
              secondary: const Icon(Icons.fiber_manual_record_outlined),
              title: const Text('Record for model training'),
              subtitle: const Text(
                'Go to failure (or close), then label the set when it ends.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$count training ${count == 1 ? 'set' : 'sets'} saved · '
                      'model: ${workout.modelName}',
                      style: text.bodySmall,
                    ),
                  ),
                  if (count > 0) ...[
                    TextButton(
                      onPressed: workout.exportTrainingData,
                      child: const Text('Export'),
                    ),
                    TextButton(
                      onPressed: () => _confirmClear(context),
                      child: const Text('Clear'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear training data?'),
        content: const Text(
          'This deletes the training sets saved on this device. Files you '
          'already exported are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) await workout.clearTrainingData();
  }
}

class _ActiveSet extends StatelessWidget {
  const _ActiveSet({required this.workout});

  final WorkoutController workout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rom = workout.lastRomDeg;
    final fatigue = workout.fatigue;

    return Column(
      children: [
        _AdviceBanner(
          advice: workout.advice,
          estimate: fatigue,
          recording: workout.recordForTraining,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SizedBox(
                height: 230,
                child: FatigueRing(
                  fatigue: fatigue?.fatigue,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${workout.reps}',
                        style: text.displayLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        workout.reps == 1 ? 'rep' : 'reps',
                        style: text.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _Stat(
                    label: 'Fatigue',
                    value: fatigue == null
                        ? '–'
                        : '${(fatigue.fatigue * 100).round()}%',
                  ),
                  _Stat(
                    label: 'Safe reps left',
                    value: fatigue == null ? '–' : '${fatigue.safeRepsLeft}',
                  ),
                  _Stat(
                    label: 'Last rep range',
                    value: rom == null ? '–' : '${rom.round()}°',
                  ),
                  _Stat(label: 'Time', value: _formatDuration(workout.elapsed)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                fatigue == null
                    ? 'Fatigue appears after a few reps. Model: '
                          '${workout.modelName}.'
                    : '≈${fatigue.repsToFailure.toStringAsFixed(1)} reps to '
                          'failure · ${fatigue.source}',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Arm motion', style: text.titleSmall),
                      Text(
                        'How fast your forearm is turning, last '
                        '${WorkoutController.motionWindow} s',
                        style: text.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 90,
                        child: MotionLine(
                          values: workout.motion,
                          range: 250,
                          signed: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FilledButton.icon(
            onPressed: workout.endSet,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('End set'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: scheme.inverseSurface,
              foregroundColor: scheme.onInverseSurface,
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AdviceBanner extends StatelessWidget {
  const _AdviceBanner({
    required this.advice,
    required this.estimate,
    required this.recording,
  });

  final SetAdvice advice;
  final FatigueEstimate? estimate;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final (color, icon, message) = switch (advice) {
      SetAdvice.keepGoing => (
        const Color(0xFF2E9E6A),
        Icons.trending_up,
        estimate == null ? 'Set in progress' : 'Looking strong — keep going',
      ),
      SetAdvice.almostDone => (
        const Color(0xFFE0A100),
        Icons.warning_amber_rounded,
        'Almost there — one more safe rep',
      ),
      SetAdvice.stop => (
        const Color(0xFFD9452B),
        Icons.front_hand,
        // While collecting training data the lifter goes on to failure.
        recording
            ? 'Safe stop reached — continue only if recording to failure'
            : 'Stop now — rack the weight',
      ),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
          if (recording)
            const Chip(
              avatar: Icon(Icons.circle, size: 10, color: Color(0xFFD9452B)),
              label: Text('REC'),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// After a recorded set: the labels the model learns from.
class _LabelSet extends StatefulWidget {
  const _LabelSet({required this.workout});

  final WorkoutController workout;

  @override
  State<_LabelSet> createState() => _LabelSetState();
}

class _LabelSetState extends State<_LabelSet> {
  late final _subject = TextEditingController(
    text: widget.workout.lastSubject ?? '',
  );
  final _weight = TextEditingController();
  final _notes = TextEditingController();
  bool _failure = true;
  int _repsInReserve = 1;
  double? _rpe;
  bool _saving = false;

  @override
  void dispose() {
    _subject.dispose();
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _valid =>
      _subject.text.trim().isNotEmpty &&
      (double.tryParse(_weight.text.trim()) ?? 0) > 0;

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.workout.saveRecording(
        SetLabels(
          subjectId: _subject.text.trim(),
          weightKg: double.parse(_weight.text.trim()),
          reachedFailure: _failure,
          repsInReserve: _failure ? 0 : _repsInReserve,
          rpe: _rpe,
          notes: _notes.text.trim(),
        ),
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Training set saved and exported')),
      );
    } catch (e) {
      // The set is already saved on the device; only the export failed.
      messenger.showSnackBar(
        SnackBar(content: Text('Saved, but the export failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reps = widget.workout.pendingRecording!.reps.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Label this set', style: text.headlineSmall),
        const SizedBox(height: 4),
        Text(
          '$reps reps recorded. These answers are what the model learns '
          'from, so be honest about how many you had left.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _subject,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Subject ID',
            hintText: 'e.g. S01 (no names)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _weight,
          onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Weight (kg)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _failure,
          onChanged: (v) => setState(() => _failure = v),
          title: const Text('Went to failure'),
          subtitle: const Text("Couldn't do another rep with good form"),
        ),
        if (!_failure)
          Row(
            children: [
              const Expanded(child: Text('Reps left in the tank')),
              IconButton(
                onPressed: _repsInReserve > 1
                    ? () => setState(() => _repsInReserve--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_repsInReserve', style: text.titleLarge),
              IconButton(
                onPressed: _repsInReserve < 10
                    ? () => setState(() => _repsInReserve++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Text('Effort (RPE, optional)', style: text.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final v in [6.0, 7.0, 8.0, 9.0, 10.0])
              ChoiceChip(
                label: Text(v.toStringAsFixed(0)),
                selected: _rpe == v,
                onSelected: (s) => setState(() => _rpe = s ? v : null),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            hintText: 'e.g. sensor slipped on rep 8',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _valid && !_saving ? _save : null,
          icon: const Icon(Icons.save_alt),
          label: const Text('Save & export'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _saving ? null : widget.workout.discardRecording,
          child: const Text('Discard this set'),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(label, textAlign: TextAlign.center, style: text.bodySmall),
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
