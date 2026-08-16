class SourceLanguageInfo {
  const SourceLanguageInfo({
    required this.label,
    this.isShell = false,
    this.isSource = true,
  });

  final String label;
  final bool isShell;
  final bool isSource;
}

abstract final class SourceLanguageCatalog {
  static const Map<String, SourceLanguageInfo> _fileNames =
      <String, SourceLanguageInfo>{
        'dockerfile': SourceLanguageInfo(label: 'Dockerfile'),
        'makefile': SourceLanguageInfo(label: 'Makefile'),
        'gnumakefile': SourceLanguageInfo(label: 'Makefile'),
        'justfile': SourceLanguageInfo(label: 'Just'),
        'procfile': SourceLanguageInfo(label: 'Procfile'),
        'jenkinsfile': SourceLanguageInfo(label: 'Jenkins Pipeline'),
        'vagrantfile': SourceLanguageInfo(label: 'Ruby'),
        'gemfile': SourceLanguageInfo(label: 'Ruby'),
        'rakefile': SourceLanguageInfo(label: 'Ruby'),
        'podfile': SourceLanguageInfo(label: 'Ruby'),
        'brewfile': SourceLanguageInfo(label: 'Ruby'),
        'cmakelists.txt': SourceLanguageInfo(label: 'CMake'),
        'workspace': SourceLanguageInfo(label: 'Bazel'),
        'build': SourceLanguageInfo(label: 'Bazel'),
      };

  static const Map<String, SourceLanguageInfo> _extensions =
      <String, SourceLanguageInfo>{
        'dart': SourceLanguageInfo(label: 'Dart'),
        'js': SourceLanguageInfo(label: 'JavaScript'),
        'mjs': SourceLanguageInfo(label: 'JavaScript'),
        'cjs': SourceLanguageInfo(label: 'JavaScript'),
        'ts': SourceLanguageInfo(label: 'TypeScript'),
        'tsx': SourceLanguageInfo(label: 'TypeScript React'),
        'jsx': SourceLanguageInfo(label: 'JavaScript React'),
        'py': SourceLanguageInfo(label: 'Python'),
        'pyw': SourceLanguageInfo(label: 'Python'),
        'rb': SourceLanguageInfo(label: 'Ruby'),
        'php': SourceLanguageInfo(label: 'PHP'),
        'phtml': SourceLanguageInfo(label: 'PHP'),
        'java': SourceLanguageInfo(label: 'Java'),
        'kt': SourceLanguageInfo(label: 'Kotlin'),
        'kts': SourceLanguageInfo(label: 'Kotlin Script'),
        'c': SourceLanguageInfo(label: 'C'),
        'h': SourceLanguageInfo(label: 'C/C++ Header'),
        'cc': SourceLanguageInfo(label: 'C++'),
        'cpp': SourceLanguageInfo(label: 'C++'),
        'cxx': SourceLanguageInfo(label: 'C++'),
        'hpp': SourceLanguageInfo(label: 'C++ Header'),
        'cs': SourceLanguageInfo(label: 'C#'),
        'go': SourceLanguageInfo(label: 'Go'),
        'rs': SourceLanguageInfo(label: 'Rust'),
        'swift': SourceLanguageInfo(label: 'Swift'),
        'scala': SourceLanguageInfo(label: 'Scala'),
        'groovy': SourceLanguageInfo(label: 'Groovy'),
        'clj': SourceLanguageInfo(label: 'Clojure'),
        'cljs': SourceLanguageInfo(label: 'ClojureScript'),
        'ex': SourceLanguageInfo(label: 'Elixir'),
        'exs': SourceLanguageInfo(label: 'Elixir Script'),
        'erl': SourceLanguageInfo(label: 'Erlang'),
        'fs': SourceLanguageInfo(label: 'F#'),
        'fsx': SourceLanguageInfo(label: 'F# Script'),
        'vb': SourceLanguageInfo(label: 'Visual Basic'),
        'lua': SourceLanguageInfo(label: 'Lua'),
        'r': SourceLanguageInfo(label: 'R'),
        'jl': SourceLanguageInfo(label: 'Julia'),
        'hs': SourceLanguageInfo(label: 'Haskell'),
        'elm': SourceLanguageInfo(label: 'Elm'),
        'ml': SourceLanguageInfo(label: 'OCaml'),
        'mli': SourceLanguageInfo(label: 'OCaml Interface'),
        'nim': SourceLanguageInfo(label: 'Nim'),
        'zig': SourceLanguageInfo(label: 'Zig'),
        'v': SourceLanguageInfo(label: 'V'),
        'sol': SourceLanguageInfo(label: 'Solidity'),
        'pas': SourceLanguageInfo(label: 'Pascal'),
        'asm': SourceLanguageInfo(label: 'Assembly'),
        's': SourceLanguageInfo(label: 'Assembly'),
        'sh': SourceLanguageInfo(label: 'Shell', isShell: true),
        'bash': SourceLanguageInfo(label: 'Bash', isShell: true),
        'zsh': SourceLanguageInfo(label: 'Zsh', isShell: true),
        'fish': SourceLanguageInfo(label: 'Fish', isShell: true),
        'nu': SourceLanguageInfo(label: 'Nushell', isShell: true),
        'ps1': SourceLanguageInfo(label: 'PowerShell', isShell: true),
        'bat': SourceLanguageInfo(label: 'Windows Batch', isShell: true),
        'cmd': SourceLanguageInfo(label: 'Windows Command', isShell: true),
        'sql': SourceLanguageInfo(label: 'SQL'),
        'graphql': SourceLanguageInfo(label: 'GraphQL'),
        'gql': SourceLanguageInfo(label: 'GraphQL'),
        'proto': SourceLanguageInfo(label: 'Protocol Buffers'),
        'tf': SourceLanguageInfo(label: 'Terraform'),
        'tfvars': SourceLanguageInfo(label: 'Terraform Variables'),
        'hcl': SourceLanguageInfo(label: 'HCL'),
        'nix': SourceLanguageInfo(label: 'Nix'),
        'css': SourceLanguageInfo(label: 'CSS'),
        'scss': SourceLanguageInfo(label: 'SCSS'),
        'less': SourceLanguageInfo(label: 'Less'),
        'html': SourceLanguageInfo(label: 'HTML'),
        'vue': SourceLanguageInfo(label: 'Vue'),
        'svelte': SourceLanguageInfo(label: 'Svelte'),
        'astro': SourceLanguageInfo(label: 'Astro'),
        'json': SourceLanguageInfo(label: 'JSON'),
        'yaml': SourceLanguageInfo(label: 'YAML'),
        'yml': SourceLanguageInfo(label: 'YAML'),
        'toml': SourceLanguageInfo(label: 'TOML'),
        'xml': SourceLanguageInfo(label: 'XML'),
        'cmake': SourceLanguageInfo(label: 'CMake'),
        'gradle': SourceLanguageInfo(label: 'Gradle'),
        'bazel': SourceLanguageInfo(label: 'Bazel'),
        'bzl': SourceLanguageInfo(label: 'Bazel'),
      };

  static SourceLanguageInfo? identify(String path, {String head = ''}) {
    final String name = path
        .replaceAll('\\', '/')
        .split('/')
        .last
        .toLowerCase();
    final SourceLanguageInfo? byName = _fileNames[name];
    if (byName != null) return byName;
    final int dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      final SourceLanguageInfo? byExtension =
          _extensions[name.substring(dot + 1)];
      if (byExtension != null) return byExtension;
    }
    return _fromShebang(head);
  }

  static SourceLanguageInfo? _fromShebang(String head) {
    if (!head.startsWith('#!')) return null;
    final String line = head.split(RegExp(r'\r?\n')).first.toLowerCase();
    if (line.contains('python')) {
      return const SourceLanguageInfo(label: 'Python');
    }
    if (line.contains('node') ||
        line.contains('deno') ||
        line.contains('bun')) {
      return const SourceLanguageInfo(label: 'JavaScript');
    }
    if (line.contains('pwsh') || line.contains('powershell')) {
      return const SourceLanguageInfo(label: 'PowerShell', isShell: true);
    }
    if (line.contains('bash')) {
      return const SourceLanguageInfo(label: 'Bash', isShell: true);
    }
    if (line.contains('zsh')) {
      return const SourceLanguageInfo(label: 'Zsh', isShell: true);
    }
    if (line.contains('fish')) {
      return const SourceLanguageInfo(label: 'Fish', isShell: true);
    }
    if (line.contains('/sh') || line.contains(' sh')) {
      return const SourceLanguageInfo(label: 'Shell', isShell: true);
    }
    if (line.contains('ruby')) return const SourceLanguageInfo(label: 'Ruby');
    if (line.contains('perl')) return const SourceLanguageInfo(label: 'Perl');
    if (line.contains('php')) return const SourceLanguageInfo(label: 'PHP');
    if (line.contains('lua')) return const SourceLanguageInfo(label: 'Lua');
    return const SourceLanguageInfo(label: 'Executable Script');
  }
}
