/// 与 pubspec.yaml 和 Windows Release 资源保持一致。
abstract final class AppVersion {
  static const String semantic = '1.3.0';
  static const int build = 4;
  static const String display = 'v$semantic+$build';
}
