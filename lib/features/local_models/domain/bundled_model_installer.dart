import 'dart:io';

import 'curated_model_bundle.dart';
import 'model_store.dart';

typedef BundledModelAssetLoader = Future<List<int>> Function(String path);
typedef BundledModelInstallProgress = void Function(double value);

abstract final class BundledModelInstaller {
  static Future<List<ModelInfo>> installPpOcrV6Tiny(
    String directory,
    BundledModelAssetLoader loadAsset,
    BundledModelInstallProgress onProgress,
  ) => installBundle(ppOcrV6TinyBundle, directory, loadAsset, onProgress);

  static Future<List<ModelInfo>> installBundle(
    CuratedModelBundle bundle,
    String directory,
    BundledModelAssetLoader loadAsset,
    BundledModelInstallProgress onProgress,
  ) async {
    final Directory temporary = Directory.systemTemp.createTempSync(
      'vibekits_bundled_model_',
    );
    final List<String> stagedPaths = <String>[];
    int completedBytes = 0;
    try {
      for (final CuratedModelArtifact artifact in bundle.artifacts) {
        final String? assetPath = artifact.bundleAssetPath;
        if (assetPath == null || assetPath.isEmpty) {
          throw FormatException('${artifact.fileName} 未包含在应用资源中');
        }
        final List<int> bytes = await loadAsset(assetPath);
        final File staged = File(
          '${temporary.path}${Platform.pathSeparator}${artifact.fileName}',
        );
        await staged.writeAsBytes(bytes, flush: true);
        final String digest = await ModelStore.sha256OfFile(staged.path);
        if (digest != artifact.sha256) {
          throw FormatException('${artifact.fileName} SHA-256 校验失败');
        }
        stagedPaths.add(staged.path);
        completedBytes += bytes.length;
        onProgress((completedBytes / bundle.downloadBytes).clamp(0.0, 1.0));
      }
      final List<ModelInfo> installed = await ModelStore.importBundle(
        stagedPaths,
        directory,
      );
      onProgress(1);
      return installed;
    } finally {
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
    }
  }
}
