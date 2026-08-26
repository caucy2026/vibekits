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
    expect(normalized(layout.harnessDebugDirectory), 'D:/Apps/Vibekits/tmp');
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
}
