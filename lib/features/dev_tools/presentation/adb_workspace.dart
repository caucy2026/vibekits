import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../domain/adb_service.dart';

typedef AdbWorkspaceLoader = Future<AdbSnapshot> Function();
typedef AdbWirelessConnector = Future<String> Function(
  String executable,
  String address,
);

class AdbWorkspace extends StatefulWidget {
  const AdbWorkspace({super.key, this.loadSnapshot, this.connectDevice});

  final AdbWorkspaceLoader? loadSnapshot;
  final AdbWirelessConnector? connectDevice;

  @override
  State<AdbWorkspace> createState() => _AdbWorkspaceState();
}

class _AdbWorkspaceState extends State<AdbWorkspace> {
  final TextEditingController _wirelessAddress = TextEditingController();
  AdbSnapshot? _snapshot;
  String? _selectedSerial;
  String? _error;
  bool _loading = false;
  bool _connecting = false;
  String? _connectionMessage;
  int _generation = 0;

  AdbDevice? get _selected => _snapshot?.devices
      .where((AdbDevice device) => device.serial == _selectedSerial)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final int generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AdbSnapshot snapshot =
          await (widget.loadSnapshot?.call() ?? AdbService.discoverAndList());
      if (!mounted || generation != _generation) return;
      final bool selectionExists = snapshot.devices.any(
        (AdbDevice device) => device.serial == _selectedSerial,
      );
      setState(() {
        _snapshot = snapshot;
        _selectedSerial = selectionExists
            ? _selectedSerial
            : snapshot.devices
                  .where((AdbDevice device) => device.ready)
                  .firstOrNull
                  ?.serial;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _connect() async {
    final AdbInstallation? installation = _snapshot?.installation;
    if (installation == null || _connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
      _connectionMessage = null;
    });
    try {
      final String message =
          await (widget.connectDevice?.call(
                installation.executable,
                _wirelessAddress.text,
              ) ??
              AdbService.connect(
                installation.executable,
                _wirelessAddress.text,
              ));
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connectionMessage = message;
      });
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  void dispose() {
    _generation += 1;
    _wirelessAddress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AdbInstallation? installation = _snapshot?.installation;
    final List<AdbDevice> devices = _snapshot?.devices ?? const <AdbDevice>[];
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.android_rounded, size: 22),
              const SizedBox(width: 8),
              const Text(
                'ADB 设备',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const Key('adb-refresh'),
                onPressed: _loading ? null : _refresh,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(_loading ? '刷新中' : '刷新设备'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.vibe.canvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.vibe.border),
            ),
            child: installation == null
                ? Text(
                    _loading ? '正在查找 Android SDK Platform-Tools…' : '尚未识别 ADB',
                    style: TextStyle(color: context.vibe.muted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('ADB ${installation.version}'),
                      const SizedBox(height: 3),
                      SelectableText(
                        installation.executable,
                        key: const Key('adb-executable-path'),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.vibe.muted,
                        ),
                      ),
                    ],
                  ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const Key('adb-error'),
              style: const TextStyle(color: VibekitsColors.danger),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('adb-wireless-address'),
                  controller: _wirelessAddress,
                  enabled: installation != null && !_connecting,
                  onSubmitted: (_) => _connect(),
                  decoration: const InputDecoration(
                    labelText: '无线设备',
                    hintText: '192.168.3.63（默认端口 5555）',
                    prefixIcon: Icon(Icons.wifi_rounded, size: 19),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('adb-connect'),
                onPressed: installation == null || _connecting
                    ? null
                    : _connect,
                icon: _connecting
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link_rounded, size: 18),
                label: Text(_connecting ? '连接中' : '连接'),
              ),
            ],
          ),
          if (_connectionMessage != null) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              _connectionMessage!,
              key: const Key('adb-connect-result'),
              style: TextStyle(fontSize: 12, color: context.vibe.success),
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  flex: 4,
                  child: Container(
                    key: const Key('adb-device-list'),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.vibe.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: devices.isEmpty
                        ? Center(
                            child: Text(
                              _loading ? '正在读取设备…' : '没有检测到设备',
                              style: TextStyle(color: context.vibe.muted),
                            ),
                          )
                        : ListView.separated(
                            itemCount: devices.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (BuildContext context, int index) {
                              final AdbDevice device = devices[index];
                              return ListTile(
                                key: Key('adb-device-${device.serial}'),
                                selected: device.serial == _selectedSerial,
                                leading: Icon(
                                  Icons.phone_android_rounded,
                                  color: device.ready
                                      ? context.vibe.success
                                      : context.vibe.muted,
                                ),
                                title: Text(device.model ?? device.serial),
                                subtitle: Text(device.serial),
                                trailing: _StateBadge(state: device.state),
                                onTap: () => setState(
                                  () => _selectedSerial = device.serial,
                                ),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: Container(
                    key: const Key('adb-device-detail'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.vibe.canvas,
                      border: Border.all(color: context.vibe.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _selected == null
                        ? Center(
                            child: Text(
                              '选择一个设备',
                              style: TextStyle(color: context.vibe.muted),
                            ),
                          )
                        : _DeviceSummary(device: _selected!),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceSummary extends StatelessWidget {
  const _DeviceSummary({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        device.model ?? device.serial,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      SelectableText(device.serial),
      const SizedBox(height: 10),
      Text(
        device.ready
            ? '设备已授权，可以继续使用 Shell、文件、日志和截图。'
            : _stateHelp(device.state),
        style: TextStyle(
          color: device.ready ? context.vibe.success : context.vibe.muted,
        ),
      ),
    ],
  );
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final AdbDeviceState state;

  @override
  Widget build(BuildContext context) => Text(
    _stateLabel(state),
    key: Key('adb-state-${state.name}'),
    style: TextStyle(
      fontSize: 11,
      color: state == AdbDeviceState.device
          ? context.vibe.success
          : state == AdbDeviceState.unauthorized
          ? VibekitsColors.warning
          : context.vibe.muted,
    ),
  );
}

String _stateLabel(AdbDeviceState state) => switch (state) {
  AdbDeviceState.device => '可用',
  AdbDeviceState.unauthorized => '未授权',
  AdbDeviceState.offline => '离线',
  AdbDeviceState.unknown => '未知',
};

String _stateHelp(AdbDeviceState state) => switch (state) {
  AdbDeviceState.device => '设备可用',
  AdbDeviceState.unauthorized => '请解锁设备并确认 USB 调试授权。',
  AdbDeviceState.offline => '设备离线；请重新连接 USB 或无线调试。',
  AdbDeviceState.unknown => '设备状态未知，请刷新或重启 ADB 服务。',
};
