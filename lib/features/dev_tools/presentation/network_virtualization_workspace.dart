import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../domain/network_virtualization_service.dart';
import '../domain/system_proxy_service.dart';

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
  SystemProxySnapshot? _systemProxy;
  final SystemProxyService _systemProxyService = SystemProxyService();
  String _configPath = '';
  String _diskPath = '';
  String _isoPath = '';
  String _message = '';
  bool _busy = false;
  int _memory = 2048;
  int _cpus = 2;
  int _diskSizeGiB = 32;
  final TextEditingController _proxyPort = TextEditingController(text: '7890');

  String get _proxyDataDirectory =>
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}tmp'
      '${Platform.pathSeparator}mihomo';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _proxyPort.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final List<BundledRuntimeStatus> status = await Future.wait(
      <Future<BundledRuntimeStatus>>[
        NetworkVirtualizationService.inspectMihomo(),
        NetworkVirtualizationService.inspectQemu(),
      ],
    );
    SystemProxySnapshot? systemProxy;
    if (Platform.isWindows) {
      try {
        systemProxy = await _systemProxyService.inspect();
      } on Object {
        systemProxy = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _mihomo = status[0];
      _qemu = status[1];
      _systemProxy = systemProxy;
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

  Future<void> _startProxyAndEnableSystem() async {
    final int? port = int.tryParse(_proxyPort.text.trim());
    if (port == null) throw const FormatException('请输入配置中的 mixed-port');
    await NetworkVirtualizationService.startMihomo(
      configPath: _configPath,
      dataDirectory: _proxyDataDirectory,
    );
    try {
      _systemProxy = await _systemProxyService.applyLocal(
        port: port,
        dataDirectory: _proxyDataDirectory,
      );
    } on Object {
      await NetworkVirtualizationService.stopMihomo();
      rethrow;
    }
  }

  Future<void> _confirmProxyStart() async {
    final bool? approved = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('启动代理并切换 Windows 网络？'),
        content: Text(
          '将启动内置 Mihomo，并把当前用户系统代理切换到 '
          '127.0.0.1:${_proxyPort.text.trim()}。原设置会先保存，停止时自动恢复。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('mihomo-confirm-system-proxy'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('启动并切换'),
          ),
        ],
      ),
    );
    if (approved == true) await _run(_startProxyAndEnableSystem);
  }

  Future<void> _stopProxyAndRestoreSystem() async {
    _systemProxy = await _systemProxyService.restore(
      dataDirectory: _proxyDataDirectory,
    );
    await NetworkVirtualizationService.stopMihomo();
  }

  Future<void> _createDisk() async {
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: 'vibekits-vm.qcow2',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'QEMU 磁盘', extensions: <String>['qcow2']),
      ],
    );
    if (location == null) return;
    await NetworkVirtualizationService.createQemuDisk(
      path: location.path,
      sizeGiB: _diskSizeGiB,
    );
    if (mounted) setState(() => _diskPath = location.path);
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
      const SizedBox(height: 8),
      TextField(
        key: const Key('mihomo-proxy-port'),
        controller: _proxyPort,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: '系统代理端口',
          helperText: '填写配置文件中的 mixed-port，默认 7890',
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _systemProxy == null
            ? '系统代理：正在读取'
            : '系统代理：${_systemProxy!.enabled ? '已启用' : '未启用'}'
                  '${_systemProxy!.server == null ? '' : ' · ${_systemProxy!.server}'}',
        key: const Key('system-proxy-status'),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: <Widget>[
          FilledButton.icon(
            key: const Key('mihomo-start'),
            onPressed: _busy || _mihomo?.available != true
                ? null
                : _confirmProxyStart,
            icon: const Icon(Icons.play_arrow),
            label: const Text('启动并启用系统代理'),
          ),
          OutlinedButton.icon(
            key: const Key('mihomo-stop'),
            onPressed: _busy ? null : () => _run(_stopProxyAndRestoreSystem),
            icon: const Icon(Icons.stop),
            label: const Text('停止并恢复原网络'),
          ),
        ],
      ),
      if (_message.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        SelectableText(_message),
      ],
      const SizedBox(height: 16),
      const Text(
        '启用前会保存当前 Windows 用户代理；停止时恢复原值。异常退出后备份仍保留，可再次点击“停止并恢复原网络”。TUN 不会静默开启。',
      ),
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
      Row(
        children: <Widget>[
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _diskSizeGiB,
              decoration: const InputDecoration(labelText: '新磁盘容量'),
              items: const <int>[8, 16, 32, 64, 128, 256]
                  .map(
                    (int value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value GiB'),
                    ),
                  )
                  .toList(),
              onChanged: (int? value) => _diskSizeGiB = value ?? _diskSizeGiB,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const Key('qemu-create-disk'),
            onPressed: _busy ? null : () => _run(_createDisk),
            icon: const Icon(Icons.add_to_drive_outlined),
            label: const Text('创建磁盘'),
          ),
        ],
      ),
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
      const SizedBox(height: 12),
      const Text(
        '支持的来宾系统：Windows 7～11、主流 x86_64 Linux、BSD 和其他 PC x86/x64 系统。当前不宣称支持 macOS 来宾或 ARM 系统。',
      ),
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
