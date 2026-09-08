/// Version recognition is separate from file ownership. A newer OS never
/// grants permission to delete more directories merely because it is newer.
class CleanupOsProfile {
  const CleanupOsProfile({this.macosMajor, this.androidSdk});
  final int? macosMajor;
  final int? androidSdk;

  static int? parseMacosMajor(String version) {
    final match = RegExp(
      r'(?:Version|macOS)\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(version);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  bool get knownMacos =>
      macosMajor != null && macosMajor! >= 12 && macosMajor! <= 26;
  bool get knownAndroid =>
      androidSdk != null && androidSdk! >= 24 && androidSdk! <= 36;
  String get androidStoragePolicy {
    if (!knownAndroid) return '系统版本未验证：仅本应用缓存，保守复核';
    if (androidSdk! >= 30) return 'SDK $androidSdk：分区存储，仅本应用私有缓存';
    if (androidSdk! >= 29) return 'SDK $androidSdk：分区存储过渡，仅本应用私有缓存';
    return 'SDK $androidSdk：旧存储模型，仍不开放其他应用/共享目录';
  }
}
