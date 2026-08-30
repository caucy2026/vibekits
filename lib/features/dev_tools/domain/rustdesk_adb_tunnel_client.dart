import 'dart:convert';
import 'dart:io';

import 'adb_server_endpoint.dart';

typedef RustDeskAdbTunnelProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

enum RustDeskAdbTunnelState { starting, ready, closed, failed }

class RustDeskAdbTunnelStatus {
  const RustDeskAdbTunnelStatus({
    required this.state,
    required this.leaseId,
    required this.peerId,
    this.host = '',
    this.port = 0,
  });

  final RustDeskAdbTunnelState state;
  final String leaseId;
  final String peerId;
  final String host;
  final int port;
}

class RustDeskAdbTunnelException implements Exception {
  const RustDeskAdbTunnelException({
    required this.code,
    required this.message,
    required this.exitCode,
  });

  final String code;
  final String message;
  final int exitCode;

  @override
  String toString() => '[$code] $message';
}

abstract interface class RustDeskAdbTunnelClient {
  Future<AdbServerEndpoint> open({
    required String rustDeskExecutable,
    required String peerId,
    String sessionId = '',
  });

  Future<void> close({
    required String rustDeskExecutable,
    required String leaseId,
  });

  Future<RustDeskAdbTunnelStatus> status({
    required String rustDeskExecutable,
    required String leaseId,
  });

  Future<RustDeskAdbTunnelStatus> heartbeat({
    required String rustDeskExecutable,
    required String leaseId,
  });
}

/// CLI adapter for the same-user RustDesk ADB tunnel control contract.
///
/// Command names are intentionally isolated here. The ADB service only knows
/// about [AdbServerEndpoint], so the transport can later move to local IPC
/// without changing command execution or UI code.
class RustDeskCliAdbTunnelClient implements RustDeskAdbTunnelClient {
  RustDeskCliAdbTunnelClient({RustDeskAdbTunnelProcessRunner? processRunner})
    : _processRunner = processRunner ?? _runProcess;

  static const String openCommand = '--vibekits-adb-tunnel-open';
  static const String closeCommand = '--vibekits-adb-tunnel-close';
  static const String statusCommand = '--vibekits-adb-tunnel-status';
  static const String heartbeatCommand = '--vibekits-adb-tunnel-heartbeat';

  final RustDeskAdbTunnelProcessRunner _processRunner;

  @override
  Future<AdbServerEndpoint> open({
    required String rustDeskExecutable,
    required String peerId,
    String sessionId = '',
  }) async {
    final String executable = _validatedExecutable(rustDeskExecutable);
    final String normalizedPeerId = peerId.trim();
    final String normalizedSessionId = sessionId.trim();
    if (normalizedPeerId.isEmpty) {
      throw const FormatException('缺少 RustDesk 远端设备 ID');
    }
    if (normalizedSessionId.isNotEmpty &&
        !_uuidPattern.hasMatch(normalizedSessionId)) {
      throw const FormatException('RustDesk sessionId 必须是 UUID');
    }
    final List<String> arguments = <String>[
      openCommand,
      '--peer-id',
      normalizedPeerId,
      if (normalizedSessionId.isNotEmpty) ...<String>[
        '--session-id',
        normalizedSessionId,
      ],
    ];
    final Map<String, Object?> response = await _invoke(
      executable,
      arguments,
      operation: '打开远端 ADB 隧道',
      expectedOperation: 'open',
    );
    final String host = (response['host'] ?? '').toString();
    final int? port = switch (response['port']) {
      final int value => value,
      final num value => value.toInt(),
      final Object value => int.tryParse(value.toString()),
      null => null,
    };
    return AdbServerEndpoint.rustDesk(
      host: host,
      port: port ?? 0,
      peerId: (response['peerId'] ?? normalizedPeerId).toString(),
      sessionId: (response['sessionId'] ?? normalizedSessionId).toString(),
      leaseId: (response['leaseId'] ?? '').toString(),
    );
  }

  @override
  Future<void> close({
    required String rustDeskExecutable,
    required String leaseId,
  }) async {
    final String executable = _validatedExecutable(rustDeskExecutable);
    final String normalizedLeaseId = leaseId.trim();
    if (normalizedLeaseId.isEmpty) return;
    await _invoke(
      executable,
      <String>[closeCommand, '--lease-id', normalizedLeaseId],
      operation: '关闭远端 ADB 隧道',
      expectedOperation: 'close',
    );
  }

  @override
  Future<RustDeskAdbTunnelStatus> status({
    required String rustDeskExecutable,
    required String leaseId,
  }) async {
    final String executable = _validatedExecutable(rustDeskExecutable);
    final String normalizedLeaseId = leaseId.trim();
    if (normalizedLeaseId.isEmpty) {
      throw const FormatException('缺少 RustDesk ADB 隧道租约');
    }
    final Map<String, Object?> response = await _invoke(
      executable,
      <String>[statusCommand, '--lease-id', normalizedLeaseId],
      operation: '查询远端 ADB 隧道',
      expectedOperation: 'status',
    );
    return _statusFromResponse(response, normalizedLeaseId);
  }

  @override
  Future<RustDeskAdbTunnelStatus> heartbeat({
    required String rustDeskExecutable,
    required String leaseId,
  }) async {
    final String executable = _validatedExecutable(rustDeskExecutable);
    final String normalizedLeaseId = leaseId.trim();
    if (normalizedLeaseId.isEmpty) {
      throw const FormatException('缺少 RustDesk ADB 隧道租约');
    }
    final Map<String, Object?> response = await _invoke(
      executable,
      <String>[heartbeatCommand, '--lease-id', normalizedLeaseId],
      operation: '续租远端 ADB 隧道',
      expectedOperation: 'heartbeat',
    );
    return _statusFromResponse(response, normalizedLeaseId);
  }

  static RustDeskAdbTunnelStatus _statusFromResponse(
    Map<String, Object?> response,
    String leaseId,
  ) {
    final String rawState = (response['state'] ?? '').toString();
    RustDeskAdbTunnelState? state;
    for (final RustDeskAdbTunnelState candidate
        in RustDeskAdbTunnelState.values) {
      if (candidate.name == rawState) {
        state = candidate;
        break;
      }
    }
    if (state == null) {
      throw const RustDeskAdbTunnelException(
        code: 'invalid_response',
        message: '查询远端 ADB 隧道失败：RustDesk 返回了无效状态',
        exitCode: 0,
      );
    }
    return RustDeskAdbTunnelStatus(
      state: state,
      leaseId: (response['leaseId'] ?? leaseId).toString(),
      peerId: (response['peerId'] ?? '').toString(),
      host: (response['host'] ?? '').toString(),
      port: _integer(response['port']) ?? 0,
    );
  }

  Future<Map<String, Object?>> _invoke(
    String executable,
    List<String> arguments, {
    required String operation,
    required String expectedOperation,
  }) async {
    final ProcessResult result = await _processRunner(
      executable,
      arguments,
    ).timeout(const Duration(seconds: 15));
    final String stdout = result.stdout.toString().trim();
    final String stderr = result.stderr.toString().trim();
    Object? decoded;
    try {
      decoded = jsonDecode(stdout);
    } on FormatException {
      throw RustDeskAdbTunnelException(
        code: 'invalid_response',
        message: result.exitCode == 0
            ? '$operation失败：RustDesk 返回了无效 JSON'
            : (stderr.isEmpty
                  ? '$operation失败（exit ${result.exitCode}）'
                  : '$operation失败：$stderr'),
        exitCode: result.exitCode,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw RustDeskAdbTunnelException(
        code: 'invalid_response',
        message: '$operation失败：RustDesk 返回了无效 JSON 对象',
        exitCode: result.exitCode,
      );
    }
    if (decoded['schemaVersion'] != 1 ||
        decoded['operation'] != expectedOperation) {
      throw RustDeskAdbTunnelException(
        code: 'invalid_response',
        message: '$operation失败：RustDesk 返回了不兼容的响应协议',
        exitCode: result.exitCode,
      );
    }
    if (result.exitCode != 0 || decoded['ok'] != true) {
      final String code = (decoded['code'] ?? 'internal_error').toString();
      final String message = (decoded['message'] ?? '').toString().trim();
      throw RustDeskAdbTunnelException(
        code: code,
        message: message.isEmpty
            ? '$operation失败（$code）'
            : '$operation失败：$message',
        exitCode: result.exitCode,
      );
    }
    return decoded;
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static int? _integer(Object? value) => switch (value) {
    final int number => number,
    final num number => number.toInt(),
    final Object other => int.tryParse(other.toString()),
    null => null,
  };

  static String _validatedExecutable(String value) {
    final String executable = value.trim();
    if (executable.isEmpty) throw const FormatException('缺少 RustDesk 可执行文件');
    return executable;
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) => Process.run(executable, arguments, runInShell: false);
}

/// Owns one RustDesk ADB tunnel lease and guarantees explicit close/replace.
class RustDeskAdbTunnelProvider {
  RustDeskAdbTunnelProvider({
    required this.rustDeskExecutable,
    RustDeskAdbTunnelClient? client,
  }) : _client = client ?? RustDeskCliAdbTunnelClient();

  final String rustDeskExecutable;
  final RustDeskAdbTunnelClient _client;
  AdbServerEndpoint? _endpoint;

  AdbServerEndpoint? get endpoint => _endpoint;

  Future<AdbServerEndpoint> open({
    required String peerId,
    String sessionId = '',
  }) async {
    await close();
    final AdbServerEndpoint opened = await _client.open(
      rustDeskExecutable: rustDeskExecutable,
      peerId: peerId,
      sessionId: sessionId,
    );
    _endpoint = opened;
    return opened;
  }

  Future<void> close() async {
    final AdbServerEndpoint? current = _endpoint;
    if (current == null || current.leaseId.isEmpty) return;
    await _client.close(
      rustDeskExecutable: rustDeskExecutable,
      leaseId: current.leaseId,
    );
    if (identical(_endpoint, current)) _endpoint = null;
  }

  Future<RustDeskAdbTunnelStatus?> status() async {
    final AdbServerEndpoint? current = _endpoint;
    if (current == null) return null;
    return _client.status(
      rustDeskExecutable: rustDeskExecutable,
      leaseId: current.leaseId,
    );
  }

  Future<RustDeskAdbTunnelStatus?> heartbeat() async {
    final AdbServerEndpoint? current = _endpoint;
    if (current == null) return null;
    return _client.heartbeat(
      rustDeskExecutable: rustDeskExecutable,
      leaseId: current.leaseId,
    );
  }

  void invalidateLease(String leaseId) {
    final AdbServerEndpoint? current = _endpoint;
    if (current != null && current.leaseId == leaseId) _endpoint = null;
  }

  Future<void> dispose() => close();
}
