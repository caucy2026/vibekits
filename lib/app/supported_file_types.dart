enum VibekitsFileKind { archive, document, model, unsupported }

/// File types that Vibekits can actually open today.
abstract final class SupportedFileTypes {
  static const List<String> archiveExtensions = <String>[
    'zip',
    'tar',
    'gz',
    'tgz',
    'bz2',
    'tbz2',
    'xz',
    'txz',
    '7z',
  ];

  static const List<String> documentExtensions = <String>[
    'txt',
    'log',
    'md',
    'markdown',
    'ini',
    'cfg',
    'conf',
    'properties',
    'yaml',
    'yml',
    'toml',
    'env',
    'editorconfig',
    'gitignore',
    'diff',
    'patch',
    'tex',
    'latex',
    'csv',
    'tsv',
    'json',
    'xml',
    'html',
    'htm',
    'epub',
    'svg',
    'svgz',
    'bin',
    'dart',
    'js',
    'mjs',
    'cjs',
    'ts',
    'tsx',
    'jsx',
    'css',
    'scss',
    'less',
    'vue',
    'svelte',
    'py',
    'pyw',
    'java',
    'kt',
    'kts',
    'c',
    'h',
    'cc',
    'cpp',
    'cxx',
    'hpp',
    'cs',
    'go',
    'rs',
    'swift',
    'sh',
    'bash',
    'zsh',
    'bat',
    'cmd',
    'ps1',
    'sql',
    'gradle',
    'cmake',
    'dockerfile',
  ];

  static const List<String> modelExtensions = <String>[
    'onnx',
    'ort',
    'tflite',
    'gguf',
    'model',
  ];

  static const List<String> allExtensions = <String>[
    ...archiveExtensions,
    ...documentExtensions,
    ...modelExtensions,
  ];

  static VibekitsFileKind kindForPath(String path) {
    final String name = path
        .replaceAll('\\', '/')
        .split('/')
        .last
        .toLowerCase();
    final String? extension = _extensionOf(name);
    if (extension != null && archiveExtensions.contains(extension)) {
      return VibekitsFileKind.archive;
    }
    if (extension != null && documentExtensions.contains(extension)) {
      return VibekitsFileKind.document;
    }
    if (extension != null && modelExtensions.contains(extension)) {
      return VibekitsFileKind.model;
    }
    return VibekitsFileKind.unsupported;
  }

  static String? _extensionOf(String name) {
    // Extension-like filenames commonly used by developer tools.
    if (name == 'dockerfile') return 'dockerfile';
    if (name == 'cmakelists.txt') return 'txt';
    if (name.startsWith('.') && !name.substring(1).contains('.')) {
      return name.substring(1);
    }
    final int dot = name.lastIndexOf('.');
    return dot < 0 || dot == name.length - 1 ? null : name.substring(dot + 1);
  }
}
