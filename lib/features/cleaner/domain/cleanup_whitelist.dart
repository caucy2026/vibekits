import 'dart:io';

abstract final class CleanupWhitelist {
  static String? normalize(String path) {
    String value = path.trim();
    if (value.isEmpty || value.contains('\u0000')) return null;
    try {
      value = Directory(value).absolute.path.replaceAll('/', r'\');
    } on FileSystemException {
      return null;
    }
    while (value.endsWith(r'\') && !_isDriveRoot(value)) {
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
    return candidateKey == rootKey || candidateKey.startsWith('$rootKey\\');
  }

  static String _key(String path) => path.toLowerCase();

  static bool _isDriveRoot(String path) =>
      RegExp(r'^[a-zA-Z]:\\$').hasMatch(path);
}
