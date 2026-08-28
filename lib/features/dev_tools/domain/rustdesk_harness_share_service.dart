import 'dart:async';
import 'dart:io';

class RustDeskHostInfo {
  const RustDeskHostInfo({
    required this.executable,
    required this.id,
    required this.available,
    required this.message,
  });

  final String executable;
  final String id;
  final bool available;
  final String message;
}

typedef RustDeskProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);
typedef RustDeskProcessLauncher = Future<void> Function(
  String executable,
  List<String> arguments,
);

/// Integrates with the official RustDesk client without handling passwords.
///
/// `hbbr` is not a generic application-data relay. The official RustDesk host
/// streams the Vibekits desktop through hbbs/hbbr and the official web client
/// provides remote interaction. This adapter only discovers/starts that host.
abstract final class RustDeskHarnessShareService {
  static Future<String> discoverWebClientUrl({File? configFile}) async {
    final List<File> candidates = configFile != null
        ? <File>[configFile]
        : <File>[
            if (Platform.isWindows)
              File(
                '${Platform.environment['APPDATA'] ?? ''}'
                '${Platform.pathSeparator}RustDesk${Platform.pathSeparator}config'
                '${Platform.pathSeparator}RustDesk2.toml',
              ),
            if (Platform.isMacOS)
              File(
                '${Platform.environment['HOME'] ?? ''}'
                '${Platform.pathSeparator}Library${Platform.pathSeparator}Preferences'
                '${Platform.pathSeparator}com.carriez.RustDesk${Platform.pathSeparator}RustDesk2.toml',
              ),
          ];
    for (final File file in candidates) {
      if (!await file.exists() || await file.length() > 1024 * 1024) continue;
      final List<String> lines = await file.readAsLines();
      for (final String key in <String>[
        'custom-rendezvous-server',
        'rendezvous_server',
      ]) {
        final RegExp expression = RegExp(
          '^${RegExp.escape(key)}\\s*=\\s*[\\x27\\x22]'
          '([^\\x27\\x22]+)[\\x27\\x22]\\s*\$',
        );
        for (final String line in lines) {
          final String? raw = expression.firstMatch(line.trim())?.group(1);
          if (raw == null) continue;
          final String host = raw.trim().replaceFirst(RegExp(r':\d+$'), '');
          if (RegExp(r'^[A-Za-z0-9.-]{1,253}$').hasMatch(host)) {
            return 'https://$host/web';
          }
        }
      }
    }
    return '';
  }

  static List<String> candidateExecutables({String configured = ''}) {
    final List<String> candidates = <String>[];
    if (configured.trim().isNotEmpty) candidates.add(configured.trim());
    if (Platform.isWindows) {
      for (final String? root in <String?>[
        Platform.environment['ProgramFiles'],
        Platform.environment['ProgramFiles(x86)'],
        Platform.environment['LOCALAPPDATA'],
      ]) {
        if (root == null || root.trim().isEmpty) continue;
        candidates.add(
          '$root${Platform.pathSeparator}RustDesk${Platform.pathSeparator}RustDesk.exe',
        );
      }
    } else if (Platform.isMacOS) {
      candidates.add('/Applications/RustDesk.app/Contents/MacOS/RustDesk');
    }
    return candidates.toSet().toList(growable: false);
  }

  static Future<RustDeskHostInfo> inspect({
    String configuredExecutable = '',
    RustDeskProcessRunner? runner,
  }) async {
    final String executable =
        candidateExecutables(configured: configuredExecutable)
            .where((String path) => File(path).existsSync())
            .firstOrNull ??
        '';
    if (executable.isEmpty) {
      return const RustDeskHostInfo(
        executable: '',
        id: '',
        available: false,
        message: '未找到KEMI远程办公客户端，请在设置中指定路径',
      );
    }
    try {
      final ProcessResult result = await (runner ?? Process.run)(
        executable,
        const <String>['--get-id'],
      ).timeout(const Duration(seconds: 8));
      final String combined = '${result.stdout}\n${result.stderr}'.trim();
      final String id =
          RegExp(r'(?<!\d)([A-Za-z][A-Za-z0-9_-]{4,31}|\d{6,16})(?!\d)')
              .firstMatch(combined)
              ?.group(1) ??
          '';
      return RustDeskHostInfo(
        executable: executable,
        id: id,
        available: true,
        message: id.isEmpty ? 'KEMI远程办公可用，请在客户端中查看KEMI办公 ID' : 'KEMI办公 ID：$id',
      );
    } on Object catch (error) {
      return RustDeskHostInfo(
        executable: executable,
        id: '',
        available: true,
        message: 'KEMI远程办公可用，但读取KEMI办公 ID 失败：$error',
      );
    }
  }

  static Future<void> launchHost(
    String executable, {
    RustDeskProcessLauncher? launcher,
  }) async {
    if (executable.trim().isEmpty || !File(executable).existsSync()) {
      throw StateError('KEMI远程办公客户端不存在');
    }
    await (launcher ?? _launchDetached)(executable, const <String>[]);
  }

  static Uri validateWebClientUrl(String value) {
    final Uri? uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('KEMI远程办公网页端地址必须是不含账号信息的 HTTP/HTTPS URL');
    }
    return uri;
  }

  static Future<void> openWebClient(
    String value, {
    RustDeskProcessLauncher? launcher,
  }) async {
    final Uri uri = validateWebClientUrl(value);
    if (Platform.isWindows) {
      await (launcher ?? _launchDetached)('explorer.exe', <String>[
        uri.toString(),
      ]);
    } else if (Platform.isMacOS) {
      await (launcher ?? _launchDetached)('/usr/bin/open', <String>[
        uri.toString(),
      ]);
    } else {
      await (launcher ?? _launchDetached)('xdg-open', <String>[uri.toString()]);
    }
  }

  static Future<void> _launchDetached(
    String executable,
    List<String> arguments,
  ) async {
    await Process.start(
      executable,
      arguments,
      runInShell: false,
      mode: ProcessStartMode.detached,
    );
  }
}
