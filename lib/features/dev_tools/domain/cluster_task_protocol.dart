import 'cluster_task_settings.dart';

enum ClusterDeviceAgentPhase {
  disabled,
  starting,
  registered,
  streaming,
  degraded,
}

enum ClusterTaskPhase {
  discovered,
  validating,
  available,
  claimed,
  parsing,
  running,
  waitingApproval,
  completed,
  failed,
  cancelled,
  expired,
  rejected,
}

typedef ClusterTaskSignatureVerifier =
    Future<bool> Function(
      ClusterTaskEnvelope envelope,
      String signingPublicKey,
    );

/// Signed pointer to a task description. The envelope cannot carry executable
/// commands; the local Harness reads the validated URL and plans through its
/// normal tool approval and audit pipeline.
final class ClusterTaskEnvelope {
  const ClusterTaskEnvelope({
    required this.taskId,
    required this.version,
    required this.descriptionUrl,
    required this.issuedAt,
    required this.expiresAt,
    required this.signature,
    this.requiredCapabilities = const <String>[],
  });

  factory ClusterTaskEnvelope.fromJson(Map<String, Object?> json) {
    String requiredText(String key) {
      final value = json[key]?.toString().trim() ?? '';
      if (value.isEmpty) throw FormatException('任务信封缺少 $key');
      return value;
    }

    DateTime requiredTime(String key) {
      final value = DateTime.tryParse(requiredText(key))?.toUtc();
      if (value == null) throw FormatException('任务信封 $key 不是 ISO-8601 时间');
      return value;
    }

    final rawCapabilities = json['requiredCapabilities'];
    if (rawCapabilities != null && rawCapabilities is! List) {
      throw const FormatException('requiredCapabilities 必须是数组');
    }
    return ClusterTaskEnvelope(
      taskId: requiredText('taskId'),
      version: requiredText('version'),
      descriptionUrl: Uri.parse(requiredText('descriptionUrl')),
      issuedAt: requiredTime('issuedAt'),
      expiresAt: requiredTime('expiresAt'),
      signature: requiredText('signature'),
      requiredCapabilities: <String>[
        for (final item in (rawCapabilities as List? ?? const <Object?>[]))
          if (item.toString().trim().isNotEmpty) item.toString().trim(),
      ],
    );
  }

  final String taskId;
  final String version;
  final Uri descriptionUrl;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String signature;
  final List<String> requiredCapabilities;

  String get deduplicationKey => '$taskId@$version';

  Map<String, Object?> signingPayload() => <String, Object?>{
    'taskId': taskId,
    'version': version,
    'descriptionUrl': descriptionUrl.toString(),
    'issuedAt': issuedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'requiredCapabilities': requiredCapabilities,
  };
}

final class ClusterTaskEnvelopeValidator {
  const ClusterTaskEnvelopeValidator({required this.verifySignature});

  final ClusterTaskSignatureVerifier verifySignature;

  Future<ClusterTaskEnvelope> validate({
    required ClusterTaskEnvelope envelope,
    required ClusterTaskConfiguration configuration,
    DateTime? now,
  }) async {
    if (!configuration.configured) {
      throw StateError('CLUSTER_TASK_SERVICE_UNCONFIGURED');
    }
    final url = envelope.descriptionUrl;
    if (url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.fragment.isNotEmpty) {
      throw const FormatException('任务描述必须是无账号、无片段的 HTTPS URL');
    }
    final host = url.host.toLowerCase();
    if (!configuration.trustedHosts.contains(host)) {
      throw StateError('CLUSTER_TASK_UNTRUSTED_HOST:$host');
    }
    final instant = (now ?? DateTime.now()).toUtc();
    if (!envelope.expiresAt.isAfter(instant)) {
      throw StateError('CLUSTER_TASK_EXPIRED');
    }
    if (envelope.issuedAt.isAfter(instant.add(const Duration(minutes: 5)))) {
      throw StateError('CLUSTER_TASK_ISSUED_IN_FUTURE');
    }
    if (!envelope.expiresAt.isAfter(envelope.issuedAt)) {
      throw StateError('CLUSTER_TASK_INVALID_WINDOW');
    }
    final valid = await verifySignature(
      envelope,
      configuration.signingPublicKey,
    );
    if (!valid) throw StateError('CLUSTER_TASK_BAD_SIGNATURE');
    return envelope;
  }
}
