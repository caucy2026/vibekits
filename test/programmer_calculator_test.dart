import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/programmer_calculator.dart';

void main() {
  test('支持混合进制、括号和标准运算优先级', () {
    final ProgrammerCalculation result = ProgrammerCalculator.calculate(
      '(0x10 + 0b11) * 2 | 1',
      width: 16,
    );
    expect(result.raw, BigInt.from(39));
    expect(result.decimal, '39');
    expect(result.hexadecimal, '0x0027');
    expect(result.octal, '0o47');
    expect(result.binary, '0b0000 0000 0010 0111');
  });

  test('按位宽同时给出有符号和无符号解释', () {
    final ProgrammerCalculation result = ProgrammerCalculator.calculate(
      '0xFF',
      width: 8,
    );
    expect(result.unsigned, BigInt.from(255));
    expect(result.signed, BigInt.from(-1));
    expect(result.decimal, '-1（无符号 255）');
    expect(result.hexadecimal, '0xFF');
  });

  test('支持移位、异或、取反和整数除法', () {
    expect(
      ProgrammerCalculator.calculate('(1 << 8) ^ 0x0F').raw,
      BigInt.from(271),
    );
    expect(ProgrammerCalculator.calculate('~0', width: 32).signed, -BigInt.one);
    expect(ProgrammerCalculator.calculate('7 / 2').raw, BigInt.from(3));
  });

  test('拒绝除零、非法数字和过大移位', () {
    expect(
      () => ProgrammerCalculator.calculate('1 / 0'),
      throwsFormatException,
    );
    expect(
      () => ProgrammerCalculator.calculate('0b102'),
      throwsFormatException,
    );
    expect(
      () => ProgrammerCalculator.calculate('1 << 20000'),
      throwsFormatException,
    );
  });
}
