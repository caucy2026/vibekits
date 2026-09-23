import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../app/app_update_service.dart';

/// Verifies the downloaded component before activation and every execution.
/// The archive SHA is checked against the HTTPS market record by the installer.
abstract final class RuntimeComponentVerifier {
  static Directory componentDirectory(String id) {
    if (!const {'virtual_machine', 'network_proxy'}.contains(id)) {
      throw const FormatException('未知组件');
    }
    final home = Platform.environment['HOME'] ?? '';
    final base = Platform.isWindows
        ? Platform.environment['LOCALAPPDATA']
        : p.join(home, 'Library', 'Application Support');
    if (base == null || !p.isAbsolute(base)) {
      throw const FormatException('组件安装目录不可用');
    }
    return Directory(p.join(base, 'Vibekits', 'components', id));
  }

  static Directory activeDirectory(String id) {
    final root = componentDirectory(id);
    var pointer = File(p.join(root.path, 'active.json'));
    if (!pointer.existsSync()) {
      pointer = File(p.join(root.path, 'active.previous.json'));
    }
    if (!pointer.existsSync()) return Directory(p.join(root.path, 'current'));
    final data = jsonDecode(pointer.readAsStringSync());
    final version = data is Map ? data['version_code'] : null;
    if (version is! int || version <= 0) {
      throw const FormatException('组件激活记录无效，请重新安装');
    }
    return Directory(p.join(root.path, '$version'));
  }

  /// Android native extensions are delivered as signed APK components and
  /// installed by the system package manager; they are never executed from
  /// the market download directory.
  static String get architecture => switch (Abi.current()) {
    Abi.windowsX64 || Abi.macosX64 => 'x64',
    Abi.windowsArm64 || Abi.macosArm64 => 'arm64',
    Abi.androidArm64 => 'arm64-v8a',
    _ => 'unsupported',
  };

  static Future<void> verify(
    Directory root,
    String componentId, {
    int? versionCode,
  }) async {
    final file = File(p.join(root.path, 'component-manifest.json'));
    if (!await file.exists()) {
      throw const FormatException('组件缺少发布清单，请重新安装');
    }
    final manifest = jsonDecode(await file.readAsString());
    if (manifest is! Map<String, dynamic> ||
        manifest['schema_version'] != 1 ||
        manifest['host_package_name'] != AppUpdateService.packageName ||
        manifest['component_id'] != componentId ||
        manifest['standalone'] != false ||
        manifest['os_type'] != Platform.operatingSystem ||
        manifest['architecture'] != architecture ||
        manifest['version_code'] is! int ||
        (manifest['version_code'] as int) <= 0 ||
        (versionCode != null && manifest['version_code'] != versionCode) ||
        manifest['files'] is! Map<String, dynamic>) {
      throw const FormatException('组件宿主、平台、架构或版本不匹配');
    }
    final files = manifest['files'] as Map<String, dynamic>;
    final runtime = componentId == 'virtual_machine' ? 'qemu' : 'mihomo';
    if (!const {'virtual_machine', 'network_proxy'}.contains(componentId)) {
      throw const FormatException('未知组件');
    }
    final expected = componentId == 'virtual_machine'
        ? ['qemu-system-x86_64', 'qemu-img']
        : ['mihomo'];
    for (final name in expected) {
      if (!files.containsKey(
        '$runtime/$name${Platform.isWindows ? '.exe' : ''}',
      )) {
        throw const FormatException('组件清单缺少必要程序');
      }
    }
    final native = <String>[];
    final seen = <String>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Link) throw const FormatException('组件不允许符号链接');
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: root.path)
          .replaceAll('\\', '/');
      if (relative == 'component-manifest.json' ||
          relative == 'component.json') {
        continue;
      }
      final declared = files[relative];
      if (declared is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(declared) ||
          (await sha256.bind(entity.openRead()).first).toString() != declared) {
        throw const FormatException('组件文件校验失败，请重新安装');
      }
      seen.add(relative);
      if (Platform.isWindows &&
          (relative.toLowerCase().endsWith('.exe') ||
              relative.toLowerCase().endsWith('.dll'))) {
        native.add(entity.path);
      }
    }
    if (seen.length != files.length) {
      throw const FormatException('组件文件不完整');
    }
    if (Platform.isWindows) {
      await _verifyWindowsSignatures(native);
    } else if (Platform.isMacOS) {
      // macOS component delivery remains blocked until notarized component
      // packaging and target-device acceptance are implemented.
      throw const FormatException('此版本尚未开放 macOS 组件安装');
    } else {
      throw const FormatException('当前平台不支持组件');
    }
  }

  static Future<void> probe(Directory root, String id) async {
    final runtime = id == 'virtual_machine' ? 'qemu' : 'mihomo';
    final names = id == 'virtual_machine'
        ? ['qemu-system-x86_64', 'qemu-img']
        : ['mihomo'];
    for (final name in names) {
      final result = await Process.run(
        p.join(root.path, runtime, '$name${Platform.isWindows ? '.exe' : ''}'),
        id == 'virtual_machine' ? ['--version'] : ['-v'],
        runInShell: false,
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) throw const FormatException('组件无法运行，未激活新版本');
    }
  }

  static Future<void> verifyManagedExecutable(String executable) async {
    final root = File(executable).parent.parent;
    final normalized = p
        .normalize(root.path)
        .replaceAll('\\', '/')
        .toLowerCase();
    if (!normalized.contains('/vibekits/components/')) return;
    final componentId = p.basename(root.parent.path);
    await verify(root, componentId);
  }

  static Future<void> verifyWindowsInstaller(String path) =>
      _verifyWindowsSignatures([path]);

  static Future<void> _verifyWindowsSignatures(List<String> files) async {
    if (files.isEmpty) throw const FormatException('组件缺少已签名程序');
    String quote(String value) => "'${value.replaceAll("'", "''")}'";
    final script =
        '''
\$ErrorActionPreference='Stop'
\$hostSignature=Get-AuthenticodeSignature -LiteralPath ${quote(Platform.resolvedExecutable)}
if(\$hostSignature.Status -ne 'Valid'){exit 2}
\$hostCert=[System.Security.Cryptography.X509Certificates.X509Certificate2]::new([System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile(${quote(Platform.resolvedExecutable)}))
foreach(\$file in (\$env:VIBEKITS_COMPONENT_VERIFY_FILES | ConvertFrom-Json)) {
  \$signature=Get-AuthenticodeSignature -LiteralPath \$file
  \$embedded=[System.Security.Cryptography.X509Certificates.X509Certificate2]::new([System.Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile(\$file))
  if(\$signature.Status -ne 'Valid' -or \$embedded.Thumbprint -ne \$hostCert.Thumbprint){exit 3}
}
exit 0
''';
    final bytes = <int>[];
    for (final unit in script.codeUnits) {
      bytes.addAll([unit & 255, unit >> 8]);
    }
    final systemRoot = Platform.environment['SystemRoot'];
    if (systemRoot == null || !p.isAbsolute(systemRoot)) {
      throw const FormatException('无法定位系统签名验证程序');
    }
    final result = await Process.run(
      p.join(
        systemRoot,
        'System32',
        'WindowsPowerShell',
        'v1.0',
        'powershell.exe',
      ),
      [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        base64Encode(bytes),
      ],
      runInShell: false,
      environment: {'VIBEKITS_COMPONENT_VERIFY_FILES': jsonEncode(files)},
    ).timeout(const Duration(seconds: 60));
    if (result.exitCode != 0) {
      throw const FormatException('组件签名无效或与主程序发布者不匹配');
    }
  }
}
