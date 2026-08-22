import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../domain/mihomo_controller_service.dart';
import '../domain/mihomo_profile_service.dart';
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
  late final MihomoProfileService _profileService;
  List<MihomoProfile> _profiles = const <MihomoProfile>[];
  List<String> _subscriptionLog = const <String>[];
  MihomoProfile? _activeProfile;
  MihomoManagedConfig? _runningConfig;
  MihomoControllerSnapshot? _controllerSnapshot;
  final Map<String, int?> _nodeDelays = <String, int?>{};
  Timer? _dashboardTimer;
  bool _testingDelay = false;
  int _testedNodes = 0;
  int _delayTestGeneration = 0;
  String _diskPath = '';
  String _isoPath = '';
  String _message = '';
  bool _busy = false;
  int _memory = 2048;
  int _cpus = 2;
  int _diskSizeGiB = 32;

  String get _proxyDataDirectory =>
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}tmp'
      '${Platform.pathSeparator}mihomo';

  bool get _proxyRunning =>
      NetworkVirtualizationService.status()['mihomoRunning'] == true;

  MihomoControllerService? get _controller {
    final MihomoConfigSummary? summary = _runningConfig?.summary;
    return summary?.controller == null
        ? null
        : MihomoControllerService(summary!.controller!, secret: summary.secret);
  }

  @override
  void initState() {
    super.initState();
    _profileService = MihomoProfileService(dataDirectory: _proxyDataDirectory);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _dashboardTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    await Future.wait<void>(<Future<void>>[_loadProfiles(), _refresh()]);
  }

  Future<void> _loadProfiles() async {
    final MihomoProfileState state = await _profileService.load();
    final List<String> activity = await _profileService.readActivityLog();
    if (!mounted) return;
    setState(() {
      _profiles = state.profiles;
      _subscriptionLog = activity;
      _activeProfile = state.profiles
          .where((MihomoProfile item) => item.id == state.activeId)
          .firstOrNull;
    });
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
    if (_proxyRunning) await _refreshController();
  }

  Future<void> _pickConfig() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'Clash YAML', extensions: <String>['yaml', 'yml']),
      ],
    );
    if (file == null) return;
    await _run(() async {
      final MihomoProfile profile = await _profileService.importConfig(
        sourcePath: file.path,
      );
      await _loadProfiles();
      if (mounted) setState(() => _activeProfile = profile);
    }, success: '配置已导入，可直接启动');
  }

  Future<void> _addSubscription() async {
    final TextEditingController name = TextEditingController();
    final TextEditingController url = TextEditingController();
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('添加订阅'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      hintText: '例如：工作代理',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('mihomo-subscription-url'),
                    controller: url,
                    decoration: const InputDecoration(
                      labelText: '订阅地址',
                      hintText: 'https://…',
                      helperText: '完整地址保存在系统凭据库，不写入普通设置和日志',
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('mihomo-add-subscription-confirm'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('下载并添加'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      await _run(() async {
        final MihomoProfile profile = await _profileService.addSubscription(
          name: name.text,
          url: url.text,
        );
        await _loadProfiles();
        if (mounted) setState(() => _activeProfile = profile);
      }, success: '订阅已添加并设为当前配置');
    }
    name.dispose();
    url.dispose();
  }

  Future<void> _selectProfile(MihomoProfile profile) async {
    if (_proxyRunning) {
      setState(() => _message = '请先停止当前代理，再切换配置');
      return;
    }
    await _profileService.select(profile.id);
    if (mounted) setState(() => _activeProfile = profile);
  }

  Future<void> _updateProfile(MihomoProfile profile) async {
    await _run(() async {
      final MihomoProfile updated = await _profileService.update(profile);
      await _loadProfiles();
      if (mounted) setState(() => _activeProfile = updated);
    }, success: '订阅已更新');
  }

  Future<void> _deleteProfile(MihomoProfile profile) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('删除配置？'),
            content: Text('将删除“${profile.name}”的本地副本和订阅凭据，不影响服务商账户。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _run(() async {
      await _profileService.delete(profile);
      await _loadProfiles();
    }, success: '配置已删除');
  }

  Future<void> _startProxyAndEnableSystem() async {
    final MihomoProfile? profile = _activeProfile;
    if (profile == null) throw StateError('请先添加订阅或导入 Clash YAML');
    final MihomoManagedConfig config = await _profileService
        .prepareManagedConfig(profile);
    await NetworkVirtualizationService.startMihomo(
      configPath: config.path,
      dataDirectory: _proxyDataDirectory,
    );
    try {
      _systemProxy = await _systemProxyService.applyLocal(
        port: config.summary.mixedPort,
        dataDirectory: _proxyDataDirectory,
      );
      _runningConfig = config;
      await _waitForController();
      _startDashboardTimer();
    } on Object {
      try {
        _systemProxy = await _systemProxyService.restore(
          dataDirectory: _proxyDataDirectory,
        );
      } on Object {
        // Preserve the original startup failure. A later refresh will surface
        // the actual Windows proxy state without hiding the root cause.
      }
      await NetworkVirtualizationService.stopMihomo();
      _runningConfig = null;
      rethrow;
    }
  }

  Future<void> _confirmProxyStart() async {
    final MihomoProfile? profile = _activeProfile;
    if (profile == null) {
      setState(() => _message = '请先添加订阅或导入 Clash YAML');
      return;
    }
    final bool approved =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('启动代理并切换 Windows 网络？'),
            content: Text(
              '将启动“${profile.name}”，并把当前用户系统代理切换到 '
              '127.0.0.1:${profile.summary.mixedPort}。原设置会先保存，停止时自动恢复。',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('mihomo-confirm-system-proxy'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('启动并切换'),
              ),
            ],
          ),
        ) ??
        false;
    if (approved) {
      await _run(_startProxyAndEnableSystem, success: '代理已启动，系统代理已启用');
    }
  }

  Future<void> _waitForController() async {
    Object? lastError;
    for (int attempt = 0; attempt < 30; attempt++) {
      try {
        await _refreshController();
        return;
      } on Object catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw StateError('Mihomo 已启动，但控制面板未就绪：$lastError');
  }

  void _startDashboardTimer() {
    _dashboardTimer?.cancel();
    _dashboardTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshController(silent: true)),
    );
  }

  Future<void> _refreshController({bool silent = false}) async {
    final MihomoControllerService? controller = _controller;
    if (controller == null) return;
    try {
      final MihomoControllerSnapshot snapshot = await controller.snapshot();
      if (mounted) setState(() => _controllerSnapshot = snapshot);
    } on Object {
      if (!silent) rethrow;
    }
  }

  Future<void> _setMode(String mode) async {
    final MihomoControllerService? controller = _controller;
    if (controller == null) return;
    await _run(() async {
      await controller.setMode(mode);
      await _refreshController();
    }, success: '代理模式已切换');
  }

  Future<void> _selectNode(MihomoProxyGroup group, String node) async {
    final MihomoControllerService? controller = _controller;
    if (controller == null) return;
    await _run(() async {
      await controller.selectNode(group.name, node);
      await _refreshController();
    }, success: '节点已切换为 $node');
  }

  Future<void> _testDelays({MihomoProxyGroup? group}) async {
    if (_testingDelay || !_proxyRunning) return;
    final MihomoControllerService? controller = _controller;
    final MihomoControllerSnapshot? snapshot = _controllerSnapshot;
    if (controller == null || snapshot == null) return;
    final List<String> nodes =
        (group == null
                ? snapshot.groups.expand((MihomoProxyGroup item) => item.nodes)
                : group.nodes)
            .where(
              (String node) => !const <String>{
                'DIRECT',
                'REJECT',
                'REJECT-DROP',
                'PASS',
                'COMPATIBLE',
              }.contains(node.toUpperCase()),
            )
            .toSet()
            .toList(growable: false);
    if (nodes.isEmpty) return;
    final int generation = ++_delayTestGeneration;
    setState(() {
      _testingDelay = true;
      _testedNodes = 0;
      for (final String node in nodes) {
        _nodeDelays.remove(node);
      }
      _message = '正在测速 0/${nodes.length}；可随时关闭代理';
    });
    int cursor = 0;
    Future<void> worker() async {
      while (generation == _delayTestGeneration && cursor < nodes.length) {
        final String node = nodes[cursor++];
        int? delay;
        try {
          delay = await controller.testDelay(node);
        } on Object {
          delay = null;
        }
        if (!mounted || generation != _delayTestGeneration) return;
        setState(() {
          _nodeDelays[node] = delay;
          _testedNodes++;
          _message = '正在测速 $_testedNodes/${nodes.length}；可随时关闭代理';
        });
      }
    }

    await Future.wait<void>(
      List<Future<void>>.generate(nodes.length.clamp(1, 6), (_) => worker()),
    );
    if (!mounted || generation != _delayTestGeneration) return;
    final int available = nodes
        .where((String node) => _nodeDelays[node] != null)
        .length;
    setState(() {
      _testingDelay = false;
      _message = '测速完成：$available/${nodes.length} 个节点可用';
    });
  }

  Future<void> _toggleSystemProxy(bool enabled) async {
    final MihomoManagedConfig? config = _runningConfig;
    if (enabled && config == null) {
      await _confirmProxyStart();
      return;
    }
    await _run(() async {
      _systemProxy = enabled
          ? await _systemProxyService.applyLocal(
              port: config!.summary.mixedPort,
              dataDirectory: _proxyDataDirectory,
            )
          : await _systemProxyService.restore(
              dataDirectory: _proxyDataDirectory,
            );
    }, success: enabled ? '系统代理已启用' : '系统代理已关闭，Mihomo 继续运行');
  }

  Future<void> _stopProxyAndRestoreSystem() async {
    _delayTestGeneration++;
    _testingDelay = false;
    _dashboardTimer?.cancel();
    _systemProxy = await _systemProxyService.restore(
      dataDirectory: _proxyDataDirectory,
    );
    await NetworkVirtualizationService.stopMihomo();
    _runningConfig = null;
    _controllerSnapshot = null;
    _nodeDelays.clear();
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

  Future<void> _run(
    Future<void> Function() action, {
    String success = '操作完成',
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await action();
      if (mounted) setState(() => _message = success);
    } on Object catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      try {
        final List<String> activity = await _profileService.readActivityLog();
        if (mounted) setState(() => _subscriptionLog = activity);
      } on Object {
        // Logging must never keep an operation in the busy state.
      }
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

  Widget _proxyTab() => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final bool compact = constraints.maxWidth < 900;
      final Widget profiles = _profilePane(compact: compact);
      final Widget dashboard = _dashboard();
      return Column(
        children: <Widget>[
          _proxyToolbar(),
          if (_message.isNotEmpty)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Text(
                _message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Expanded(
            child: compact
                ? ListView(
                    padding: const EdgeInsets.all(12),
                    children: <Widget>[
                      profiles,
                      const SizedBox(height: 12),
                      dashboard,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(width: 310, child: profiles),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(14),
                          child: dashboard,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      );
    },
  );

  Widget _proxyToolbar() => Container(
    height: 58,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(
      children: <Widget>[
        Icon(
          _proxyRunning ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _proxyRunning
                ? '${_activeProfile?.name ?? 'Mihomo'} · 127.0.0.1:${_runningConfig?.summary.mixedPort ?? '-'}'
                : '代理未启动',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: '刷新状态',
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 4),
        if (_proxyRunning) ...<Widget>[
          OutlinedButton.icon(
            key: const Key('mihomo-test-all'),
            onPressed: _testingDelay ? null : _testDelays,
            icon: _testingDelay
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed),
            label: Text(_testingDelay ? '$_testedNodes 个' : '全部测速'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const Key('mihomo-stop'),
            onPressed: () =>
                _run(_stopProxyAndRestoreSystem, success: '代理已关闭，原网络已恢复'),
            icon: const Icon(Icons.power_settings_new),
            label: const Text('关闭代理'),
          ),
        ] else
          FilledButton.icon(
            key: const Key('mihomo-start'),
            onPressed: _busy || _mihomo?.available != true
                ? null
                : _confirmProxyStart,
            icon: const Icon(Icons.play_arrow),
            label: const Text('启动代理'),
          ),
      ],
    ),
  );

  Widget _profilePane({required bool compact}) => Container(
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                '订阅与配置',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: '添加订阅',
              onPressed: _busy ? null : _addSubscription,
              icon: const Icon(Icons.add_link),
            ),
            IconButton(
              tooltip: '导入 YAML',
              onPressed: _busy ? null : _pickConfig,
              icon: const Icon(Icons.file_open_outlined),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_profiles.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  const Icon(Icons.cloud_download_outlined, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    '添加订阅或导入 Clash YAML 后即可使用',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _addSubscription,
                    icon: const Icon(Icons.add),
                    label: const Text('添加订阅'),
                  ),
                ],
              ),
            ),
          )
        else if (compact)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _profiles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: _profileItem,
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: _profiles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: _profileItem,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          '数据目录：$_proxyDataDirectory',
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );

  Widget _profileItem(BuildContext context, int index) {
    final MihomoProfile profile = _profiles[index];
    final bool selected = profile.id == _activeProfile?.id;
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: ListTile(
        dense: true,
        selected: selected,
        onTap: () => _selectProfile(profile),
        leading: Icon(
          profile.subscription
              ? Icons.cloud_outlined
              : Icons.description_outlined,
        ),
        title: Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${profile.sourceHost} · ${profile.summary.proxyCount} 节点\n'
          '${profile.updatedAt.toString().substring(0, 16)}',
          maxLines: 2,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (String action) {
            if (action == 'update') unawaited(_updateProfile(profile));
            if (action == 'delete') unawaited(_deleteProfile(profile));
          },
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            if (profile.subscription)
              const PopupMenuItem(value: 'update', child: Text('立即更新')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }

  Widget _dashboard() {
    final MihomoControllerSnapshot? snapshot = _controllerSnapshot;
    final List<String> logs = <String>[
      ..._subscriptionLog,
      ...(NetworkVirtualizationService.status()['mihomoLog'] as List? ??
              const <Object>[])
          .map((Object? line) => '$line'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _runtimeCard(_mihomo),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _metricCard(
              '活动连接',
              '${snapshot?.connectionCount ?? 0}',
              Icons.link,
            ),
            _metricCard(
              '下载流量',
              _bytes(snapshot?.downloadTotal ?? 0),
              Icons.download,
            ),
            _metricCard(
              '上传流量',
              _bytes(snapshot?.uploadTotal ?? 0),
              Icons.upload,
            ),
            _metricCard(
              '当前节点',
              snapshot?.groups.firstOrNull?.selected ?? '未启动',
              Icons.public,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '网络设置',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    const Expanded(child: Text('系统代理')),
                    Switch(
                      key: const Key('mihomo-system-proxy-switch'),
                      value: _systemProxy?.enabled == true,
                      onChanged: _busy || !Platform.isWindows
                          ? null
                          : _toggleSystemProxy,
                    ),
                  ],
                ),
                Text(
                  _systemProxy?.enabled == true
                      ? '已启用 · ${_systemProxy?.server ?? ''}'
                      : '未启用；关闭时会恢复启动前的 Windows 设置',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                const Text('代理模式'),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  key: const Key('mihomo-mode-selector'),
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment(value: 'rule', label: Text('规则')),
                    ButtonSegment(value: 'global', label: Text('全局')),
                    ButtonSegment(value: 'direct', label: Text('直连')),
                  ],
                  selected: <String>{
                    snapshot?.mode ?? _activeProfile?.summary.mode ?? 'rule',
                  },
                  onSelectionChanged: !_proxyRunning || _busy
                      ? null
                      : (Set<String> value) => _setMode(value.first),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '代理组与节点',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (!_proxyRunning)
                  const Text('启动代理后可直接选择代理组和节点。')
                else if (snapshot == null)
                  const LinearProgressIndicator()
                else if (snapshot.groups.isEmpty)
                  const Text('当前配置没有可切换的代理组。')
                else
                  ...snapshot.groups.map(
                    (MihomoProxyGroup group) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey<String>(
                                'mihomo-group-${group.name}',
                              ),
                              initialValue: group.nodes.contains(group.selected)
                                  ? group.selected
                                  : group.nodes.first,
                              decoration: InputDecoration(
                                labelText: '${group.name} · ${group.type}',
                              ),
                              items: group.nodes
                                  .map(
                                    (String node) => DropdownMenuItem<String>(
                                      value: node,
                                      child: Text(
                                        _nodeLabel(node),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _busy
                                  ? null
                                  : (String? node) {
                                      if (node != null) {
                                        _selectNode(group, node);
                                      }
                                    },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            key: ValueKey<String>('mihomo-test-${group.name}'),
                            tooltip: '测试此组所有节点延迟',
                            onPressed: _testingDelay
                                ? null
                                : () => _testDelays(group: group),
                            icon: const Icon(Icons.speed),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ExpansionTile(
            initiallyExpanded: logs.isNotEmpty,
            title: Text('订阅与运行日志（${logs.length}）'),
            children: <Widget>[
              SizedBox(
                height: 180,
                width: double.infinity,
                child: logs.isEmpty
                    ? const Center(child: Text('暂无日志'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: logs.length,
                        itemBuilder: (_, int index) => SelectableText(
                          logs[index],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _nodeLabel(String node) {
    if (!_nodeDelays.containsKey(node)) return node;
    final int? delay = _nodeDelays[node];
    return delay == null ? '$node · 超时' : '$node · $delay ms';
  }

  Widget _metricCard(String label, String value, IconData icon) => SizedBox(
    width: 190,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

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

  Widget _vmTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Text('轻量虚拟机', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('内置 QEMU x86_64 运行时。选择已有磁盘或 ISO 后启动。'),
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

  Widget _pathField(String label, String value, VoidCallback pick) =>
      InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                value.isEmpty ? '未选择' : value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: '选择文件',
              onPressed: pick,
              icon: const Icon(Icons.folder_open_outlined),
            ),
          ],
        ),
      );

  static String _bytes(int value) {
    if (value >= 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
    }
    if (value >= 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
    }
    if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
    return '$value B';
  }
}
