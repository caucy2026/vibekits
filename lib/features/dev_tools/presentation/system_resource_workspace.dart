import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/system_resource_service.dart';

class SystemResourceWorkspace extends StatefulWidget {
  const SystemResourceWorkspace({super.key, this.inspector});

  final Future<SystemResourceSnapshot> Function(String? adbSerial)? inspector;

  @override
  State<SystemResourceWorkspace> createState() =>
      _SystemResourceWorkspaceState();
}

class _SystemResourceWorkspaceState extends State<SystemResourceWorkspace> {
  final TextEditingController _serial = TextEditingController();
  final SystemResourceProbeController _probeController =
      SystemResourceProbeController();
  SystemResourceSnapshot? _snapshot;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _probeController.cancel();
    _serial.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool androidDevice = false}) async {
    if (_loading) return;
    final String? serial = androidDevice ? _serial.text.trim() : null;
    if (androidDevice && serial!.isEmpty) {
      setState(() => _error = '请输入已连接的 ADB 设备序列号');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final SystemResourceSnapshot result = widget.inspector != null
          ? await widget.inspector!(serial)
          : serial == null
          ? await SystemResourceService.inspectLocal(
              processRunner: _probeController.run,
            )
          : await SystemResourceService.inspectAndroidDevice(serial: serial);
      if (!mounted) return;
      setState(() => _snapshot = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final SystemResourceSnapshot? snapshot = _snapshot;
    return Column(
      children: <Widget>[
        _toolbar(),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: <Widget>[
              TextButton(onPressed: () => _refresh(), child: const Text('重试')),
            ],
          ),
        Expanded(
          child: snapshot == null
              ? const Center(child: Text('界面已就绪，正在后台读取资源快照…'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    Text(
                      '${snapshot.target} · ${snapshot.platform}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '采样于 ${snapshot.capturedAt.toLocal()} · 单次快照不代表持续负载',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        _metric(
                          '处理器',
                          '${snapshot.cpuPercent.toStringAsFixed(1)}%',
                          '${snapshot.logicalProcessors} 逻辑核心'
                              '${snapshot.loadAverage == null ? '' : ' · Load ${snapshot.loadAverage!.toStringAsFixed(2)}'}',
                          snapshot.cpuPercent / 100,
                          Icons.memory,
                        ),
                        _metric(
                          '内存',
                          '${snapshot.memoryUsedPercent.toStringAsFixed(1)}%',
                          '可用 ${_bytes(snapshot.memoryAvailableBytes)} / ${_bytes(snapshot.memoryTotalBytes)}',
                          snapshot.memoryUsedPercent / 100,
                          Icons.storage_outlined,
                        ),
                        _metric(
                          'GPU',
                          snapshot.gpuPercent == null
                              ? '未取得'
                              : '${snapshot.gpuPercent!.toStringAsFixed(1)}%',
                          snapshot.gpuNames.isEmpty
                              ? '设备未提供统一计数器'
                              : snapshot.gpuNames.join(' / '),
                          (snapshot.gpuPercent ?? 0) / 100,
                          Icons.videogame_asset_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '图表说明：CPU 表示当前处理器忙碌比例；内存表示已用物理内存比例；GPU 仅在系统提供可靠计数器时显示。进度条越接近右侧，占用越高。',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('诊断建议'),
                    Card(
                      child: Column(
                        children: <Widget>[
                          for (final String warning in snapshot.warnings)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                warning.startsWith('单次')
                                    ? Icons.check_circle_outline
                                    : Icons.warning_amber_rounded,
                              ),
                              title: Text(warning),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('磁盘'),
                    const Text(
                      '每条磁盘图表表示该分区已用空间比例，右侧同时给出剩余容量；这里只读分析，不会自动删除文件。',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    Card(
                      child: Column(
                        children: <Widget>[
                          for (final ResourceStorageSample disk
                              in snapshot.storage)
                            ListTile(
                              leading: const Icon(Icons.storage_outlined),
                              title: Text(disk.name),
                              subtitle: LinearProgressIndicator(
                                value: (disk.usedPercent / 100).clamp(0, 1),
                              ),
                              trailing: Text(
                                '剩余 ${_bytes(disk.freeBytes)}\n${disk.usedPercent.toStringAsFixed(1)}% 已用',
                                textAlign: TextAlign.right,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle('当前 Top 进程'),
                    Card(
                      child: Column(
                        children: <Widget>[
                          for (final ResourceProcessSample process
                              in snapshot.processes)
                            ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                child: Text(
                                  '${process.pid}',
                                  style: const TextStyle(fontSize: 9),
                                ),
                              ),
                              title: Text(process.name),
                              subtitle: Text(
                                'CPU ${process.cpuPercent.toStringAsFixed(1)}%',
                              ),
                              trailing: Text(
                                process.memoryBytes == 0
                                    ? '内存未取得'
                                    : _bytes(process.memoryBytes),
                              ),
                            ),
                          if (snapshot.processes.isEmpty)
                            const ListTile(title: Text('当前系统未返回进程计数器')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('证据：${snapshot.evidence.join(' · ')}'),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _toolbar() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(
      children: <Widget>[
        FilledButton.icon(
          key: const Key('system-resource-refresh'),
          onPressed: _loading ? null : () => _refresh(),
          icon: const Icon(Icons.refresh),
          label: const Text('采样本机'),
        ),
        if (!Platform.isAndroid && !Platform.isIOS) ...<Widget>[
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: const Key('system-resource-adb-serial'),
              controller: _serial,
              decoration: const InputDecoration(
                labelText: 'Android ADB 设备',
                hintText: '例如 192.168.3.63:5555',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const Key('system-resource-adb-inspect'),
            onPressed: _loading ? null : () => _refresh(androidDevice: true),
            icon: const Icon(Icons.android),
            label: const Text('分析 Android'),
          ),
        ],
      ],
    ),
  );

  Widget _metric(
    String title,
    String value,
    String detail,
    double progress,
    IconData icon,
  ) => SizedBox(
    width: 270,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            const SizedBox(height: 10),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress.clamp(0, 1)),
            const SizedBox(height: 8),
            Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    ),
  );

  Widget _sectionTitle(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(value, style: Theme.of(context).textTheme.titleMedium),
  );

  String _bytes(int value) {
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double number = value.toDouble();
    int unit = 0;
    while (number >= 1024 && unit < units.length - 1) {
      number /= 1024;
      unit++;
    }
    return '${number.toStringAsFixed(unit < 2 ? 0 : 1)} ${units[unit]}';
  }
}
