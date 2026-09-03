import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;
import 'package:vibekits/features/about/domain/marketing_cache_service.dart';

void main() {
  late Directory temporary;
  late Uint8List png;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('vibekits-marketing-');
    png = Uint8List.fromList(
      image_codec.encodePng(image_codec.Image(width: 4, height: 3)),
    );
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  MarketingRemoteManifest manifest(String version, {int count = 3}) =>
      MarketingRemoteManifest(
        name: MarketingCacheService.resourceName,
        version: version,
        files: List<MarketingRemoteFile>.generate(
          count,
          (int index) => MarketingRemoteFile(
            name: 'series-$index.png',
            url: Uri.parse('https://cdn.example.test/series-$index.png'),
            mime: 'image/png',
            md5Digest: md5.convert(png).toString(),
            size: png.length,
            sortOrder: index,
          ),
        ),
      );

  test('完整下载后原子发布，清单未变化时不重复下载', () async {
    int downloads = 0;
    final MarketingCacheService service = MarketingCacheService(
      cacheRoot: temporary,
      manifestLoader: () async => manifest('1.0.2'),
      bytesLoader: (_) async {
        downloads += 1;
        return png;
      },
    );

    await service.refresh();
    expect(service.snapshot.value.state, MarketingCacheState.ready);
    expect(service.snapshot.value.version, '1.0.2');
    expect(service.snapshot.value.images, hasLength(3));
    expect(downloads, 3);
    expect(await File('${temporary.path}/active.json').exists(), isTrue);

    await service.refresh();
    expect(downloads, 3);
  });

  test('新版本完整性失败时继续使用上一版完整缓存', () async {
    String version = '1.0.1';
    bool corrupt = false;
    final MarketingCacheService service = MarketingCacheService(
      cacheRoot: temporary,
      manifestLoader: () async => manifest(version),
      bytesLoader: (_) async => corrupt ? Uint8List.fromList(<int>[1, 2]) : png,
    );
    await service.refresh();
    version = '1.0.2';
    corrupt = true;
    await service.refresh();

    expect(service.snapshot.value.state, MarketingCacheState.ready);
    expect(service.snapshot.value.version, '1.0.1');
    expect(service.snapshot.value.images, hasLength(3));
  });
}
