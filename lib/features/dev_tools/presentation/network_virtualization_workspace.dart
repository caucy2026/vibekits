import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../domain/network_virtualization_service.dart';

class NetworkVirtualizationWorkspace extends StatefulWidget {
  const NetworkVirtualizationWorkspace({super.key});

  @override
  State<NetworkVirtualizationWorkspace> createState() =>
      _NetworkVirtualizationWorkspaceState();
}

class _NetworkVirtualizationWorkspaceState
    extends State<NetworkVirtualizationWorkspace> {
  BundledRuntimeStatus? _mihomo;
  BundledRuntimeStatus? _qemu;
  String _configPath = '';
  String _diskPath = '';
  String _isoPath = '';
  String _message = '';
  bool _busy = false;
  int _memory = 2048;
  int _cpus = 2;

  String get _proxyDataDirectory =>
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}tmp'
      '${Platform.pathSeparator}mihomo';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final List<BundledRuntimeStatus> status = await Future.wait(
      <Future<BundledRuntimeStatus>>[
        NetworkVirtualizationService.inspectMihomo(),
        NetworkVirtualizationService.inspectQemu(),
      ],
    );
    if (!mounted) return;
    setState(() {
      _mihomo = status[0];
      _qemu = status[1];
    });
  }

  Future<void> _pickConfig() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'Clash YAML', extensions: <String>['yaml', 'yml']),
      ],
    );
    if (file != null && mounted) setState(() => _configPath = file.path);
  }

  Future<void> _pickDisk() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: '虚拟磁盘',
          extensions: <String>['qcow2', 'vhd', 'vhdx', 'vmdk', 'img', 'raw'],
        ),
      ],
    );
    if (file != null && mounted) setState(() => _diskPath = file.path);
  }

  Future<void> _pickIso() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: '安装镜像', extensions: <String>['iso']),
      ],
    );
    if (file != null && mounted) setState(() => _isoPath = file.path);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await action();
      _message = '操作完成';
    } on Object catch (error) {
      _message = '$error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: <Widget>[
          const TabBar(
            tabs: <Widget>[
              Tab(icon: Icon(Icons.shield_outlined), text: 'Clash Verge'),
              Tab(icon: Icon(Icons.computer_outlined), text: '轻量虚拟机'),
            ],
          ),
          Expanded(
            child: TabBarView(children: <Widget>[_proxyTab(), _vmTab()]),
          ),
        ],
      ),
    );
  }

  Widget _runtimeCard(BundledRuntimeStatus? status) {
    final bool available = status?.available == true;
    return Card(
      child: ListTile(
        leading: Icon(
          available ? Icons.check_circle_outline : Icons.error_outline,
          color: available ? Colors.green : Colors.red,
        ),
        title: Text(status?.name ?? '正在检查运行时…'),
        subtitle: Text(
          status == null ? '' : '${status.version}\n${status.executable}',
          maxLines: 3,
        ),
        trailing: IconButton(
          tooltip: '重新检查',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ),
    );
  }

  Widget _proxyTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Text('网络代理', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('内置 Mihomo 内核，兼容 Clash Verge 配置。启动和停止均在独立进程，不阻塞界面。'),
      const SizedBox(height: 12),
      _runtimeCard(_mihomo),
      const SizedBox(height: 12),
      TextField(
        key: const Key('mihomo-config-path'),
        controller: TextEditingController(text: _configPath),
        readOnly: true,
        decoration: InputDecoration(
          labelText: '配置文件',
          hintText: '选择 .yaml / .yml',
          suffixIcon: IconButton(
            tooltip: '选择配置',
            onPressed: _pickConfig,
            icon: const Icon(Icons.folder_open_outlined),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('运行数据：$_proxyDataDirectory'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: <Widget>[
          FilledButton.icon(
            key: const Key('mihomo-start'),
            onPressed: _busy || _mihomo?.available != true
                ? null
                : () => _run(() async {
                    await NetworkVirtualizationService.startMihomo(
                      configPath: _configPath,
                      dataDirectory: _proxyDataDirectory,
                    );
                  }),
            icon: const Icon(Icons.play_arrow),
            label: const Text('启动'),
          ),
          OutlinedButton.icon(
            key: const Key('mihomo-stop'),
            onPressed: _busy
                ? null
                : () => _run(NetworkVirtualizationService.stopMihomo),
            icon: const Icon(Icons.stop),
            label: const Text('停止'),
          ),
        ],
      ),
      if (_message.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        SelectableText(_message),
      ],
      const SizedBox(height: 16),
      const Text('说明：当前版本先提供兼容配置的本地内核与运行控制；修改系统代理和 TUN 需要单独明确授权，未静默修改系统网络。'),
    ],
  );

  Widget _vmTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Text('轻量虚拟机', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('内置 QEMU x86_64 运行时。选择已有磁盘或 ISO 后启动，关闭不会影响 Vibekits 主界面。'),
      const SizedBox(height: 12),
      _runtimeCard(_qemu),
      const SizedBox(height: 12),
      _pathField('虚拟磁盘（可选）', _diskPath, _pickDisk),
      const SizedBox(height: 8),
      _pathField('安装 ISO（可选）', _isoPath, _pickIso),
      const SizedBox(height: 12),
      Row(
        children: <Widget>[
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _memory,
              decoration: const InputDecoration(labelText: '内存'),
              items: const <int>[512, 1024, 2048, 4096, 8192]
                  .map(
                    (int value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value MiB'),
                    ),
                  )
                  .toList(),
              onChanged: (int? value) => _memory = value ?? _memory,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _cpus,
              decoration: const InputDecoration(labelText: 'CPU'),
              items: const <int>[1, 2, 4, 8]
                  .map(
                    (int value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value 核'),
                    ),
                  )
                  .toList(),
              onChanged: (int? value) => _cpus = value ?? _cpus,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: <Widget>[
          FilledButton.icon(
            key: const Key('qemu-start'),
            onPressed: _busy || _qemu?.available != true
                ? null
                : () => _run(() async {
                    await NetworkVirtualizationService.startQemu(
                      diskPath: _diskPath,
                      isoPath: _isoPath,
                      memoryMiB: _memory,
                      cpuCount: _cpus,
                    );
                  }),
            icon: const Icon(Icons.play_arrow),
            label: const Text('启动虚拟机'),
          ),
          OutlinedButton.icon(
            key: const Key('qemu-stop'),
            onPressed: _busy
                ? null
                : () => _run(NetworkVirtualizationService.stopQemu),
            icon: const Icon(Icons.stop),
            label: const Text('停止'),
          ),
        ],
      ),
      if (_message.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        SelectableText(_message),
      ],
    ],
  );

  Widget _pathField(String label, String value, VoidCallback pick) => TextField(
    controller: TextEditingController(text: value),
    readOnly: true,
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: IconButton(
        tooltip: '选择文件',
        onPressed: pick,
        icon: const Icon(Icons.folder_open_outlined),
      ),
    ),
  );
}
