enum VibekitsFileKind {
  archive,
  document,
  database,
  image,
  model,
  audio,
  unsupported,
}

/// File types that Vibekits can actually open today.
abstract final class SupportedFileTypes {
  static const List<String> audioExtensions = <String>[
    'pcm',
    'raw',
    'wav',
    'wave',
  ];
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
    'rar',
    'r00',
    'iso',
    'img',
    'zst',
    'tzst',
    'cab',
    'arj',
    'lzh',
    'chm',
    'msi',
    'nsis',
    'udf',
    'wim',
    'swm',
    'esd',
    'dmg',
    'hfs',
    'apfs',
    'vhd',
    'vhdx',
    'ova',
    'cpio',
    'rpm',
    'deb',
    'squashfs',
    'zipx',
    'jar',
    'xpi',
    'apk',
    'appx',
    'ipa',
    'odt',
    'ods',
    'docx',
    'xlsx',
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
    'rb',
    'php',
    'phtml',
    'lua',
    'r',
    'scala',
    'sc',
    'groovy',
    'clj',
    'cljs',
    'cljc',
    'edn',
    'ex',
    'exs',
    'erl',
    'hrl',
    'fs',
    'fsx',
    'fsi',
    'vb',
    'vbs',
    'asm',
    's',
    'v',
    'zig',
    'nim',
    'nims',
    'sol',
    'proto',
    'graphql',
    'gql',
    'tf',
    'tfvars',
    'hcl',
    'nix',
    'fish',
    'nu',
    'awk',
    'sed',
    'pl',
    'pm',
    'tcl',
    'coffee',
    'wat',
    'wasm',
    'lock',
    'ipynb',
    'astro',
    'elm',
    'hs',
    'lhs',
    'jl',
    'ml',
    'mli',
    'pas',
    'pp',
    'inc',
    'rego',
    'yara',
    'yar',
    'glsl',
    'vert',
    'frag',
    'comp',
    'hlsl',
    'metal',
    'rst',
    'adoc',
    'bazel',
    'bzl',
    'build',
  ];

  static const Set<String> specialDocumentFileNames = <String>{
    'makefile',
    'gnumakefile',
    'justfile',
    'procfile',
    'jenkinsfile',
    'vagrantfile',
    'gemfile',
    'rakefile',
    'podfile',
    'brewfile',
    'cmakelists.txt',
    'workspace',
    'build',
  };

  static const List<String> modelExtensions = <String>[
    'onnx',
    'ort',
    'tflite',
    'gguf',
    'model',
  ];

  static const List<String> databaseExtensions = <String>[
    'db',
    'db3',
    'sqlite',
    'sqlite3',
  ];

  static const List<String> imageExtensions = <String>[
    'png',
    'jpg',
    'jpeg',
    'jpe',
    'jfif',
    'webp',
    'bmp',
    'dib',
    'gif',
    'tif',
    'tiff',
    'ico',
    'cur',
    'tga',
    'psd',
    'exr',
    'pnm',
    'pbm',
    'pgm',
    'ppm',
    'pvr',
  ];

  static const List<String> allExtensions = <String>[
    ...archiveExtensions,
    ...documentExtensions,
    ...databaseExtensions,
    ...imageExtensions,
    ...modelExtensions,
    ...audioExtensions,
  ];

  static VibekitsFileKind kindForPath(String path) {
    final String name = path
        .replaceAll('\\', '/')
        .split('/')
        .last
        .toLowerCase();
    final String? extension = _extensionOf(name);
    if (specialDocumentFileNames.contains(name)) {
      return VibekitsFileKind.document;
    }
    if (extension != null && archiveExtensions.contains(extension)) {
      return VibekitsFileKind.archive;
    }
    if (extension != null && documentExtensions.contains(extension)) {
      return VibekitsFileKind.document;
    }
    if (extension != null && databaseExtensions.contains(extension)) {
      return VibekitsFileKind.database;
    }
    if (extension != null && imageExtensions.contains(extension)) {
      return VibekitsFileKind.image;
    }
    if (extension != null && modelExtensions.contains(extension)) {
      return VibekitsFileKind.model;
    }
    if (extension != null && audioExtensions.contains(extension)) {
      return VibekitsFileKind.audio;
    }
    return VibekitsFileKind.unsupported;
  }

  static bool isSpecialDocumentPath(String path) {
    final String name = path
        .replaceAll('\\', '/')
        .split('/')
        .last
        .toLowerCase();
    return specialDocumentFileNames.contains(name);
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
