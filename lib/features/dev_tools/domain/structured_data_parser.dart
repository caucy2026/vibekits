import 'dart:convert';

import 'package:xml/xml.dart';

abstract final class StructuredDataParser {
  static Object? parse(String input, String format) {
    final String selected = format.toLowerCase() == 'auto'
        ? detectFormat(input)
        : format.toLowerCase();
    return switch (selected) {
      'json' => jsonDecode(input),
      'yaml' || 'yml' => _parseYaml(input),
      'toml' => _parseToml(input),
      'xml' => _xmlValue(XmlDocument.parse(input).rootElement),
      _ => throw FormatException('不支持的结构化格式：$selected'),
    };
  }

  static String detectFormat(String input) {
    final String value = input.trimLeft();
    if (value.startsWith('{') || value.startsWith('[')) return 'json';
    if (value.startsWith('<')) return 'xml';
    if (RegExp(r'^\s*\[[^\]]+\]\s*$', multiLine: true).hasMatch(input) ||
        RegExp(
          r'^\s*[A-Za-z0-9_.-]+\s*=\s*',
          multiLine: true,
        ).hasMatch(input)) {
      return 'toml';
    }
    return 'yaml';
  }

  static Object? _parseYaml(String input) {
    final List<_YamlLine> lines = <_YamlLine>[];
    for (final String raw in input.replaceAll('\r\n', '\n').split('\n')) {
      if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
      final int indent = raw.length - raw.trimLeft().length;
      lines.add(_YamlLine(indent, raw.trim()));
    }
    if (lines.isEmpty) return <String, Object?>{};
    final _YamlResult result = _yamlBlock(lines, 0, lines.first.indent);
    if (result.next != lines.length) {
      throw FormatException('YAML 缩进无法解析：第 ${result.next + 1} 项');
    }
    return result.value;
  }

  static _YamlResult _yamlBlock(List<_YamlLine> lines, int start, int indent) {
    if (lines[start].indent != indent) {
      throw const FormatException('YAML 缩进不一致');
    }
    if (lines[start].text.startsWith('-')) {
      final List<Object?> values = <Object?>[];
      int index = start;
      while (index < lines.length &&
          lines[index].indent == indent &&
          lines[index].text.startsWith('-')) {
        final String rest = lines[index].text.substring(1).trim();
        if (rest.isEmpty) {
          if (index + 1 >= lines.length || lines[index + 1].indent <= indent) {
            values.add(null);
            index++;
          } else {
            final _YamlResult nested = _yamlBlock(
              lines,
              index + 1,
              lines[index + 1].indent,
            );
            values.add(nested.value);
            index = nested.next;
          }
        } else if (_yamlKeyValue(rest)
            case final MapEntry<String, String> pair) {
          final Map<String, Object?> item = <String, Object?>{
            pair.key: pair.value.isEmpty ? null : _scalar(pair.value),
          };
          index++;
          while (index < lines.length && lines[index].indent > indent) {
            final _YamlLine child = lines[index];
            final MapEntry<String, String>? childPair = _yamlKeyValue(
              child.text,
            );
            if (childPair == null) break;
            if (childPair.value.isEmpty &&
                index + 1 < lines.length &&
                lines[index + 1].indent > child.indent) {
              final _YamlResult nested = _yamlBlock(
                lines,
                index + 1,
                lines[index + 1].indent,
              );
              item[childPair.key] = nested.value;
              index = nested.next;
            } else {
              item[childPair.key] = _scalar(childPair.value);
              index++;
            }
          }
          values.add(item);
        } else {
          values.add(_scalar(rest));
          index++;
        }
      }
      return _YamlResult(values, index);
    }
    final Map<String, Object?> values = <String, Object?>{};
    int index = start;
    while (index < lines.length && lines[index].indent == indent) {
      final MapEntry<String, String>? pair = _yamlKeyValue(lines[index].text);
      if (pair == null) {
        throw FormatException('YAML 映射缺少冒号：${lines[index].text}');
      }
      if (pair.value.isEmpty &&
          index + 1 < lines.length &&
          lines[index + 1].indent > indent) {
        final _YamlResult nested = _yamlBlock(
          lines,
          index + 1,
          lines[index + 1].indent,
        );
        values[pair.key] = nested.value;
        index = nested.next;
      } else {
        values[pair.key] = _scalar(pair.value);
        index++;
      }
    }
    return _YamlResult(values, index);
  }

  static MapEntry<String, String>? _yamlKeyValue(String value) {
    final int colon = value.indexOf(':');
    if (colon <= 0) return null;
    return MapEntry<String, String>(
      value.substring(0, colon).trim(),
      value.substring(colon + 1).trim(),
    );
  }

  static Object? _parseToml(String input) {
    final Map<String, Object?> root = <String, Object?>{};
    Map<String, Object?> current = root;
    for (final String raw in input.replaceAll('\r\n', '\n').split('\n')) {
      final String line = _stripComment(raw).trim();
      if (line.isEmpty) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        current = root;
        for (final String part
            in line.substring(1, line.length - 1).split('.')) {
          final String key = part.trim();
          current = current.putIfAbsent(
            key,
            () => <String, Object?>{},
          ) as Map<String, Object?>;
        }
        continue;
      }
      final int equals = line.indexOf('=');
      if (equals <= 0) throw FormatException('TOML 行缺少 =：$line');
      current[line.substring(0, equals).trim()] = _scalar(
        line.substring(equals + 1).trim(),
      );
    }
    return root;
  }

  static String _stripComment(String value) {
    bool quoted = false;
    String quote = '';
    for (int index = 0; index < value.length; index++) {
      final String char = value[index];
      if ((char == '"' || char == "'") &&
          (index == 0 || value[index - 1] != '\\')) {
        if (!quoted) {
          quoted = true;
          quote = char;
        } else if (quote == char) {
          quoted = false;
        }
      }
      if (char == '#' && !quoted) return value.substring(0, index);
    }
    return value;
  }

  static Object? _xmlValue(XmlElement element) {
    final Map<String, Object?> content = <String, Object?>{
      for (final XmlAttribute attribute in element.attributes)
        '@${attribute.name.local}': attribute.value,
    };
    for (final XmlElement child in element.childElements) {
      final Object? value = _xmlValue(child);
      final String key = child.name.local;
      if (!content.containsKey(key)) {
        content[key] = value;
      } else if (content[key] is List<Object?>) {
        (content[key]! as List<Object?>).add(value);
      } else {
        content[key] = <Object?>[content[key], value];
      }
    }
    final String text = element.children
        .whereType<XmlText>()
        .map((XmlText node) => node.value)
        .join()
        .trim();
    if (content.isEmpty) return text;
    if (text.isNotEmpty) content['#text'] = text;
    return content;
  }

  static Object? _scalar(String value) {
    final String text = value.trim();
    if (text.isEmpty || text == 'null' || text == '~') return null;
    if ((text.startsWith('"') && text.endsWith('"')) ||
        (text.startsWith("'") && text.endsWith("'"))) {
      return text.substring(1, text.length - 1);
    }
    if (text == 'true') return true;
    if (text == 'false') return false;
    if (int.tryParse(text) case final int number) return number;
    if (double.tryParse(text) case final double number) return number;
    if (text.startsWith('[') && text.endsWith(']')) {
      return text
          .substring(1, text.length - 1)
          .split(',')
          .where((String item) => item.trim().isNotEmpty)
          .map(_scalar)
          .toList();
    }
    return text;
  }
}

class _YamlLine {
  const _YamlLine(this.indent, this.text);
  final int indent;
  final String text;
}

class _YamlResult {
  const _YamlResult(this.value, this.next);
  final Object? value;
  final int next;
}
