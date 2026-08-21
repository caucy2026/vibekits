import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_theme.dart';
import '../domain/tool_registry.dart';
import '../domain/tool_result.dart';

class UtilityCollectionWorkspace extends StatefulWidget {
  const UtilityCollectionWorkspace({super.key, this.initialToolId});

  final String? initialToolId;

  @override
  State<UtilityCollectionWorkspace> createState() =>
      _UtilityCollectionWorkspaceState();
}

class _UtilityCollectionWorkspaceState extends State<UtilityCollectionWorkspace>
    with SingleTickerProviderStateMixin {
  late final List<String> _groups = <String>[
    for (final ToolSpec tool in utilityToolRegistry)
      if (!utilityToolRegistry
          .takeWhile((ToolSpec item) => item != tool)
          .any((ToolSpec item) => item.group == tool.group))
        tool.group,
  ];
  late final Map<String, ToolSpec> _selectedByGroup = <String, ToolSpec>{
    for (final String group in _groups)
      group: utilityToolRegistry.firstWhere(
        (ToolSpec tool) => tool.group == group,
      ),
  };
  late final TabController _tabs = TabController(
    length: _groups.length,
    vsync: this,
  );
  late final Map<String, ScrollController> _toolScrollControllers =
      <String, ScrollController>{
        for (final String group in _groups) group: ScrollController(),
      };
  final Map<String, GlobalKey> _toolKeys = <String, GlobalKey>{};
  final TextEditingController _input = TextEditingController();
  final TextEditingController _params = TextEditingController();
  final TextEditingController _output = TextEditingController();
  bool _executing = false;
  bool _outputIsError = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_handleTabChange);
    _selectInitial(widget.initialToolId);
  }

  @override
  void didUpdateWidget(covariant UtilityCollectionWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialToolId != oldWidget.initialToolId) {
      _selectInitial(widget.initialToolId);
    }
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_handleTabChange)
      ..dispose();
    for (final ScrollController controller in _toolScrollControllers.values) {
      controller.dispose();
    }
    _input.dispose();
    _params.dispose();
    _output.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (!_tabs.indexIsChanging && mounted) {
      setState(() {});
      _revealTool(_activeTool.id);
    }
  }

  void _selectInitial(String? toolId) {
    final ToolSpec? tool = utilityToolRegistry
        .where((ToolSpec item) => item.id == toolId)
        .firstOrNull;
    if (tool == null) return;
    _selectedByGroup[tool.group] = tool;
    final int index = _groups.indexOf(tool.group);
    if (index >= 0) _tabs.index = index;
    _revealTool(tool.id);
  }

  ToolSpec get _activeTool => _selectedByGroup[_groups[_tabs.index]]!;

  void _selectTool(ToolSpec tool) {
    setState(() {
      _selectedByGroup[tool.group] = tool;
      _params.clear();
      _output.clear();
      _outputIsError = false;
    });
    _revealTool(tool.id);
  }

  void _revealTool(String toolId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? target = _toolKeys[toolId]?.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollToolStrip(String group, double direction) {
    final ScrollController controller = _toolScrollControllers[group]!;
    if (!controller.hasClients) return;
    final double target = (controller.offset + direction * 320).clamp(
      0,
      controller.position.maxScrollExtent,
    );
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  Future<void> _copyToolId(ToolSpec tool) async {
    await Clipboard.setData(ClipboardData(text: 'vibekits.${tool.id}'));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('智能体接口 ID 已复制')));
  }

  Future<void> _execute() async {
    final ToolSpec tool = _activeTool;
    setState(() => _executing = true);
    try {
      final ToolResult result = tool.runAsync != null
          ? await tool.runAsync!(_input.text, _params.text)
          : tool.run!(_input.text, _params.text);
      if (!mounted) return;
      setState(() {
        _executing = false;
        switch (result) {
          case ToolSuccess(:final String output):
            _output.text = output;
            _outputIsError = false;
          case ToolFailure(:final String message, :final int? position):
            _output.text = position == null
                ? message
                : '$message\n出错位置：$position';
            _outputIsError = true;
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _executing = false;
        _output.text = '执行失败：$error';
        _outputIsError = true;
      });
    }
  }

  Future<void> _copy() async {
    if (_output.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _output.text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('结果已复制')));
    }
  }

  Future<void> _pickCodeRoot() async {
    final String? path = await getDirectoryPath(confirmButtonText: '选择项目目录');
    if (path == null || !mounted) return;
    setState(() {
      _input.text = path;
      _output.clear();
      _outputIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            HardwareKeyboard.instance.isControlPressed) {
          if (!_executing) _execute();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: <Widget>[
                const Icon(Icons.auto_awesome_mosaic_outlined, size: 21),
                const SizedBox(width: 8),
                const Text(
                  '转换与检查',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                Text(
                  '同一个输入区，切换 Tab 即可换工具',
                  style: TextStyle(fontSize: 12, color: context.vibe.muted),
                ),
              ],
            ),
          ),
          TabBar(
            key: const Key('utility-category-tabs'),
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              for (final String group in _groups) Tab(text: group),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: <Widget>[
                for (final String group in _groups) _buildGroup(group),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroup(String group) {
    final List<ToolSpec> tools = utilityToolRegistry
        .where((ToolSpec tool) => tool.group == group)
        .toList(growable: false);
    final ToolSpec selected = _selectedByGroup[group]!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                key: ValueKey<String>('utility-tool-previous-$group'),
                tooltip: '向前浏览工具',
                visualDensity: VisualDensity.compact,
                onPressed: () => _scrollToolStrip(group, -1),
                icon: const Icon(Icons.chevron_left, size: 20),
              ),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: SingleChildScrollView(
                    key: ValueKey<String>('utility-tool-strip-$group'),
                    controller: _toolScrollControllers[group],
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (int index = 0; index < tools.length; index++) ...[
                          if (index > 0) const SizedBox(width: 6),
                          KeyedSubtree(
                            key: _toolKeys.putIfAbsent(
                              tools[index].id,
                              GlobalKey.new,
                            ),
                            child: ChoiceChip(
                              key: ValueKey<String>(
                                'utility-${tools[index].id}',
                              ),
                              selected: selected.id == tools[index].id,
                              showCheckmark: false,
                              label: Text(tools[index].name),
                              onSelected: (_) => _selectTool(tools[index]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: ValueKey<String>('utility-tool-next-$group'),
                tooltip: '向后浏览工具',
                visualDensity: VisualDensity.compact,
                onPressed: () => _scrollToolStrip(group, 1),
                icon: const Icon(Icons.chevron_right, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget description = Text(
                selected.description,
                style: TextStyle(color: context.vibe.muted),
              );
              final Widget agentInterface = ActionChip(
                key: const Key('utility-agent-interface'),
                avatar: const Icon(Icons.smart_toy_outlined, size: 16),
                tooltip: '复制 Harness/MCP 工具 ID',
                onPressed: () => _copyToolId(selected),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    '智能体 · vibekits.${selected.id}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              );
              if (constraints.maxWidth < 680) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    description,
                    const SizedBox(height: 6),
                    agentInterface,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: description),
                  const SizedBox(width: 12),
                  agentInterface,
                ],
              );
            },
          ),
          if (<String>{
            'code_statistics',
            'code_structure_search',
          }.contains(selected.id)) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('code-statistics-pick-directory'),
                onPressed: _executing ? null : _pickCodeRoot,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('选择项目目录'),
              ),
            ),
          ],
          if (selected.paramLabel != null) ...<Widget>[
            const SizedBox(height: 10),
            SizedBox(
              width: 360,
              child: TextField(
                controller: _params,
                decoration: InputDecoration(
                  labelText: selected.paramLabel,
                  isDense: true,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Widget input = _editor(controller: _input, hint: '输入');
                final Widget output = _editor(
                  controller: _output,
                  hint: '结果',
                  readOnly: true,
                  error: _outputIsError,
                );
                if (constraints.maxWidth >= 760) {
                  return Row(
                    children: <Widget>[
                      Expanded(child: input),
                      const SizedBox(width: 10),
                      Expanded(child: output),
                    ],
                  );
                }
                return Column(
                  children: <Widget>[
                    Expanded(child: input),
                    const SizedBox(height: 10),
                    Expanded(child: output),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              FilledButton.icon(
                key: const Key('utility-run'),
                onPressed: _executing ? null : _execute,
                icon: _executing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow, size: 18),
                label: Text(_executing ? '处理中…' : '执行  Ctrl+Enter'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _output.text.isEmpty
                    ? null
                    : () => setState(() {
                        _input.text = _output.text;
                        _output.clear();
                        _outputIsError = false;
                      }),
                child: const Text('结果作为输入'),
              ),
              const Spacer(),
              IconButton(
                tooltip: '清空',
                onPressed: () => setState(() {
                  _input.clear();
                  _params.clear();
                  _output.clear();
                  _outputIsError = false;
                }),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
              IconButton(
                tooltip: '复制结果',
                onPressed: _output.text.isEmpty ? null : _copy,
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _editor({
    required TextEditingController controller,
    required String hint,
    bool readOnly = false,
    bool error = false,
  }) {
    return TextField(
      key: ValueKey<String>('utility-${hint == '输入' ? 'input' : 'output'}'),
      controller: controller,
      readOnly: readOnly,
      expands: true,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      style: TextStyle(
        fontFamily: 'Cascadia Mono',
        fontSize: 13,
        color: error
            ? VibekitsColors.danger
            : Theme.of(context).colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        hintText: hint,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
