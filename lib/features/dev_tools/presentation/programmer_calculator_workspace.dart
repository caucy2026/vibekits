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
  final TextEditingController _controller = TextEditingController(
    text: '0xFF & (1 << 7)',
  );
  int _width = 64;
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
    super.dispose();
  }

  void _calculate() {
    try {
      final ProgrammerCalculation result = ProgrammerCalculator.calculate(
        _controller.text,
        width: _width,
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

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value.replaceAll(' ', '')));
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已复制')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ProgrammerCalculation? result = _result;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.calculate_outlined, size: 22),
              const SizedBox(width: 8),
              const Text(
                '程序员计算器',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '输入即算 · 支持 0x / 0o / 0b',
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 11, color: context.vibe.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('programmer-calculator-input'),
            controller: _controller,
            autofocus: true,
            onChanged: (_) => _calculate(),
            style: const TextStyle(fontFamily: 'Cascadia Mono', fontSize: 20),
            decoration: InputDecoration(
              hintText: '例如：(0xFF << 8) | 0b1010',
              errorText: _error,
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空',
                      onPressed: () {
                        _controller.clear();
                        _calculate();
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text('整数位宽', style: TextStyle(color: context.vibe.muted)),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 8, label: Text('8')),
                  ButtonSegment<int>(value: 16, label: Text('16')),
                  ButtonSegment<int>(value: 32, label: Text('32')),
                  ButtonSegment<int>(value: 64, label: Text('64')),
                  ButtonSegment<int>(value: 128, label: Text('128')),
                ],
                selected: <int>{_width},
                onSelectionChanged: (Set<int> selected) {
                  _width = selected.first;
                  _calculate();
                },
              ),
              Text(
                '+  −  ×  ÷  %  &  |  ^  ~  <<  >>',
                style: TextStyle(
                  fontFamily: 'Cascadia Mono',
                  fontSize: 12,
                  color: context.vibe.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: result == null
                ? Center(
                    child: Text(
                      _controller.text.trim().isEmpty
                          ? '输入表达式开始计算'
                          : '修正表达式后会立即显示结果',
                      style: TextStyle(color: context.vibe.muted),
                    ),
                  )
                : ListView(
                    children: <Widget>[
                      _ResultRow(
                        label: 'DEC',
                        value: result.decimal,
                        onCopy: () => _copy(result.signed.toString()),
                      ),
                      _ResultRow(
                        label: 'HEX',
                        value: result.hexadecimal,
                        onCopy: () => _copy(result.hexadecimal),
                      ),
                      _ResultRow(
                        label: 'OCT',
                        value: result.octal,
                        onCopy: () => _copy(result.octal),
                      ),
                      _ResultRow(
                        label: 'BIN',
                        value: result.binary,
                        onCopy: () => _copy(result.binary),
                      ),
                      if (result.raw != result.signed &&
                          result.raw != result.unsigned)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '原始结果 ${result.raw}，以上按 ${result.width} 位截断。',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.vibe.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 11, 6, 11),
      decoration: BoxDecoration(
        color: context.vibe.panelRaised,
        border: Border.all(color: context.vibe.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 42,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.vibe.muted,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              key: ValueKey<String>('calculator-$label'),
              style: const TextStyle(fontFamily: 'Cascadia Mono', fontSize: 15),
            ),
          ),
          IconButton(
            tooltip: '复制 $label',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined, size: 18),
          ),
        ],
      ),
    );
  }
}
