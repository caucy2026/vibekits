import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/platform_storage_layout.dart';

void main() {
  String normalized(String value) => value.replaceAll('\\', '/');

  test('Windows 持久数据、缓存、下载和凭据位置彼此明确', () {
    final PlatformStorageLayout layout = PlatformStorageLayout.resolve(
      operatingSystem: 'windows',
      environment: const <String, String>{
        'LOCALAPPDATA': r'C:\Users\dev\AppData\Local',
      },
      systemTempPath: r'C:\Temp',
      executablePath: r'D:\Apps\Vibekits\vibekits.exe',
    );
    expect(
      normalized(layout.settingsFile),
      endsWith('/Vibekits/settings.json'),
    );
    expect(normalized(layout.modelsDirectory), endsWith('/Vibekits/Models'));
    expect(
      normalized(layout.harnessDebugDirectory),
      'C:/Users/dev/AppData/Local/Vibekits/debug',
    );
    expect(
      normalized(layout.harnessQueueDirectory),
      'C:/Users/dev/AppData/Local/Vibekits/Harness/queue',
    );
    expect(layout.credentialStoreLabel, 'Windows Credential Manager');
  });

  test('macOS 使用 Application Support、Caches、Logs 和 Keychain', () {
    final PlatformStorageLayout layout = PlatformStorageLayout.resolve(
      operatingSystem: 'macos',
      environment: const <String, String>{'HOME': '/Users/dev'},
      systemTempPath: '/private/tmp',
    );
    expect(
      normalized(layout.settingsFile),
      '/Users/dev/Library/Application Support/Vibekits/settings.json',
    );
    expect(
      normalized(layout.downloadsDirectory),
      '/Users/dev/Library/Caches/Vibekits/downloads',
    );
    expect(
      normalized(layout.harnessDebugDirectory),
      '/Users/dev/Library/Logs/Vibekits/Harness',
    );
    expect(layout.credentialStoreLabel, 'macOS Keychain');
  });

  test('Android 设置进 files，下载和调试数据只进应用 cache', () {
    final PlatformStorageLayout layout = PlatformStorageLayout.resolve(
      operatingSystem: 'android',
      environment: const <String, String>{},
      systemTempPath: '/data/user/0/com.vibekits.vibekits/cache',
    );
    expect(
      normalized(layout.settingsFile),
      '/data/user/0/com.vibekits.vibekits/files/Vibekits/settings.json',
    );
    expect(
      normalized(layout.downloadsDirectory),
      '/data/user/0/com.vibekits.vibekits/cache/Vibekits/downloads',
    );
    expect(
      normalized(layout.modelsDirectory),
      contains('/files/Vibekits/Models'),
    );
    expect(layout.credentialStoreLabel, 'Android Keystore');
    expect(normalized(layout.settingsDirectory), isNot(contains('/cache/')));
  });

  test('启动时所有可写目录都由用户数据根派生', () async {
    final PlatformStorageAccessReport report =
        await PlatformStorageLayout.initialize(
          operatingSystem: 'windows',
          environment: const <String, String>{},
          executablePath: r'C:\Program Files\Vibekits\vibekits.exe',
          roots: const PlatformStorageRoots(
            applicationSupport: r'C:\Users\dev\AppData\Roaming',
            applicationCache: r'C:\Users\dev\AppData\Local\cache',
            temporary: r'C:\Users\dev\AppData\Local\Temp',
            documents: r'C:\Users\dev\Documents',
          ),
          writeProbe: (String path) async =>
              !normalized(path).startsWith('C:/Program Files/'),
        );

    final PlatformStorageLayout layout = PlatformStorageLayout.current();
    expect(report.allRequiredWritable, isTrue);
    expect(report.fallbacks, isEmpty);
    expect(
      normalized(layout.harnessDebugDirectory),
      contains('/AppData/Roaming/Vibekits/debug'),
    );
    expect(report.persistentDataUsesTemporaryStorage, isFalse);
  });

  test('Windows 显式数据盘根目录统一 Harness queue MCP 和 debug', () async {
    final PlatformStorageAccessReport report =
        await PlatformStorageLayout.initialize(
          operatingSystem: 'windows',
          environment: const <String, String>{
            'VIBEKITS_DATA_HOME': r'D:\VibekitsData',
          },
          roots: const PlatformStorageRoots(
            applicationSupport: r'C:\Users\dev\AppData\Roaming',
            applicationCache: r'C:\Users\dev\AppData\Local\cache',
            temporary: r'C:\Users\dev\AppData\Local\Temp',
            documents: r'C:\Users\dev\Documents',
          ),
          writeProbe: (_) async => true,
        );

    final PlatformStorageLayout layout = PlatformStorageLayout.current();
    expect(report.fallbacks, isEmpty);
    expect(normalized(layout.dataHomeDirectory), 'D:/VibekitsData');
    expect(normalized(layout.harnessHomeDirectory), 'D:/VibekitsData/Harness');
    expect(
      normalized(layout.harnessQueueDirectory),
      'D:/VibekitsData/Harness/queue',
    );
    expect(
      normalized(layout.mcpConnectionFile),
      'D:/VibekitsData/Mcp/tool-bridge.json',
    );
    expect(normalized(layout.harnessDebugDirectory), 'D:/VibekitsData/debug');
  });

  test('持久目录只有临时应急位置可写时必须明确告警', () async {
    final PlatformStorageAccessReport report =
        await PlatformStorageLayout.initialize(
          operatingSystem: 'macos',
          environment: const <String, String>{'HOME': '/Users/dev'},
          executablePath: '/Applications/Vibekits.app/Contents/MacOS/Vibekits',
          roots: const PlatformStorageRoots(
            applicationSupport: '/readonly/support',
            applicationCache: '/writable/cache',
            temporary: '/writable/tmp',
            documents: '/readonly/documents',
          ),
          writeProbe: (String path) async =>
              normalized(path).startsWith('/writable/'),
        );

    expect(report.allRequiredWritable, isTrue);
    expect(report.persistentDataUsesTemporaryStorage, isTrue);
    expect(
      normalized(PlatformStorageLayout.current().settingsDirectory),
      contains('/writable/tmp/Vibekits/persistent-recovery'),
    );
  });

  test('Android 官方沙箱根目录通过探针后直接使用', () async {
    final PlatformStorageAccessReport report =
        await PlatformStorageLayout.initialize(
          operatingSystem: 'android',
          environment: const <String, String>{},
          roots: const PlatformStorageRoots(
            applicationSupport: '/data/user/0/com.vibekits/files',
            applicationCache: '/data/user/0/com.vibekits/cache',
            temporary: '/data/user/0/com.vibekits/cache',
            documents: '/data/user/0/com.vibekits/files',
          ),
          writeProbe: (String path) async =>
              normalized(path).startsWith('/data/user/0/com.vibekits/'),
        );

    expect(report.allRequiredWritable, isTrue);
    expect(report.fallbacks, isEmpty);
    expect(
      normalized(PlatformStorageLayout.current().settingsDirectory),
      '/data/user/0/com.vibekits/files/Vibekits',
    );
  });
}
