import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../documents/domain/text_encoding.dart';

enum FileDiffLineKind { equal, added, removed }

class FileDiffLine {
  const FileDiffLine({
    required this.kind,
    required this.text,
    this.leftLine,
    this.rightLine,
  });

  final FileDiffLineKind kind;
  final String text;
  final int? leftLine;
  final int? rightLine;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'text': text,
    'leftLine': leftLine,
    'rightLine': rightLine,
  };
}

class FileDiffResult {
  const FileDiffResult({
    required this.leftPath,
    required this.rightPath,
    required this.leftEncoding,
    required this.rightEncoding,
    required this.leftBytes,
    required this.rightBytes,
    required this.lines,
    required this.addedLines,
    required this.removedLines,
    required this.unchangedLines,
    required this.exactMinimalDiff,
  });

  final String leftPath;
  final String rightPath;
  final String leftEncoding;
  final String rightEncoding;
  final int leftBytes;
  final int rightBytes;
  final List<FileDiffLine> lines;
  final int addedLines;
  final int removedLines;
  final int unchangedLines;
  final bool exactMinimalDiff;

  bool get identical => addedLines == 0 && removedLines == 0;

  String get unifiedText {
    final StringBuffer output = StringBuffer()
      ..writeln('--- $leftPath')
      ..writeln('+++ $rightPath');
    for (final FileDiffLine line in lines) {
      output.writeln(switch (line.kind) {
        FileDiffLineKind.equal => ' ${line.text}',
        FileDiffLineKind.added => '+${line.text}',
        FileDiffLineKind.removed => '-${line.text}',
      });
    }
    return output.toString();
  }

  Map<String, Object?> toJson({int maxLines = 2000}) => <String, Object?>{
    'leftPath': leftPath,
    'rightPath': rightPath,
    'leftEncoding': leftEncoding,
    'rightEncoding': rightEncoding,
    'leftBytes': leftBytes,
    'rightBytes': rightBytes,
    'identical': identical,
    'addedLines': addedLines,
    'removedLines': removedLines,
    'unchangedLines': unchangedLines,
    'exactMinimalDiff': exactMinimalDiff,
    'lines': lines
        .take(maxLines)
        .map((FileDiffLine line) => line.toJson())
        .toList(),
    'truncated': lines.length > maxLines,
  };
}

abstract final class FileDiffService {
  static const int maxFileBytes = 8 * 1024 * 1024;
  static const int maxLinesPerFile = 50000;
  static const int maxLcsCells = 4000000;

  static Future<FileDiffResult> compare({
    required String leftPath,
    required String rightPath,
    bool ignoreWhitespace = false,
    bool ignoreCase = false,
  }) => Isolate.run<FileDiffResult>(
    () => compareSync(
      leftPath: leftPath,
      rightPath: rightPath,
      ignoreWhitespace: ignoreWhitespace,
      ignoreCase: ignoreCase,
    ),
    debugName: 'vibekits-file-diff',
  );

  static FileDiffResult compareSync({
    required String leftPath,
    required String rightPath,
    bool ignoreWhitespace = false,
    bool ignoreCase = false,
  }) {
    final File left = _validatedFile(leftPath, '左侧');
    final File right = _validatedFile(rightPath, '右侧');
    final Uint8List leftData = left.readAsBytesSync();
    final Uint8List rightData = right.readAsBytesSync();
    final DocEncoding leftEncoding = TextCodecs.detect(leftData);
    final DocEncoding rightEncoding = TextCodecs.detect(rightData);
    final List<String> leftLines = _lines(
      TextCodecs.decode(leftData, leftEncoding),
    );
    final List<String> rightLines = _lines(
      TextCodecs.decode(rightData, rightEncoding),
    );
    if (leftLines.length > maxLinesPerFile ||
        rightLines.length > maxLinesPerFile) {
      throw const FormatException('单个文件最多比较 50000 行');
    }
    final List<String> normalizedLeft = leftLines
        .map((String line) => _normalize(line, ignoreWhitespace, ignoreCase))
        .toList(growable: false);
    final List<String> normalizedRight = rightLines
        .map((String line) => _normalize(line, ignoreWhitespace, ignoreCase))
        .toList(growable: false);
    final _DiffBuild build = _buildDiff(
      leftLines,
      rightLines,
      normalizedLeft,
      normalizedRight,
    );
    return FileDiffResult(
      leftPath: left.absolute.path,
      rightPath: right.absolute.path,
      leftEncoding: leftEncoding.label,
      rightEncoding: rightEncoding.label,
      leftBytes: leftData.length,
      rightBytes: rightData.length,
      lines: List<FileDiffLine>.unmodifiable(build.lines),
      addedLines: build.added,
      removedLines: build.removed,
      unchangedLines: build.equal,
      exactMinimalDiff: build.exact,
    );
  }

  static File _validatedFile(String path, String side) {
    final String value = path.trim();
    if (value.isEmpty) throw FormatException('请选择$side文件');
    final File file = File(value);
    if (!file.existsSync()) throw FileSystemException('$side文件不存在', value);
    final int bytes = file.lengthSync();
    if (bytes > maxFileBytes) {
      throw FormatException('$side文件超过 8 MiB 限制');
    }
    return file;
  }

  static List<String> _lines(String text) {
    final String normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final List<String> lines = normalized.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return lines;
  }

  static String _normalize(
    String line,
    bool ignoreWhitespace,
    bool ignoreCase,
  ) {
    String value = line;
    if (ignoreWhitespace) value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (ignoreCase) value = value.toLowerCase();
    return value;
  }

  static _DiffBuild _buildDiff(
    List<String> left,
    List<String> right,
    List<String> normalizedLeft,
    List<String> normalizedRight,
  ) {
    int prefix = 0;
    while (prefix < left.length &&
        prefix < right.length &&
        normalizedLeft[prefix] == normalizedRight[prefix]) {
      prefix++;
    }
    int suffix = 0;
    while (suffix < left.length - prefix &&
        suffix < right.length - prefix &&
        normalizedLeft[left.length - 1 - suffix] ==
            normalizedRight[right.length - 1 - suffix]) {
      suffix++;
    }
    final List<FileDiffLine> output = <FileDiffLine>[];
    int leftLine = 1;
    int rightLine = 1;
    for (int index = 0; index < prefix; index++) {
      output.add(
        FileDiffLine(
          kind: FileDiffLineKind.equal,
          text: left[index],
          leftLine: leftLine++,
          rightLine: rightLine++,
        ),
      );
    }
    final int leftEnd = left.length - suffix;
    final int rightEnd = right.length - suffix;
    final int leftCount = leftEnd - prefix;
    final int rightCount = rightEnd - prefix;
    final bool exact = leftCount * rightCount <= maxLcsCells;
    if (exact) {
      final List<Uint32List> table = List<Uint32List>.generate(
        leftCount + 1,
        (_) => Uint32List(rightCount + 1),
      );
      for (int i = leftCount - 1; i >= 0; i--) {
        for (int j = rightCount - 1; j >= 0; j--) {
          table[i][j] =
              normalizedLeft[prefix + i] == normalizedRight[prefix + j]
              ? table[i + 1][j + 1] + 1
              : table[i + 1][j] >= table[i][j + 1]
              ? table[i + 1][j]
              : table[i][j + 1];
        }
      }
      int i = 0;
      int j = 0;
      while (i < leftCount || j < rightCount) {
        if (i < leftCount &&
            j < rightCount &&
            normalizedLeft[prefix + i] == normalizedRight[prefix + j]) {
          output.add(
            FileDiffLine(
              kind: FileDiffLineKind.equal,
              text: left[prefix + i],
              leftLine: leftLine++,
              rightLine: rightLine++,
            ),
          );
          i++;
          j++;
        } else if (j < rightCount &&
            (i == leftCount || table[i][j + 1] > table[i + 1][j])) {
          output.add(
            FileDiffLine(
              kind: FileDiffLineKind.added,
              text: right[prefix + j++],
              rightLine: rightLine++,
            ),
          );
        } else {
          output.add(
            FileDiffLine(
              kind: FileDiffLineKind.removed,
              text: left[prefix + i++],
              leftLine: leftLine++,
            ),
          );
        }
      }
    } else {
      for (int index = prefix; index < leftEnd; index++) {
        output.add(
          FileDiffLine(
            kind: FileDiffLineKind.removed,
            text: left[index],
            leftLine: leftLine++,
          ),
        );
      }
      for (int index = prefix; index < rightEnd; index++) {
        output.add(
          FileDiffLine(
            kind: FileDiffLineKind.added,
            text: right[index],
            rightLine: rightLine++,
          ),
        );
      }
    }
    for (int index = suffix; index > 0; index--) {
      final int leftIndex = left.length - index;
      output.add(
        FileDiffLine(
          kind: FileDiffLineKind.equal,
          text: left[leftIndex],
          leftLine: leftLine++,
          rightLine: rightLine++,
        ),
      );
    }
    int added = 0;
    int removed = 0;
    int equal = 0;
    for (final FileDiffLine line in output) {
      switch (line.kind) {
        case FileDiffLineKind.added:
          added++;
        case FileDiffLineKind.removed:
          removed++;
        case FileDiffLineKind.equal:
          equal++;
      }
    }
    return _DiffBuild(output, added, removed, equal, exact);
  }
}

class _DiffBuild {
  const _DiffBuild(
    this.lines,
    this.added,
    this.removed,
    this.equal,
    this.exact,
  );

  final List<FileDiffLine> lines;
  final int added;
  final int removed;
  final int equal;
  final bool exact;
}
