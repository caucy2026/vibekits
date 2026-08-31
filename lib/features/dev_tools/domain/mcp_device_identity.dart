import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class McpDeviceIdentity {
  const McpDeviceIdentity({
    required this.appId,
    required this.appName,
    required this.hardwareCode,
    required this.instanceId,
    required this.displayName,
  });

  final String appId;
  final String appName;
  final String hardwareCode;
  final String instanceId;
  final String displayName;

  static McpDeviceIdentity forVibekits() {
    const String appId = 'com.vibekits.desktop';
    const String appName = 'VibeKits';
    final String host = Platform.localHostname.trim().isEmpty
        ? 'device'
        : Platform.localHostname.trim();
    final String hardwareMaterial = <String>[
      Platform.operatingSystem,
      host,
      Platform.environment['COMPUTERNAME'] ?? '',
      Platform.environment['PROCESSOR_IDENTIFIER'] ?? '',
      Platform.environment['HOSTNAME'] ?? '',
    ].join('|').toLowerCase();
    final String code = sha256
        .convert(utf8.encode('$appId|$hardwareMaterial'))
        .toString()
        .substring(0, 10)
        .toUpperCase();
    return McpDeviceIdentity(
      appId: appId,
      appName: appName,
      hardwareCode: code,
      instanceId: '$appId:$code',
      displayName: '$appName@$host-$code',
    );
  }
}

class McpExposurePreferences {
  McpExposurePreferences({File? file})
    : file =
          file ??
          File(
            '${Directory.current.absolute.path}${Platform.pathSeparator}'
            '.runtime-cache${Platform.pathSeparator}mcp'
            '${Platform.pathSeparator}exposure.json',
          );

  final File file;
  static const int consentVersion = 2;

  Future<bool> loadEnabled() async {
    try {
      if (!await file.exists()) return false;
      final Object? decoded = jsonDecode(await file.readAsString());
      return decoded is Map &&
              decoded['consentVersion'] == consentVersion &&
              decoded['enabled'] is bool
          ? decoded['enabled']! as bool
          : false;
    } on Object {
      return false;
    }
  }

  Future<void> saveEnabled(bool enabled) async {
    await file.parent.create(recursive: true);
    final File temporary = File('${file.path}.$pid.tmp');
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 2,
        'consentVersion': consentVersion,
        'enabled': enabled,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
