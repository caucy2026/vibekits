import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../domain/api_request_service.dart';

typedef ApiExecutor = Future<ApiResponseData> Function(
  ApiRequestSpec spec,
  ApiRequestCancellation cancellation,
);

class ApiRequestHistoryEntry {
  const ApiRequestHistoryEntry({
    required this.method,
    required this.url,
    required this.headers,
    required this.lastUsedEpochMs,
  });

  final String method;
  final String url;
  final Map<String, String> headers;
  final int lastUsedEpochMs;

  String get label => '$method $url';

  String encode() => jsonEncode(<String, Object>{
    'version': 1,
    'method': method,
    'url': url,
    'headers': headers,
    'lastUsedEpochMs': lastUsedEpochMs,
  });

  static ApiRequestHistoryEntry? decode(String source) {
    try {
      final Object? decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?>) return null;
      final String method = '${decoded['method'] ?? ''}'.toUpperCase();
      final String url = '${decoded['url'] ?? ''}'.trim();
      final Uri? uri = Uri.tryParse(url);
      if (!const <String>{
            'GET',
            'POST',
            'PUT',
            'PATCH',
            'DELETE',
            'HEAD',
            'OPTIONS',
          }.contains(method) ||
          uri == null ||
          !uri.isAbsolute ||
          url.length > 4096) {
        return null;
      }
      final Map<String, String> headers = <String, String>{};
      if (decoded['headers'] is Map) {
        for (final MapEntry<Object?, Object?> item
            in (decoded['headers']! as Map).entries) {
          final String name = '${item.key}'.trim();
          final String value = '${item.value}'.trim();
          if (name.isNotEmpty && name.length <= 128 && value.length <= 2048) {
            headers[name] = value;
          }
        }
      }
      return ApiRequestHistoryEntry(
        method: method,
        url: url,
        headers: headers,
        lastUsedEpochMs: decoded['lastUsedEpochMs'] is int
            ? decoded['lastUsedEpochMs']! as int
            : 0,
      );
    } on Object {
      return null;
    }
  }
}

class ApiWorkspace extends StatefulWidget {
  const ApiWorkspace({
    super.key,
    this.execute,
    this.initialHistory = const <String>[],
    this.onHistoryChanged,
  });

  final ApiExecutor? execute;
  final List<String> initialHistory;
  final Future<void> Function(List<String> history)? onHistoryChanged;

  @override
  State<ApiWorkspace> createState() => _ApiWorkspaceState();
}

class _ApiWorkspaceState extends State<ApiWorkspace> {
  final TextEditingController _url = TextEditingController(
    text: 'https://api.github.com/',
  );
  final TextEditingController _headers = TextEditingController(
    text: 'Accept: application/json\nUser-Agent: Vibekits',
  );
  final TextEditingController _body = TextEditingController();
  final TextEditingController _timeout = TextEditingController(text: '15');
  final TextEditingController _maxMb = TextEditingController(text: '5');
  String _method = 'GET';
  ApiRequestCancellation? _cancellation;
  ApiResponseData? _response;
  String? _error;
  bool _sending = false;
  late final List<ApiRequestHistoryEntry> _history =
      widget.initialHistory.map(ApiRequestHistoryEntry.decode).nonNulls.toList()
        ..sort(
          (ApiRequestHistoryEntry a, ApiRequestHistoryEntry b) =>
              b.lastUsedEpochMs.compareTo(a.lastUsedEpochMs),
        );

  static bool _sensitiveHeader(String name) {
    final String normalized = name.trim().toLowerCase();
    return normalized == 'authorization' ||
        normalized == 'proxy-authorization' ||
        normalized == 'cookie' ||
        normalized == 'set-cookie' ||
        normalized == 'x-api-key' ||
        normalized.contains('token') ||
        normalized.contains('secret');
  }

  Future<void> _remember(ApiRequestSpec spec) async {
    final Map<String, String> safeHeaders = <String, String>{
      for (final MapEntry<String, String> item in spec.headers.entries)
        if (!_sensitiveHeader(item.key)) item.key: item.value,
    };
    final ApiRequestHistoryEntry entry = ApiRequestHistoryEntry(
      method: spec.method,
      url: spec.url.trim(),
      headers: safeHeaders,
      lastUsedEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    _history.removeWhere(
      (ApiRequestHistoryEntry item) =>
          item.method == entry.method && item.url == entry.url,
    );
    _history.insert(0, entry);
    if (_history.length > 30) _history.removeRange(30, _history.length);
    await widget.onHistoryChanged?.call(
      _history.map((ApiRequestHistoryEntry item) => item.encode()).toList(),
    );
  }

  void _restore(ApiRequestHistoryEntry entry) {
    setState(() {
      _method = entry.method;
      _url.text = entry.url;
      _headers.text = entry.headers.entries
          .map((MapEntry<String, String> item) => '${item.key}: ${item.value}')
          .join('\n');
      _body.clear();
      _response = null;
      _error = null;
    });
  }

  Future<void> _clearHistory() async {
    setState(_history.clear);
    await widget.onHistoryChanged?.call(const <String>[]);
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    _url.dispose();
    _headers.dispose();
    _body.dispose();
    _timeout.dispose();
    _maxMb.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final ApiRequestCancellation cancellation = ApiRequestCancellation();
    setState(() {
      _sending = true;
      _cancellation = cancellation;
      _response = null;
      _error = null;
    });
    try {
      final ApiRequestSpec spec = ApiRequestSpec(
        method: _method,
        url: _url.text,
        headers: _parseHeaders(_headers.text),
        body: _body.text,
        timeout: Duration(seconds: int.tryParse(_timeout.text) ?? 0),
        maxResponseBytes: ((double.tryParse(_maxMb.text) ?? 0) * 1024 * 1024)
            .round(),
      );
      final ApiResponseData response = await (widget.execute != null
          ? widget.execute!(spec, cancellation)
          : ApiRequestService.execute(spec, cancellation: cancellation));
      if (!mounted || cancellation.isCancelled) return;
      await _remember(spec);
      if (!mounted || cancellation.isCancelled) return;
      setState(() {
        _sending = false;
        _cancellation = null;
        _response = response;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _cancellation = null;
        _error = error is FormatException
            ? error.message
            : error is ApiRequestCancelled
            ? '请求已取消'
            : '请求失败：$error';
      });
    }
  }

  void _cancel() {
    _cancellation?.cancel();
    setState(() {
      _sending = false;
      _cancellation = null;
      _error = '请求已取消';
    });
  }

  Future<void> _copyResponse() async {
    final ApiResponseData? response = _response;
    if (response == null) return;
    await Clipboard.setData(ClipboardData(text: response.body));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('响应体已复制')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              const Icon(Icons.api_outlined, size: 21),
              const Text(
                'API 调试',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              _ApiBadge(text: 'TLS 校验开启', color: context.vibe.success),
              Text(
                '本地发送 · 敏感头不记历史',
                style: TextStyle(fontSize: 11, color: context.vibe.muted),
              ),
              if (_history.isNotEmpty)
                PopupMenuButton<Object>(
                  key: const Key('api-history'),
                  tooltip: '最近请求',
                  onSelected: (Object value) {
                    if (value == 'clear') {
                      _clearHistory();
                    } else if (value is ApiRequestHistoryEntry) {
                      _restore(value);
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<Object>>[
                        for (final ApiRequestHistoryEntry item in _history)
                          PopupMenuItem<Object>(
                            value: item,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        const PopupMenuDivider(),
                        const PopupMenuItem<Object>(
                          value: 'clear',
                          child: Text('清空最近请求'),
                        ),
                      ],
                  child: const Chip(
                    avatar: Icon(Icons.history_rounded, size: 17),
                    label: Text('最近请求'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  key: const Key('api-method'),
                  isExpanded: true,
                  initialValue: _method,
                  decoration: const InputDecoration(
                    labelText: '方法',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items:
                      const <String>[
                            'GET',
                            'POST',
                            'PUT',
                            'PATCH',
                            'DELETE',
                            'HEAD',
                            'OPTIONS',
                          ]
                          .map(
                            (String value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(growable: false),
                  onChanged: _sending
                      ? null
                      : (String? value) {
                          if (value != null) setState(() => _method = value);
                        },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const Key('api-url'),
                  controller: _url,
                  enabled: !_sending,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const Key('api-primary-action'),
                onPressed: _sending ? _cancel : _send,
                icon: Icon(
                  _sending ? Icons.stop_rounded : Icons.send_outlined,
                  size: 18,
                ),
                label: Text(_sending ? '取消' : '发送'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            flex: 2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('api-headers'),
                    controller: _headers,
                    enabled: !_sending,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontFamily: 'Cascadia Mono',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      labelText: '请求头（每行 Name: Value）',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('api-body'),
                    controller: _body,
                    enabled: !_sending && _method != 'GET' && _method != 'HEAD',
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontFamily: 'Cascadia Mono',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      labelText: '请求体（UTF-8）',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _timeout,
                  enabled: !_sending,
                  decoration: const InputDecoration(
                    labelText: '超时（秒）',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _maxMb,
                  enabled: !_sending,
                  decoration: const InputDecoration(
                    labelText: '响应上限（MiB）',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Text(
                '最多 5 次重定向 · 不允许忽略证书错误',
                style: TextStyle(fontSize: 11, color: context.vibe.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_sending) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                _error!,
                key: const Key('api-error'),
                style: const TextStyle(
                  color: VibekitsColors.danger,
                  fontSize: 12,
                ),
              ),
            ),
          Expanded(flex: 3, child: _buildResponse()),
        ],
      ),
    );
  }

  Widget _buildResponse() {
    final ApiResponseData? response = _response;
    if (response == null) {
      return Center(
        child: Text(
          '响应状态、头和正文会显示在这里。',
          style: TextStyle(color: context.vibe.muted),
        ),
      );
    }
    final String headerText = response.headers.entries
        .map(
          (MapEntry<String, List<String>> item) =>
              '${item.key}: ${item.value.join(', ')}',
        )
        .join('\n');
    return Container(
      key: const Key('api-response'),
      decoration: BoxDecoration(
        color: context.vibe.canvas,
        border: Border.all(color: context.vibe.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
            child: Row(
              children: <Widget>[
                Text(
                  '${response.statusCode} ${response.reasonPhrase}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${response.elapsed.inMilliseconds} ms · ${response.bodyBytes} B · ${response.finalUrl}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.vibe.muted),
                  ),
                ),
                IconButton(
                  tooltip: '复制响应体',
                  onPressed: _copyResponse,
                  icon: const Icon(Icons.copy_outlined, size: 17),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                '$headerText\n\n${response.body}',
                style: const TextStyle(
                  fontFamily: 'Cascadia Mono',
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, String> _parseHeaders(String source) {
  final Map<String, String> headers = <String, String>{};
  for (final String rawLine in const LineSplitter().convert(source)) {
    final String line = rawLine.trim();
    if (line.isEmpty) continue;
    final int colon = line.indexOf(':');
    if (colon <= 0) {
      throw FormatException('请求头格式错误：$rawLine');
    }
    headers[line.substring(0, colon).trim()] = line.substring(colon + 1).trim();
  }
  return headers;
}

class _ApiBadge extends StatelessWidget {
  const _ApiBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}
