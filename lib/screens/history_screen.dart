import 'dart:math';

import 'package:flutter/material.dart';

import '../widgets/charts.dart';
import '../widgets/tiles.dart';
import '../workout/workout_controller.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.workout});

  final WorkoutController workout;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: workout,
      builder: (context, _) {
        final sets = workout.history;
        if (sets.isEmpty) return const _Empty();

        final text = Theme.of(context).textTheme;
        final totalReps = sets.fold<int>(0, (sum, s) => sum + s.reps);
        final recent = sets.take(10).toList().reversed.toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                StatTile(label: 'Sets', value: '${sets.length}'),
                const SizedBox(width: 12),
                StatTile(label: 'Total reps', value: '$totalReps'),
                const SizedBox(width: 12),
                StatTile(
                  label: 'Best set',
                  value: '${sets.map((s) => s.reps).reduce(max)}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reps per set', style: text.titleSmall),
                    Text('Last ${recent.length} sets', style: text.bodySmall),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 110,
                      child: RepBars(values: [for (final s in recent) s.reps]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('All sets', style: text.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () => _confirmClear(context),
                  child: const Text('Clear'),
                ),
              ],
            ),
            for (final s in sets) SetTile(set: s),
          ],
        );
      },
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('This deletes every saved set on this phone.'),
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
    if (ok == true) await workout.clearHistory();
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

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
              Icons.insights,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No sets yet', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Finished sets show up here so you can track progress.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
