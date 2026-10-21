import 'package:flutter/material.dart';

import 'screens/connect_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/workout_screen.dart';
import 'wearable/wearable_controller.dart';
import 'workout/workout_controller.dart';

void main() {
  runApp(const FatigueCoachApp());
}

/// App flow: animated splash → connect the wearable → main app
/// (Home, Workout, History).
class FatigueCoachApp extends StatefulWidget {
  const FatigueCoachApp({super.key});

  @override
  State<FatigueCoachApp> createState() => _FatigueCoachAppState();
}

class _FatigueCoachAppState extends State<FatigueCoachApp> {
  static const _seed = Color(0xFF0F7C8C);

  final _navigator = GlobalKey<NavigatorState>();
  final _wearable = WearableController();
  late final _workout = WorkoutController(_wearable);

  @override
  void dispose() {
    _workout.dispose();
    _wearable.dispose();
    super.dispose();
  }

  void _replaceWith(Widget page) {
    _navigator.currentState!.pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  void _showOnboardingConnect() => _replaceWith(
    ConnectPage(wearable: _wearable, onContinue: _showHome, onSkip: _showHome),
  );

  void _showHome() =>
      _replaceWith(HomeShell(wearable: _wearable, workout: _workout));

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.symmetric(vertical: 4),
      ),
    );

    return MaterialApp(
      title: 'Fatigue Coach',
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: SplashScreen(onDone: _showOnboardingConnect),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.wearable, required this.workout});

  final WearableController wearable;
  final WorkoutController workout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _workoutTab = 1, _historyTab = 2;

  int _tab = 0;

  void _goTo(int tab) => setState(() => _tab = tab);

  void _manageDevice() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ConnectPage(
          wearable: widget.wearable,
          continueLabel: 'Done',
          onContinue: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['Home', 'Workout', 'History'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          _ConnectionChip(wearable: widget.wearable, onTap: _manageDevice),
          const SizedBox(width: 12),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(
            workout: widget.workout,
            onManageDevice: _manageDevice,
            onStartSet: () => _goTo(_workoutTab),
            onSeeHistory: () => _goTo(_historyTab),
          ),
          WorkoutScreen(workout: widget.workout, onConnect: _manageDevice),
          HistoryScreen(workout: widget.workout),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _goTo,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center),
            label: 'Workout',
          ),
          NavigationDestination(icon: Icon(Icons.insights), label: 'History'),
        ],
      ),
    );
  }
}

/// Always-visible connection state in the app bar; tap to manage the device.
class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.wearable, required this.onTap});

  final WearableController wearable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: wearable,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final (color, label) = switch (wearable.status) {
          LinkStatus.connected => (const Color(0xFF2E9E6A), 'Connected'),
          LinkStatus.scanning => (scheme.tertiary, 'Searching'),
          LinkStatus.connecting => (scheme.tertiary, 'Connecting'),
          LinkStatus.disconnected => (scheme.outline, 'Offline'),
        };
        return ActionChip(
          onPressed: onTap,
          avatar: Icon(Icons.circle, size: 10, color: color),
          label: Text(label),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        );
      },
    );
  }
}
