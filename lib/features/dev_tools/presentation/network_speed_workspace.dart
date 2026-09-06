import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/network_speed_service.dart';

class NetworkSpeedWorkspace extends StatefulWidget {
  const NetworkSpeedWorkspace({super.key, this.service});

  final NetworkSpeedService? service;

  @override
  State<NetworkSpeedWorkspace> createState() => _NetworkSpeedWorkspaceState();
}

class _NetworkSpeedWorkspaceState extends State<NetworkSpeedWorkspace> {
  NetworkSpeedCancellation? _cancellation;
  NetworkSpeedProgress? _progress;
  NetworkSpeedResult? _result;
  String? _error;
  bool _running = false;

  Future<void> _start() async {
    if (_running) return;
    final NetworkSpeedCancellation cancellation = NetworkSpeedCancellation();
    setState(() {
      _running = true;
      _cancellation = cancellation;
      _progress = const NetworkSpeedProgress(
        phase: NetworkSpeedPhase.latency,
        completedUnits: 0,
        totalUnits: 5,
        currentMbps: 0,
        detail: '正在连接测速服务器',
      );
      _result = null;
      _error = null;
    });
    try {
      final NetworkSpeedResult result =
          await (widget.service ?? NetworkSpeedService()).run(
            cancellation: cancellation,
            onProgress: (NetworkSpeedProgress value) {
              if (mounted && identical(_cancellation, cancellation)) {
                setState(() => _progress = value);
              }
            },
          );
      if (mounted && identical(_cancellation, cancellation)) {
        setState(() => _result = result);
      }
    } on NetworkSpeedCancelled {
      if (mounted && identical(_cancellation, cancellation)) {
        setState(() => _error = '测速已由用户停止');
      }
    } on Object catch (error) {
      if (mounted && identical(_cancellation, cancellation)) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      if (mounted && identical(_cancellation, cancellation)) {
        setState(() {
          _running = false;
          _cancellation = null;
        });
      }
    }
  }

  void _stop() => _cancellation?.cancel();

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _header(theme),
              const SizedBox(height: 18),
              _metrics(theme),
              const SizedBox(height: 16),
              _progressPanel(theme),
              const SizedBox(height: 16),
              _methodPanel(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.speed_rounded, color: theme.colorScheme.primary),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('公网带宽测速', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '测量到公开测速节点的延迟、抖动、下载和上传带宽。测试会产生约 8.7 MB 网络流量。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      if (_running)
        FilledButton.tonalIcon(
          key: const Key('network-speed-stop'),
          onPressed: _stop,
          icon: const Icon(Icons.stop_rounded),
          label: const Text('停止测试'),
        )
      else
        FilledButton.icon(
          key: const Key('network-speed-start'),
          onPressed: _start,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(_result == null ? '开始测速' : '重新测试'),
        ),
    ],
  );

  Widget _metrics(ThemeData theme) {
    final NetworkSpeedResult? result = _result;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth >= 720
            ? (constraints.maxWidth - 36) / 4
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _MetricCard(
              key: const Key('network-speed-latency'),
              width: width,
              icon: Icons.network_ping_rounded,
              label: '延迟',
              value: result == null ? '—' : result.latencyMs.toStringAsFixed(1),
              unit: 'ms',
            ),
            _MetricCard(
              key: const Key('network-speed-jitter'),
              width: width,
              icon: Icons.multiline_chart_rounded,
              label: '抖动',
              value: result == null ? '—' : result.jitterMs.toStringAsFixed(1),
              unit: 'ms',
            ),
            _MetricCard(
              key: const Key('network-speed-download'),
              width: width,
              icon: Icons.download_rounded,
              label: '下载',
              value: result == null
                  ? '—'
                  : result.downloadMbps.toStringAsFixed(1),
              unit: 'Mbps',
            ),
            _MetricCard(
              key: const Key('network-speed-upload'),
              width: width,
              icon: Icons.upload_rounded,
              label: '上传',
              value: result == null
                  ? '—'
                  : result.uploadMbps.toStringAsFixed(1),
              unit: 'Mbps',
            ),
          ],
        );
      },
    );
  }

  Widget _progressPanel(ThemeData theme) {
    final NetworkSpeedProgress? progress = _progress;
    final String title = _result != null
        ? '测试完成'
        : _error != null
        ? _error!
        : progress?.detail ?? '尚未开始';
    final Color accent = _error == null
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    return Container(
      key: const Key('network-speed-progress-panel'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.vibe.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.vibe.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (_running)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else
                Icon(
                  _result != null
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  size: 20,
                  color: accent,
                ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              if (_running && (progress?.currentMbps ?? 0) > 0)
                Text(
                  '${progress!.currentMbps.toStringAsFixed(1)} Mbps',
                  key: const Key('network-speed-live-rate'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 13),
          LinearProgressIndicator(
            key: const Key('network-speed-progress'),
            value: _running ? progress?.fraction : (_result == null ? 0 : 1),
          ),
          const SizedBox(height: 10),
          Text(
            _phaseDescription(progress?.phase),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _methodPanel(ThemeData theme) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('测量方法', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          const Text(
            '服务器：speed.cloudflare.com\n'
            '流程：5 次延迟采样 → 100 KB/1 MB/5 MB 分档下载 → '
            '100 KB/500 KB/2 MB 分档上传。带宽使用各档有效速率的 P90，'
            '延迟使用中位数，抖动使用延迟绝对偏差中位数。结果代表当前设备到该测速节点的路径表现，'
            '会受 Wi-Fi、运营商路由、代理和后台流量影响。',
          ),
        ],
      ),
    ),
  );

  static String _phaseDescription(NetworkSpeedPhase? phase) => switch (phase) {
    NetworkSpeedPhase.latency => '正在测量往返响应时间，不下载大文件。',
    NetworkSpeedPhase.download => '正在逐级增加下载样本，观察链路是否达到稳定吞吐。',
    NetworkSpeedPhase.upload => '正在发送随机空白测试数据，测量上行吞吐。',
    NetworkSpeedPhase.complete => '结果已按多次样本汇总。',
    null => '点击“开始测速”后将依次测试延迟、下载和上传。',
  };

  static String _friendlyError(Object error) {
    final String text = '$error';
    if (text.contains('timed out') || text.contains('TimeoutException')) {
      return '测速超时，请检查网络或代理后重试';
    }
    if (text.contains('Failed host lookup')) return '无法解析测速服务器';
    return '测速失败，请检查网络后重试';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    super.key,
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 19,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 7),
                Text(label),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: value,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                    ),
                    TextSpan(text: '  $unit'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
