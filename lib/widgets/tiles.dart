import 'package:flutter/material.dart';

import '../workout/history_store.dart';
import 'charts.dart';

/// A big number with a label under it.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(label, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// One finished set: reps, duration, when, and peak fatigue.
class SetTile extends StatelessWidget {
  const SetTile({super.key, required this.set});

  final WorkoutSet set;

  @override
  Widget build(BuildContext context) {
    final peak = set.peakFatigue;
    final secs = set.duration.inSeconds;
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${set.reps}')),
        title: Text(
          '${set.reps} reps · ${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
        ),
        subtitle: Text(_formatDate(set.startedAt)),
        trailing: peak == null
            ? null
            : Chip(
                label: Text('${(peak * 100).round()}% fatigue'),
                backgroundColor: FatigueRing.colorFor(peak)
                    .withValues(alpha: 0.15),
                side: BorderSide.none,
              ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day}, $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}
