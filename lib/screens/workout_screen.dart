import 'package:flutter/material.dart';

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
        const SizedBox(height: 24),
        Icon(Icons.fitness_center, size: 56, color: scheme.primary),
        const SizedBox(height: 16),
        Text(
          'Bicep curls',
          textAlign: TextAlign.center,
          style: text.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Start curling after you tap Start. We count your reps and tell '
          'you when to stop, a couple of reps before failure.',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 32),
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
        if (last != null) ...[
          const SizedBox(height: 32),
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

class _ActiveSet extends StatelessWidget {
  const _ActiveSet({required this.workout});

  final WorkoutController workout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final fatigue = workout.fatigue;

    return Column(
      children: [
        _AdviceBanner(advice: workout.advice, fatigue: fatigue != null),
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
                    label: 'Reps left',
                    value: fatigue == null ? '–' : '${fatigue.repsLeft}',
                  ),
                  _Stat(
                    label: 'Fatigue',
                    value: fatigue == null
                        ? '–'
                        : '${(fatigue.fatigue * 100).round()}%',
                  ),
                  _Stat(label: 'Time', value: _formatDuration(workout.elapsed)),
                ],
              ),
              if (fatigue == null) ...[
                const SizedBox(height: 8),
                Text(
                  'Fatigue and reps left appear once the wearable streams '
                  'the model output.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Arm motion', style: text.titleSmall),
                      Text(
                        'Forearm rotation speed, last '
                        '${WorkoutController.motionWindow} s',
                        style: text.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 90,
                        child: MotionLine(values: workout.motion),
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
  const _AdviceBanner({required this.advice, required this.fatigue});

  final SetAdvice advice;
  final bool fatigue;

  @override
  Widget build(BuildContext context) {
    final (color, icon, message) = switch (advice) {
      SetAdvice.keepGoing => (
        const Color(0xFF2E9E6A),
        Icons.trending_up,
        fatigue ? 'Looking strong — keep going' : 'Set in progress',
      ),
      SetAdvice.almostDone => (
        const Color(0xFFE0A100),
        Icons.warning_amber_rounded,
        'Almost there — finish your last reps',
      ),
      SetAdvice.stop => (
        const Color(0xFFD9452B),
        Icons.front_hand,
        'Stop now — rack the weight',
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
        ],
      ),
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
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(label, style: text.bodySmall),
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
