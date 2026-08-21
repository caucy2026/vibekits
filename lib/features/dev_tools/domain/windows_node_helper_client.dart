import 'dart:convert';
import 'dart:io';

import 'windows_node_helper_protocol.dart';

enum WindowsNodeHelperFailure {
  missing,
  signatureInvalid,
  publisherMismatch,
  hashMismatch,
  protocolMismatch,
  uacDenied,
  cancelled,
  timeout,
  processFailed,
  receiptInvalid,
}

class WindowsNodeHelperException implements Exception {
  const WindowsNodeHelperException(this.failure, this.message);

  final WindowsNodeHelperFailure failure;
  final String message;

  @override
  String toString() => message;
}

class WindowsNodeHelperIdentity {
  const WindowsNodeHelperIdentity({
    required this.signatureValid,
    required this.publisher,
    required this.sha256,
    required this.fileVersion,
    required this.protocolVersion,
  });

  final bool signatureValid;
  final String publisher;
  final String sha256;
  final String fileVersion;
  final int protocolVersion;
}

class WindowsNodeHelperLaunchResult {
  const WindowsNodeHelperLaunchResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.uacDenied = false,
    this.cancelled = false,
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool uacDenied;
  final bool cancelled;
  final bool timedOut;
}

typedef WindowsNodeHelperIdentityInspector =
    Future<WindowsNodeHelperIdentity> Function(File helper);
typedef WindowsNodeHelperLauncher =
    Future<WindowsNodeHelperLaunchResult> Function(
      File helper,
      String requestJson,
    );

class WindowsNodeHelperClient {
  WindowsNodeHelperClient({
    required this.helper,
    required this.expectedPublisher,
    required this.expectedSha256,
    required this.inspectIdentity,
    required this.launch,
    DateTime Function()? clock,
    WindowsNodeHelperReplayGuard? replayGuard,
  }) : _clock = clock ?? DateTime.now,
       _replayGuard = replayGuard ?? WindowsNodeHelperReplayGuard();

  final File helper;
  final String expectedPublisher;
  final String expectedSha256;
  final WindowsNodeHelperIdentityInspector inspectIdentity;
  final WindowsNodeHelperLauncher launch;
  final DateTime Function() _clock;
  final WindowsNodeHelperReplayGuard _replayGuard;

  Future<WindowsNodeHelperIdentity> verifyBinary() async {
    if (!await helper.exists()) {
      throw const WindowsNodeHelperException(
        WindowsNodeHelperFailure.missing,
        '签名 Windows 节点 helper 不存在',
      );
    }
    final WindowsNodeHelperIdentity identity = await inspectIdentity(helper);
    if (!identity.signatureValid) {
      throw const WindowsNodeHelperException(
        WindowsNodeHelperFailure.signatureInvalid,
        'helper Authenticode 签名无效',
      );
    }
    if (identity.publisher.trim() != expectedPublisher.trim()) {
      throw const WindowsNodeHelperException(
        WindowsNodeHelperFailure.publisherMismatch,
        'helper 发布者与 Release 清单不一致',
      );
    }
    if (identity.sha256.toLowerCase() != expectedSha256.toLowerCase()) {
      throw const WindowsNodeHelperException(
        WindowsNodeHelperFailure.hashMismatch,
        'helper 文件哈希与 Release 清单不一致',
      );
    }
    if (identity.protocolVersion !=
        WindowsNodeHelperRequest.currentProtocolVersion) {
      throw const WindowsNodeHelperException(
        WindowsNodeHelperFailure.protocolMismatch,
        'helper 协议版本与 App 不一致',
      );
    }
    return identity;
  }

  Future<WindowsNodeHelperReceipt> execute(
    WindowsNodeHelperRequest request,
  ) async {
    await verifyBinary();
    _replayGuard.accept(request, now: _clock());
    final WindowsNodeHelperLaunchResult launched = await launch(
      helper,
      jsonEncode(request.toJson()),
    );
    if (launched.uacDenied) {
      throw const WindowsNodeHelperException(
        WindowsNodeHelperFailure.uacDenied,
        '用户拒绝 UAC，本次未执行系统变更',
      );
    }
    if (launched.cancelled) {
      throw const WindowsNodeHelperException(
        WindowsNodeHelperFailure.cancelled,
        'helper 操作已取消，需重新体检确认实际状态',
      );
    }
    if (launched.timedOut) {
      throw const WindowsNodeHelperException(
        WindowsNodeHelperFailure.timeout,
        'helper 执行超时，需重新体检确认部分成功状态',
      );
    }
    if (launched.exitCode != 0) {
      throw WindowsNodeHelperException(
        WindowsNodeHelperFailure.processFailed,
        _safeDetail(launched.stderr),
      );
    }
    try {
      final Object? decoded = jsonDecode(launched.stdout);
      if (decoded is! Map) throw const FormatException('回执不是 JSON 对象');
      final WindowsNodeHelperReceipt receipt =
          WindowsNodeHelperReceipt.fromJson(
            decoded.map(
              (dynamic key, dynamic value) =>
                  MapEntry<String, Object?>('$key', value),
            ),
          );
      WindowsNodeHelperProtocol.validateReceipt(request, receipt);
      return receipt;
    } on FormatException catch (error) {
      throw WindowsNodeHelperException(
        WindowsNodeHelperFailure.receiptInvalid,
        'helper 回执验证失败：${error.message}',
      );
    }
  }

  static String _safeDetail(String value) {
    final String detail = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return detail.isEmpty
        ? 'helper 进程失败且没有返回可审计原因'
        : detail.substring(0, detail.length > 400 ? 400 : detail.length);
  }
}
