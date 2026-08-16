class ProgrammerCalculation {
  const ProgrammerCalculation({
    required this.expression,
    required this.width,
    required this.raw,
    required this.unsigned,
    required this.signed,
  });

  final String expression;
  final int width;
  final BigInt raw;
  final BigInt unsigned;
  final BigInt signed;

  String get decimal => signed == unsigned
      ? signed.toString()
      : '${signed.toString()}（无符号 ${unsigned.toString()}）';

  String get hexadecimal =>
      '0x${unsigned.toRadixString(16).toUpperCase().padLeft(width ~/ 4, '0')}';

  String get octal => '0o${unsigned.toRadixString(8)}';

  String get binary {
    final String bits = unsigned.toRadixString(2).padLeft(width, '0');
    final List<String> groups = <String>[];
    for (int index = 0; index < bits.length; index += 4) {
      groups.add(bits.substring(index, (index + 4).clamp(0, bits.length)));
    }
    return '0b${groups.join(' ')}';
  }
}

abstract final class ProgrammerCalculator {
  static const Set<int> supportedWidths = <int>{8, 16, 32, 64, 128};

  static ProgrammerCalculation calculate(String expression, {int width = 64}) {
    final String source = expression.trim();
    if (source.isEmpty) throw const FormatException('请输入表达式');
    if (source.length > 4096) throw const FormatException('表达式过长');
    if (!supportedWidths.contains(width)) {
      throw const FormatException('位宽必须为 8、16、32、64 或 128');
    }
    final BigInt raw = _ExpressionParser(source).parse();
    final BigInt modulus = BigInt.one << width;
    final BigInt mask = modulus - BigInt.one;
    final BigInt unsigned = raw & mask;
    final BigInt signBit = BigInt.one << (width - 1);
    final BigInt signed = (unsigned & signBit) == BigInt.zero
        ? unsigned
        : unsigned - modulus;
    return ProgrammerCalculation(
      expression: source,
      width: width,
      raw: raw,
      unsigned: unsigned,
      signed: signed,
    );
  }
}

class _ExpressionParser {
  _ExpressionParser(this.source);

  final String source;
  int position = 0;

  static const Map<String, int> _precedence = <String, int>{
    '|': 1,
    '^': 2,
    '&': 3,
    '<<': 4,
    '>>': 4,
    '+': 5,
    '-': 5,
    '*': 6,
    '/': 6,
    '%': 6,
  };

  BigInt parse() {
    final BigInt result = _parseExpression(1);
    _skipWhitespace();
    if (position != source.length) {
      throw FormatException('无法识别的内容', source, position);
    }
    return result;
  }

  BigInt _parseExpression(int minimumPrecedence) {
    BigInt left = _parseUnary();
    while (true) {
      _skipWhitespace();
      final int saved = position;
      final String? operator = _readOperator();
      final int? precedence = operator == null ? null : _precedence[operator];
      if (precedence == null || precedence < minimumPrecedence) {
        position = saved;
        return left;
      }
      final BigInt right = _parseExpression(precedence + 1);
      left = _apply(operator!, left, right);
      if (left.bitLength > 16384) {
        throw const FormatException('计算结果过大');
      }
    }
  }

  BigInt _parseUnary() {
    _skipWhitespace();
    if (_consume('+')) return _parseUnary();
    if (_consume('-')) return -_parseUnary();
    if (_consume('~')) return ~_parseUnary();
    if (_consume('(')) {
      final BigInt value = _parseExpression(1);
      _skipWhitespace();
      if (!_consume(')')) {
        throw FormatException('缺少右括号', source, position);
      }
      return value;
    }
    return _parseNumber();
  }

  BigInt _parseNumber() {
    _skipWhitespace();
    final int start = position;
    int radix = 10;
    if (_peekPrefix('0x') || _peekPrefix('0X')) {
      radix = 16;
      position += 2;
    } else if (_peekPrefix('0b') || _peekPrefix('0B')) {
      radix = 2;
      position += 2;
    } else if (_peekPrefix('0o') || _peekPrefix('0O')) {
      radix = 8;
      position += 2;
    }
    final int digitsStart = position;
    while (position < source.length) {
      final int unit = source.codeUnitAt(position);
      final bool digit = unit >= 0x30 && unit <= 0x39;
      final bool alpha =
          unit >= 0x41 && unit <= 0x46 || unit >= 0x61 && unit <= 0x66;
      if (!digit && !alpha && unit != 0x5f) break;
      position++;
    }
    final String digits = source
        .substring(digitsStart, position)
        .replaceAll('_', '');
    if (digits.isEmpty) {
      throw FormatException('这里需要整数', source, start);
    }
    if (digits.length > 1024) throw const FormatException('整数位数过多');
    try {
      return BigInt.parse(digits, radix: radix);
    } on FormatException {
      throw FormatException('$radix 进制数字格式错误', source, start);
    }
  }

  String? _readOperator() {
    for (final String operator in <String>['<<', '>>']) {
      if (_peekPrefix(operator)) {
        position += operator.length;
        return operator;
      }
    }
    if (position < source.length && _precedence.containsKey(source[position])) {
      return source[position++];
    }
    return null;
  }

  BigInt _apply(String operator, BigInt left, BigInt right) {
    return switch (operator) {
      '+' => left + right,
      '-' => left - right,
      '*' => left * right,
      '/' =>
        right == BigInt.zero
            ? throw const FormatException('不能除以 0')
            : left ~/ right,
      '%' =>
        right == BigInt.zero
            ? throw const FormatException('不能对 0 取余')
            : left.remainder(right),
      '&' => left & right,
      '|' => left | right,
      '^' => left ^ right,
      '<<' => left << _shiftCount(right),
      '>>' => left >> _shiftCount(right),
      _ => throw StateError('未知运算符 $operator'),
    };
  }

  int _shiftCount(BigInt value) {
    if (value < BigInt.zero || value > BigInt.from(16384)) {
      throw const FormatException('移位数量必须在 0 到 16384 之间');
    }
    return value.toInt();
  }

  bool _consume(String value) {
    if (!_peekPrefix(value)) return false;
    position += value.length;
    return true;
  }

  bool _peekPrefix(String value) => source.startsWith(value, position);

  void _skipWhitespace() {
    while (position < source.length && source.codeUnitAt(position) <= 0x20) {
      position++;
    }
  }
}
