import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../domain/programmer_calculator.dart';

class ProgrammerCalculatorWorkspace extends StatefulWidget {
  const ProgrammerCalculatorWorkspace({super.key});

  @override
  State<ProgrammerCalculatorWorkspace> createState() =>
      _ProgrammerCalculatorWorkspaceState();
}

class _ProgrammerCalculatorWorkspaceState
    extends State<ProgrammerCalculatorWorkspace> {
  final TextEditingController _controller = TextEditingController(text: '0');
  final FocusNode _inputFocus = FocusNode();
  int _width = 64;
  int _radix = 10;
  ProgrammerCalculation? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _calculate();
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _calculate() {
    try {
      final ProgrammerCalculation result = ProgrammerCalculator.calculate(
        _controller.text,
        width: _width,
        inputRadix: _radix,
      );
      setState(() {
        _result = result;
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _result = null;
        _error = error.message;
      });
    }
  }

  void _setExpression(String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _calculate();
    _inputFocus.requestFocus();
  }

  void _insert(String value) {
    final TextSelection selection = _controller.selection;
    final String source = _controller.text;
    final int start = selection.isValid ? selection.start : source.length;
    final int end = selection.isValid ? selection.end : source.length;
    final bool replaceZero =
        source == '0' && RegExp(r'^[0-9A-F]$').hasMatch(value);
    final String next = replaceZero
        ? value
        : source.replaceRange(start, end, value);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: replaceZero ? value.length : start + value.length,
      ),
    );
    _calculate();
    _inputFocus.requestFocus();
  }

  void _backspace() {
    final TextSelection selection = _controller.selection;
    final String source = _controller.text;
    if (source.isEmpty) return;
    final int start = selection.isValid ? selection.start : source.length;
    final int end = selection.isValid ? selection.end : source.length;
    final int removeStart = start == end ? (start - 1).clamp(0, start) : start;
    final String next = source.replaceRange(removeStart, end, '');
    _setExpression(next.isEmpty ? '0' : next);
  }

  void _equals() {
    final ProgrammerCalculation? result = _result;
    if (result != null) {
      _setExpression(_displayValue(result, _radix, grouped: false));
    }
  }

  void _changeRadix(int radix) {
    if (radix == _radix) return;
    final ProgrammerCalculation? result = _result;
    setState(() => _radix = radix);
    if (result == null) {
      _calculate();
    } else {
      _setExpression(_displayValue(result, radix, grouped: false));
    }
  }

  void _rotate(bool left) {
    final ProgrammerCalculation? result = _result;
    if (result == null) return;
    final BigInt mask = (BigInt.one << _width) - BigInt.one;
    final BigInt value = result.unsigned;
    final BigInt rotated = left
        ? ((value << 1) | (value >> (_width - 1))) & mask
        : ((value >> 1) | ((value & BigInt.one) << (_width - 1))) & mask;
    final ProgrammerCalculation rotatedResult = ProgrammerCalculator.calculate(
      rotated.toString(),
      width: _width,
    );
    _setExpression(_displayValue(rotatedResult, _radix, grouped: false));
  }

  Future<void> _copyResult() async {
    final ProgrammerCalculation? result = _result;
    if (result == null) return;
    await Clipboard.setData(
      ClipboardData(text: _displayValue(result, _radix, grouped: false)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('结果已复制')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ProgrammerCalculation? result = _result;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.calculate_outlined, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    '程序员计算器',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  DropdownButton<int>(
                    value: _width,
                    underline: const SizedBox.shrink(),
                    items: const <DropdownMenuItem<int>>[
                      DropdownMenuItem(value: 64, child: Text('QWORD  64 位')),
                      DropdownMenuItem(value: 32, child: Text('DWORD  32 位')),
                      DropdownMenuItem(value: 16, child: Text('WORD  16 位')),
                      DropdownMenuItem(value: 8, child: Text('BYTE  8 位')),
                    ],
                    onChanged: (int? value) {
                      if (value == null) return;
                      _width = value;
                      _calculate();
                    },
                  ),
                ],
              ),
              TextField(
                key: const Key('programmer-calculator-input'),
                controller: _controller,
                focusNode: _inputFocus,
                autofocus: true,
                textAlign: TextAlign.end,
                onChanged: (_) => _calculate(),
                onSubmitted: (_) => _equals(),
                style: const TextStyle(
                  fontFamily: 'Cascadia Mono',
                  fontSize: 20,
                ),
                decoration: InputDecoration(
                  hintText: '0',
                  errorText: _error,
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    tooltip: '复制当前结果',
                    onPressed: result == null ? null : _copyResult,
                    icon: const Icon(Icons.copy_outlined, size: 18),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: SelectableText(
                  result == null ? '—' : _displayValue(result, _radix),
                  key: ValueKey<String>('calculator-${_radixLabel(_radix)}'),
                  maxLines: 2,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: 'Cascadia Mono',
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildRadixPanel(result),
              const SizedBox(height: 10),
              Expanded(child: _buildKeypad()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadixPanel(ProgrammerCalculation? result) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.vibe.panelRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.vibe.border),
      ),
      child: Column(
        children: <Widget>[
          for (final int radix in const <int>[16, 10, 8, 2])
            InkWell(
              key: ValueKey<String>('calculator-base-$radix'),
              onTap: () => _changeRadix(radix),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 3,
                      height: 20,
                      color: _radix == radix
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                    ),
                    const SizedBox(width: 9),
                    SizedBox(
                      width: 34,
                      child: Text(
                        _radixLabel(radix),
                        style: TextStyle(
                          fontSize: 11,
                          color: _radix == radix
                              ? Theme.of(context).colorScheme.primary
                              : context.vibe.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        result == null ? '—' : _displayValue(result, radix),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Cascadia Mono',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKeypad() {
    final List<_CalculatorKey> keys = <_CalculatorKey>[
      _CalculatorKey('A', () => _insert('A'), enabled: _radix == 16),
      _CalculatorKey('RoL', () => _rotate(true)),
      _CalculatorKey('RoR', () => _rotate(false)),
      _CalculatorKey('(', () => _insert('(')),
      _CalculatorKey(')', () => _insert(')')),
      _CalculatorKey('⌫', _backspace),
      _CalculatorKey('B', () => _insert('B'), enabled: _radix == 16),
      _CalculatorKey('Lsh', () => _insert(' << ')),
      _CalculatorKey('Rsh', () => _insert(' >> ')),
      _CalculatorKey('OR', () => _insert(' | ')),
      _CalculatorKey('XOR', () => _insert(' ^ ')),
      _CalculatorKey('÷', () => _insert(' / '), accent: true),
      _CalculatorKey('C', () => _insert('C'), enabled: _radix == 16),
      _CalculatorKey('7', () => _insert('7'), enabled: _radix >= 8),
      _CalculatorKey('8', () => _insert('8'), enabled: _radix >= 10),
      _CalculatorKey('9', () => _insert('9'), enabled: _radix >= 10),
      _CalculatorKey('AND', () => _insert(' & ')),
      _CalculatorKey('×', () => _insert(' * '), accent: true),
      _CalculatorKey('D', () => _insert('D'), enabled: _radix == 16),
      _CalculatorKey('4', () => _insert('4'), enabled: _radix >= 8),
      _CalculatorKey('5', () => _insert('5'), enabled: _radix >= 8),
      _CalculatorKey('6', () => _insert('6'), enabled: _radix >= 8),
      _CalculatorKey('NOT', () => _insert('~')),
      _CalculatorKey('−', () => _insert(' - '), accent: true),
      _CalculatorKey('E', () => _insert('E'), enabled: _radix == 16),
      _CalculatorKey('1', () => _insert('1')),
      _CalculatorKey('2', () => _insert('2'), enabled: _radix >= 8),
      _CalculatorKey('3', () => _insert('3'), enabled: _radix >= 8),
      _CalculatorKey('MOD', () => _insert(' % ')),
      _CalculatorKey('+', () => _insert(' + '), accent: true),
      _CalculatorKey('F', () => _insert('F'), enabled: _radix == 16),
      _CalculatorKey('CE', () => _setExpression('0')),
      _CalculatorKey('0', () => _insert('0')),
      _CalculatorKey('00', () => _insert('00')),
      _CalculatorKey('=', _equals, primary: true, span: 2),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double keyWidth = (constraints.maxWidth - 5 * 6) / 6;
        return SingleChildScrollView(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: keys
                .map((_CalculatorKey key) {
                  final double width = key.span == 1
                      ? keyWidth
                      : keyWidth * key.span + 6 * (key.span - 1);
                  return SizedBox(
                    width: width,
                    height: 42,
                    child: key.primary
                        ? FilledButton(
                            key: ValueKey<String>(
                              'calculator-key-${key.label}',
                            ),
                            onPressed: key.enabled ? key.onPressed : null,
                            child: Text(key.label),
                          )
                        : OutlinedButton(
                            key: ValueKey<String>(
                              'calculator-key-${key.label}',
                            ),
                            onPressed: key.enabled ? key.onPressed : null,
                            style: key.accent
                                ? OutlinedButton.styleFrom(
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  )
                                : null,
                            child: Text(key.label),
                          ),
                  );
                })
                .toList(growable: false),
          ),
        );
      },
    );
  }

  String _displayValue(
    ProgrammerCalculation result,
    int radix, {
    bool grouped = true,
  }) {
    if (radix == 10) return result.signed.toString();
    String value = result.unsigned.toRadixString(radix).toUpperCase();
    if (!grouped) return value;
    final int groupSize = radix == 2
        ? 4
        : radix == 16
        ? 4
        : 3;
    final List<String> groups = <String>[];
    while (value.isNotEmpty) {
      final int start = (value.length - groupSize).clamp(0, value.length);
      groups.insert(0, value.substring(start));
      value = value.substring(0, start);
    }
    return groups.join(' ');
  }

  String _radixLabel(int radix) => switch (radix) {
    16 => 'HEX',
    10 => 'DEC',
    8 => 'OCT',
    2 => 'BIN',
    _ => '$radix',
  };
}

class _CalculatorKey {
  const _CalculatorKey(
    this.label,
    this.onPressed, {
    this.enabled = true,
    this.primary = false,
    this.accent = false,
    this.span = 1,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool primary;
  final bool accent;
  final int span;
}
