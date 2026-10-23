import 'dart:math';

import 'package:flutter/material.dart';

import '../wearable/protocol.dart';
import '../wearable/wearable_controller.dart';
import '../widgets/charts.dart';

/// Full-screen page for pairing with the wearable. Shown after the splash
/// during onboarding, and again from inside the app to manage the device.
class ConnectPage extends StatelessWidget {
  const ConnectPage({
    super.key,
    required this.wearable,
    required this.onContinue,
    this.continueLabel = 'Continue',
    this.onSkip,
  });

  final WearableController wearable;

  /// Called from the connected card's main button.
  final VoidCallback onContinue;
  final String continueLabel;

  /// When set (onboarding), shows "Skip for now" so the app can be used
  /// without a wearable.
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect your wearable'),
        automaticallyImplyLeading: onSkip == null,
      ),
      body: SafeArea(
        top: false,
        child: _ConnectBody(
          wearable: wearable,
          onContinue: onContinue,
          continueLabel: continueLabel,
          onSkip: onSkip,
        ),
      ),
    );
  }
}

class _ConnectBody extends StatelessWidget {
  const _ConnectBody({
    required this.wearable,
    required this.onContinue,
    required this.continueLabel,
    required this.onSkip,
  });

  final WearableController wearable;
  final VoidCallback onContinue;
  final String continueLabel;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: wearable,
      builder: (context, _) {
        final status = wearable.status;
        final showList =
            status == LinkStatus.scanning ||
            (status == LinkStatus.disconnected && wearable.scanFinished);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusCard(
              wearable: wearable,
              onContinue: onContinue,
              continueLabel: continueLabel,
            ),
            if (wearable.error != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: wearable.error!),
            ],
            if (showList) ...[
              const SizedBox(height: 24),
              _NearbyList(wearable: wearable),
            ],
            if (wearable.isConnected) ...[
              const SizedBox(height: 16),
              _LiveSensorCard(wearable: wearable),
            ],
            if (status == LinkStatus.disconnected) ...[
              const SizedBox(height: 24),
              Center(
                child: TextButton.icon(
                  onPressed: wearable.connectDemo,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('No hardware? Try the demo wearable'),
                ),
              ),
            ],
            if (onSkip != null && !wearable.isConnected)
              Center(
                child: TextButton(
                  onPressed: onSkip,
                  child: const Text('Skip for now'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.wearable,
    required this.onContinue,
    required this.continueLabel,
  });

  final WearableController wearable;
  final VoidCallback onContinue;
  final String continueLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final connected = wearable.isConnected;

    final (
      Widget icon,
      String title,
      String subtitle,
    ) = switch (wearable.status) {
      LinkStatus.disconnected => (
        Icon(Icons.bluetooth, size: 40, color: scheme.primary),
        'Not connected',
        'Power on your wearable, then tap Connect.',
      ),
      LinkStatus.scanning => (
        const _Spinner(),
        'Searching…',
        'Looking for ${WearableProtocol.deviceName} nearby.',
      ),
      LinkStatus.connecting => (
        const _Spinner(),
        'Connecting…',
        'Pairing with ${wearable.connected?.name ?? 'your wearable'}.',
      ),
      LinkStatus.connected => (
        const Icon(Icons.check_circle, size: 40, color: Colors.white),
        'Connected',
        wearable.isDemo
            ? 'Demo wearable · simulated data'
            : '${wearable.connected!.name} · ${wearable.sampleRate} Hz',
      ),
    };

    final background = connected
        ? const Color(0xFF2E9E6A)
        : scheme.surfaceContainerHigh;
    final foreground = connected ? Colors.white : scheme.onSurface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          SizedBox(height: 48, child: Center(child: icon)),
          const SizedBox(height: 12),
          Text(
            title,
            style: text.headlineSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(
              color: foreground.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: switch (wearable.status) {
              LinkStatus.disconnected => FilledButton.icon(
                onPressed: wearable.scan,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Connect'),
                style: _bigButton,
              ),
              LinkStatus.scanning => OutlinedButton(
                onPressed: wearable.stopScan,
                style: _bigButton,
                child: const Text('Stop searching'),
              ),
              LinkStatus.connecting => FilledButton(
                onPressed: null,
                style: _bigButton,
                child: const Text('Connecting…'),
              ),
              LinkStatus.connected => Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: wearable.disconnect,
                      style: _bigButton.copyWith(
                        foregroundColor: const WidgetStatePropertyAll(
                          Colors.white,
                        ),
                        side: const WidgetStatePropertyAll(
                          BorderSide(color: Colors.white70),
                        ),
                      ),
                      child: const Text('Disconnect'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onContinue,
                      style: _bigButton.copyWith(
                        backgroundColor: const WidgetStatePropertyAll(
                          Colors.white,
                        ),
                        foregroundColor: const WidgetStatePropertyAll(
                          Color(0xFF1E6E49),
                        ),
                      ),
                      child: Text(continueLabel),
                    ),
                  ),
                ],
              ),
            },
          ),
        ],
      ),
    );
  }
}

final _bigButton = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
  textStyle: const WidgetStatePropertyAll(
    TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  ),
);

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 36,
    height: 36,
    child: CircularProgressIndicator(strokeWidth: 3.5),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyList extends StatelessWidget {
  const _NearbyList({required this.wearable});

  final WearableController wearable;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final found = wearable.found;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nearby wearables', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Only devices running the Team 9 firmware are shown.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 8),
        if (found.isEmpty && wearable.status == LinkStatus.disconnected)
          const Card(
            child: ListTile(
              leading: Icon(Icons.search_off),
              title: Text('No wearable found'),
              subtitle: Text(
                'Check it is powered on and not connected to another phone, then tap Connect again.',
              ),
            ),
          ),
        for (final w in found)
          Card(
            child: ListTile(
              leading: _SignalIcon(rssi: w.rssi),
              title: Text(w.name),
              subtitle: Text('${w.id} · ${w.rssi} dBm'),
              trailing: FilledButton.tonal(
                onPressed: () => wearable.connect(w),
                child: const Text('Connect'),
              ),
            ),
          ),
      ],
    );
  }
}

class _SignalIcon extends StatelessWidget {
  const _SignalIcon({required this.rssi});

  final int rssi;

  @override
  Widget build(BuildContext context) {
    final icon = rssi > -60
        ? Icons.signal_cellular_alt
        : rssi > -75
        ? Icons.signal_cellular_alt_2_bar
        : Icons.signal_cellular_alt_1_bar;
    return Icon(icon);
  }
}

class _LiveSensorCard extends StatelessWidget {
  const _LiveSensorCard({required this.wearable});

  final WearableController wearable;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = wearable.latest;
    final r = wearable.lastRepUpdate;
    String f(double? v, int digits) => v?.toStringAsFixed(digits) ?? '–';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Sensor check', style: text.titleMedium),
                const Spacer(),
                Text('IMU ${wearable.sampleRate} Hz', style: text.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            _AxisRow(
              label: 'Accel (g)',
              values: [f(s?.ax, 2), f(s?.ay, 2), f(s?.az, 2)],
            ),
            const SizedBox(height: 8),
            _AxisRow(
              label: 'Gyro (°/s)',
              values: [f(s?.gx, 0), f(s?.gy, 0), f(s?.gz, 0)],
            ),
            const SizedBox(height: 8),
            // Curl here to check the rep counter without starting a set.
            _AxisRow(
              label: 'Reps',
              names: const ['total', 'range'],
              values: [
                r?.reps.toString() ?? '–',
                r == null || r.reps == 0 ? '–' : '${r.romDeg.round()}°',
              ],
            ),
            const SizedBox(height: 12),
            _EmgCheck(wearable: wearable),
          ],
        ),
      ),
    );
  }
}

/// The latest EMG snapshot over a chart of recent RMS. Redraws on every
/// snapshot (10 Hz) rather than with the rest of the card, so flexing shows
/// up right away.
class _EmgCheck extends StatelessWidget {
  const _EmgCheck({required this.wearable});

  final WearableController wearable;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StreamBuilder<EmgSnapshot>(
      stream: wearable.emg,
      builder: (context, _) {
        final e = wearable.latestEmg;
        final rms = [for (final s in wearable.emgHistory) s.rmsMv.toDouble()];
        String f(int? v) => v?.toString() ?? '–';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AxisRow(
              label: 'EMG (mV)',
              names: const ['rms', 'min', 'max'],
              values: [f(e?.rmsMv), f(e?.minMv), f(e?.maxMv)],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              // Scale to the biggest recent value, but not below 50 mV so
              // resting noise stays near the bottom.
              child: MotionLine(
                values: rms,
                range: rms.fold(50, max),
                signed: false,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Muscle activity (RMS), last ${WearableController.emgWindow} s',
              style: text.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

class _AxisRow extends StatelessWidget {
  const _AxisRow({
    required this.label,
    required this.values,
    this.names = const ['x', 'y', 'z'],
  });

  final String label;
  final List<String> values;

  /// Shown before each value.
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        SizedBox(width: 84, child: Text(label, style: text.bodySmall)),
        for (final (i, v) in values.indexed)
          Expanded(
            child: Text(
              '${names[i]} $v',
              style: text.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }
}
