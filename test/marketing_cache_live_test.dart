import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/about/domain/marketing_cache_service.dart';

void main() {
  final bool enabled = Platform.environment['VIBEKITS_MARKETING_LIVE'] == '1';

  test(
    '生产系列资源清单和全部图片通过真实完整性校验',
    () async {
      final Directory temporary = await Directory.systemTemp.createTemp(
        'vibekits-marketing-live-',
      );
      try {
        final MarketingCacheService service = MarketingCacheService(
          cacheRoot: temporary,
        );
        await service.refresh();
        expect(service.snapshot.value.state, MarketingCacheState.ready);
        expect(service.snapshot.value.version, isNotEmpty);
        expect(service.snapshot.value.images.length, inInclusiveRange(1, 24));
        for (final MarketingCachedImage image
            in service.snapshot.value.images) {
          expect(await File(image.path).length(), greaterThan(0));
        }
      } finally {
        if (await temporary.exists()) await temporary.delete(recursive: true);
      }
    },
    skip: enabled ? false : 'set VIBEKITS_MARKETING_LIVE=1',
  );
}
