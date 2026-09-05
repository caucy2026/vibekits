import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

String formatStopwatchDuration(Duration value) {
  final int hundredths = (value.inMilliseconds ~/ 10) % 100;
  final int seconds = value.inSeconds % 60;
  final int minutes = value.inMinutes % 60;
  final int hours = value.inHours;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(hours)}:${two(minutes)}:${two(seconds)}.${two(hundredths)}';
}

class StopwatchWorkspace extends StatefulWidget {
  const StopwatchWorkspace({super.key});

  @override
  State<StopwatchWorkspace> createState() => _StopwatchWorkspaceState();
}

class _StopwatchWorkspaceState extends State<StopwatchWorkspace> {
  final Stopwatch _watch = Stopwatch();
  final List<Duration> _laps = <Duration>[];
  Timer? _ticker;

  Duration get _elapsed => _watch.elapsed;

  void _toggle() {
    if (_watch.isRunning) {
      _watch.stop();
      _ticker?.cancel();
      _ticker = null;
    } else {
      _watch.start();
      _ticker ??= Timer.periodic(const Duration(milliseconds: 10), (_) {
        if (mounted) setState(() {});
      });
    }
    setState(() {});
  }

  void _reset() {
    _watch
      ..stop()
      ..reset();
    _ticker?.cancel();
    _ticker = null;
    setState(_laps.clear);
  }

  void _lap() {
    if (!_watch.isRunning) return;
    setState(() => _laps.insert(0, _elapsed));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 12),
                      Semantics(
                        label: '秒表表盘',
                        value: formatStopwatchDuration(_elapsed),
                        child: SizedBox.square(
                          dimension: 250,
                          child: CustomPaint(
                            painter: _StopwatchDialPainter(
                              elapsed: _elapsed,
                              color: theme.colorScheme.primary,
                              muted: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        formatStopwatchDuration(_elapsed),
                        key: const Key('stopwatch-digital-value'),
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 10,
                        children: <Widget>[
                          FilledButton.icon(
                            key: const Key('stopwatch-toggle'),
                            onPressed: _toggle,
                            icon: Icon(
                              _watch.isRunning
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(_watch.isRunning ? '暂停' : '开始'),
                          ),
                          OutlinedButton.icon(
                            key: const Key('stopwatch-lap'),
                            onPressed: _watch.isRunning ? _lap : null,
                            icon: const Icon(Icons.flag_outlined),
                            label: const Text('计次'),
                          ),
                          OutlinedButton.icon(
                            key: const Key('stopwatch-reset'),
                            onPressed: _elapsed == Duration.zero
                                ? null
                                : _reset,
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('复位'),
                          ),
                        ],
                      ),
                      if (_laps.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 24),
                        const Divider(),
                        for (int index = 0; index < _laps.length; index++)
                          ListTile(
                            dense: true,
                            leading: Text('计次 ${_laps.length - index}'),
                            trailing: Text(
                              formatStopwatchDuration(_laps[index]),
                              style: const TextStyle(
                                fontFeatures: <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              Text(
                '1 秒 = 100 份 · 精度 0.01 秒',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StopwatchDialPainter extends CustomPainter {
  const _StopwatchDialPainter({
    required this.elapsed,
    required this.color,
    required this.muted,
  });

  final Duration elapsed;
  final Color color;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2 - 10;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = muted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (int i = 0; i < 100; i++) {
      final double angle = i * math.pi * 2 / 100 - math.pi / 2;
      final bool major = i % 10 == 0;
      final double outer = radius - 5;
      final double inner = outer - (major ? 13 : 6);
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * inner,
        center + Offset(math.cos(angle), math.sin(angle)) * outer,
        Paint()
          ..color = major ? color : muted
          ..strokeWidth = major ? 2.2 : 1,
      );
    }
    final double seconds = (elapsed.inMilliseconds % 60000) / 1000;
    final double angle = seconds * math.pi * 2 / 60 - math.pi / 2;
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle), math.sin(angle)) * (radius - 26),
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _StopwatchDialPainter oldDelegate) =>
      oldDelegate.elapsed.inMilliseconds ~/ 10 !=
          elapsed.inMilliseconds ~/ 10 ||
      oldDelegate.color != color ||
      oldDelegate.muted != muted;
}
