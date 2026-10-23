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
          'Tap Start, then curl. The wearable counts a rep each time your '
          'forearm swings up and back down.',
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
    final rom = workout.lastRomDeg;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.surfaceContainerHighest,
                      width: 14,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                    label: 'Last rep range',
                    value: rom == null ? '–' : '${rom.round()}°',
                  ),
                  _Stat(label: 'Time', value: _formatDuration(workout.elapsed)),
                ],
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
