import 'dart:io';

abstract final class CleanupWhitelist {
  static String? normalize(String path) {
    String value = path.trim();
    if (value.isEmpty || value.contains('\u0000')) return null;
    final bool windowsPath =
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value) || value.startsWith(r'\\');
    if (windowsPath) {
      value = value.replaceAll('/', r'\');
      while (value.endsWith(r'\') && !_isDriveRoot(value)) {
        value = value.substring(0, value.length - 1);
      }
      return value;
    }
    try {
      value = Directory(value).absolute.path.replaceAll(r'\', '/');
    } on FileSystemException {
      return null;
    }
    while (value.endsWith('/') && value.length > 1) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static List<String> sanitize(Iterable<String> paths) {
    final Map<String, String> unique = <String, String>{};
    for (final String path in paths.take(100)) {
      final String? normalized = normalize(path);
      if (normalized != null) unique[_key(normalized)] = normalized;
    }
    final List<String> result = unique.values.toList()..sort();
    return result;
  }

  static bool contains(String root, String candidate) {
    final String? normalizedRoot = normalize(root);
    final String? normalizedCandidate = normalize(candidate);
    if (normalizedRoot == null || normalizedCandidate == null) return false;
    final String rootKey = _key(normalizedRoot);
    final String candidateKey = _key(normalizedCandidate);
    final String separator = _isWindowsPath(normalizedRoot) ? r'\' : '/';
    return candidateKey == rootKey ||
        candidateKey.startsWith('$rootKey$separator');
  }

  // Default macOS volumes are case-insensitive too. A whitelist must never
  // miss the same physical path merely because a scanner changed casing.
  static String _key(String path) => path.toLowerCase();

  static bool _isWindowsPath(String path) =>
      RegExp(r'^[a-zA-Z]:\\').hasMatch(path) || path.startsWith(r'\\');

  static bool _isDriveRoot(String path) =>
      RegExp(r'^[a-zA-Z]:\\$').hasMatch(path);
}
