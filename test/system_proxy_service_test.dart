import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/system_proxy_service.dart';

void main() {
  test('Windows 系统代理保存、应用并恢复原值', () async {
    if (!Platform.isWindows) return;
    final Directory data = await Directory.systemTemp.createTemp('vk_proxy_');
    addTearDown(() => data.delete(recursive: true));
    final Map<String, String> registry = <String, String>{
      'ProxyEnable': '0x0',
      'ProxyServer': 'old.proxy:8080',
      'ProxyOverride': '<local>;example.test',
    };
    Future<ProcessResult> runner(String _, List<String> arguments) async {
      final String operation = arguments.first;
      final int valueIndex = arguments.indexOf('/v');
      final String name = arguments[valueIndex + 1];
      if (operation == 'query') {
        final String? value = registry[name];
        return ProcessResult(
          1,
          value == null ? 1 : 0,
          value == null ? '' : '    $name    REG_SZ    $value\r\n',
          '',
        );
      }
      if (operation == 'delete') {
        registry.remove(name);
        return ProcessResult(1, 0, '', '');
      }
      final int dataIndex = arguments.indexOf('/d');
      registry[name] = arguments[dataIndex + 1] == '1'
          ? '0x1'
          : arguments[dataIndex + 1] == '0'
          ? '0x0'
          : arguments[dataIndex + 1];
      return ProcessResult(1, 0, '', '');
    }

    final SystemProxyService service = SystemProxyService(runner: runner);
    final SystemProxySnapshot applied = await service.applyLocal(
      port: 7890,
      dataDirectory: data.path,
    );
    expect(applied.enabled, isTrue);
    expect(applied.server, '127.0.0.1:7890');
    expect(File('${data.path}\\system-proxy-backup.json').existsSync(), isTrue);

    final SystemProxySnapshot restored = await service.restore(
      dataDirectory: data.path,
    );
    expect(restored.enabled, isFalse);
    expect(restored.server, 'old.proxy:8080');
    expect(restored.bypass, '<local>;example.test');
  });
}
