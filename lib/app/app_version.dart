/// 与 pubspec.yaml 和 Windows Release 资源保持一致。
abstract final class AppVersion {
  static const String semantic = '1.9.0-dev.8';
  static const int build = 18;
  static const String display = 'v$semantic+$build';
}
