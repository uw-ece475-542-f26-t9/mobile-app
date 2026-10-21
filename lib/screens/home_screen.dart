import 'package:flutter/material.dart';

import '../wearable/wearable_controller.dart';
import '../widgets/charts.dart';
import '../widgets/tiles.dart';
import '../workout/history_store.dart';
import '../workout/workout_controller.dart';

/// Dashboard: device status, a quick way into a set, this week's activity,
/// and the latest sets.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.workout,
    required this.onManageDevice,
    required this.onStartSet,
    required this.onSeeHistory,
  });

  final WorkoutController workout;
  final VoidCallback onManageDevice;
  final VoidCallback onStartSet;
  final VoidCallback onSeeHistory;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([workout, workout.wearable]),
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        final week = _Week.from(workout.history, DateTime.now());
        final recent = workout.history.take(3).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(_greeting(), style: text.headlineSmall),
            Text(
              'Ready for some curls?',
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _DeviceCard(wearable: workout.wearable, onTap: onManageDevice),
            const SizedBox(height: 12),
            _StartCard(
              connected: workout.wearable.isConnected,
              active: workout.active,
              onTap: workout.wearable.isConnected ? onStartSet : onManageDevice,
            ),
            const SizedBox(height: 24),
            Text('This week', style: text.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                StatTile(label: 'Sets', value: '${week.sets}'),
                const SizedBox(width: 12),
                StatTile(label: 'Reps', value: '${week.reps}'),
                const SizedBox(width: 12),
                StatTile(
                  label: 'Avg fatigue',
                  value: week.avgPeakFatigue == null
                      ? '–'
                      : '${(week.avgPeakFatigue! * 100).round()}%',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('Reps per day', style: text.titleSmall),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 120,
                      child: DayBars(
                        values: week.repsPerDay,
                        labels: week.dayLabels,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('Recent sets', style: text.titleMedium),
                const Spacer(),
                if (recent.isNotEmpty)
                  TextButton(
                    onPressed: onSeeHistory,
                    child: const Text('See all'),
                  ),
              ],
            ),
            if (recent.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.flag_outlined),
                  title: Text('No sets yet'),
                  subtitle: Text('Your first set will show up here.'),
                ),
              ),
            for (final s in recent) SetTile(set: s),
          ],
        );
      },
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.wearable, required this.onTap});

  final WearableController wearable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = wearable.isConnected;
    final color = connected ? const Color(0xFF2E9E6A) : scheme.outline;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: color,
          ),
        ),
        title: Text(connected ? wearable.connected!.name : 'No wearable'),
        subtitle: Text(
          connected
              ? (wearable.isDemo
                    ? 'Connected · simulated data'
                    : 'Connected · ${wearable.sampleRate} Hz')
              : 'Tap to connect',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.connected,
    required this.active,
    required this.onTap,
  });

  final bool connected;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (title, subtitle) = active
        ? ('Set in progress', 'Jump back to your live reps')
        : connected
        ? ('Start a set', 'Bicep curls · live rep count & fatigue')
        : ('Connect to start', 'Pair your wearable to track a set');
    return Material(
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B3C49), Color(0xFF0F7C8C)],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: text.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 32,
                  color: Color(0xFF0F7C8C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The last 7 days (today last), summarized from saved sets.
class _Week {
  _Week({
    required this.sets,
    required this.reps,
    required this.avgPeakFatigue,
    required this.repsPerDay,
    required this.dayLabels,
  });

  final int sets;
  final int reps;
  final double? avgPeakFatigue;
  final List<int> repsPerDay;
  final List<String> dayLabels;

  factory _Week.from(List<WorkoutSet> history, DateTime now) {
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final today = DateTime(now.year, now.month, now.day);
    final days = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    final repsPerDay = List.filled(7, 0);
    final fatigues = <double>[];
    var sets = 0;
    for (final s in history) {
      final d = s.startedAt;
      final index = days.indexOf(DateTime(d.year, d.month, d.day));
      if (index < 0) continue;
      sets++;
      repsPerDay[index] += s.reps;
      if (s.peakFatigue != null) fatigues.add(s.peakFatigue!);
    }
    return _Week(
      sets: sets,
      reps: repsPerDay.fold(0, (a, b) => a + b),
      avgPeakFatigue: fatigues.isEmpty
          ? null
          : fatigues.reduce((a, b) => a + b) / fatigues.length,
      repsPerDay: repsPerDay,
      dayLabels: [for (final d in days) names[d.weekday - 1]],
    );
  }
}
