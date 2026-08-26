import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../domain/packet_capture_service.dart';

class PacketCaptureWorkspace extends StatefulWidget {
  const PacketCaptureWorkspace({super.key, this.service});

  final PacketCaptureService? service;

  @override
  State<PacketCaptureWorkspace> createState() => _PacketCaptureWorkspaceState();
}

class _PacketCaptureWorkspaceState extends State<PacketCaptureWorkspace> {
  late final PacketCaptureService _service =
      widget.service ?? PacketCaptureService.instance;
  final TextEditingController _filterController = TextEditingController(
    text: 'true',
  );
  final List<CapturedPacket> _packets = <CapturedPacket>[];
  StreamSubscription<CapturedPacket>? _subscription;
  PacketCaptureSummary? _summary;
  String? _outputPath;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _subscription = _service.packets.listen((CapturedPacket packet) {
      if (!mounted) return;
      setState(() {
        _packets.insert(0, packet);
        if (_packets.length > 2000) _packets.removeLast();
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _message = null;
      _packets.clear();
      _summary = null;
    });
    try {
      final String path = await _service.defaultOutputPath();
      await _service.start(outputPath: path, filter: _filterController.text);
      if (mounted) {
        setState(() {
          _outputPath = path;
          _message = '正在抓包，数据实时写入 PCAP';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    await _service.stop();
    final String? path = _outputPath;
    if (path != null && await File(path).exists()) {
      _summary = await _service.read(path);
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _message = _service.lastError ?? '抓包已停止并保存';
      });
    }
  }

  Future<void> _open() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'PCAP 抓包文件', extensions: <String>['pcap', 'cap']),
      ],
    );
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final PacketCaptureSummary summary = await _service.read(file.path);
      if (mounted) {
        setState(() {
          _summary = summary;
          _outputPath = file.path;
          _packets
            ..clear()
            ..addAll(summary.packets.reversed);
          _message = '已读取 ${summary.packets.length} 个数据包';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAs() async {
    final String? source = _outputPath;
    if (source == null || !await File(source).exists()) return;
    final FileSaveLocation? location = await getSaveLocation(
      suggestedName: File(source).uri.pathSegments.last,
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'PCAP 抓包文件', extensions: <String>['pcap']),
      ],
    );
    if (location == null) return;
    await File(source).copy(location.path);
    if (mounted) setState(() => _message = '已另存为 ${location.path}');
  }

  @override
  Widget build(BuildContext context) {
    final bool capturing = _service.isCapturing;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const Key('packet-capture-filter'),
                      controller: _filterController,
                      enabled: !capturing,
                      decoration: const InputDecoration(
                        labelText: '抓包过滤器',
                        hintText: 'true / tcp / udp / tcp.DstPort == 443',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('packet-capture-toggle'),
                    onPressed: _busy ? null : (capturing ? _stop : _start),
                    icon: Icon(
                      capturing
                          ? Icons.stop_rounded
                          : Icons.fiber_manual_record,
                      size: 18,
                    ),
                    label: Text(capturing ? '停止并保存' : '开始抓包'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: capturing || _busy ? null : _open,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('读取 PCAP'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: capturing || _outputPath == null
                        ? null
                        : _saveAs,
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: const Text('另存为'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  for (final MapEntry<String, String> preset
                      in const <String, String>{
                        '全部': 'true',
                        'TCP': 'tcp',
                        'UDP': 'udp',
                        'DNS': 'udp.DstPort == 53 or udp.SrcPort == 53',
                        'HTTPS': 'tcp.DstPort == 443 or tcp.SrcPort == 443',
                      }.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(preset.key),
                        onPressed: capturing
                            ? null
                            : () => _filterController.text = preset.value,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '${_packets.length} 包',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              if (_outputPath != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    '文件：$_outputPath',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (_message != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _message!,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          _message!.contains('失败') || _message!.contains('错误')
                          ? Colors.red
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_summary != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Text(
              '分析：${_summary!.packets.length} 包 · ${_summary!.packetBytes} B · '
              '${_summary!.protocolCounts.entries.map((e) => '${e.key} ${e.value}').join(' · ')}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        Expanded(
          child: _packets.isEmpty
              ? Center(
                  child: Text(
                    _busy ? '正在准备抓包内核…' : '开始抓包或打开已有 PCAP 文件\n实时列表不会阻塞其他工具',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  key: const Key('packet-capture-list'),
                  itemCount: _packets.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final CapturedPacket packet = _packets[index];
                    return ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -3),
                      leading: SizedBox(
                        width: 46,
                        child: Text(
                          packet.protocol,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      title: Text(
                        '${packet.source}  →  ${packet.destination}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(
                        '${packet.timestamp.toLocal()} · ${packet.direction} · 接口 ${packet.interfaceIndex}',
                        style: const TextStyle(fontSize: 10.5),
                      ),
                      trailing: Text(
                        '${packet.length} B',
                        style: const TextStyle(fontSize: 11),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
