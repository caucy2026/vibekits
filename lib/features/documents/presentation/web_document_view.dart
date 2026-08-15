import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../../app/app_theme.dart';
import '../domain/web_sanitize.dart';

/// 隔离只读的 Web 文档视图（HTML/EPUB 章节），基于 WebView2。
///
/// 通过注入 CSP 禁止脚本与外部资源（docs/00 §5.4）。
class WebDocumentView extends StatefulWidget {
  const WebDocumentView({
    super.key,
    required this.html,
    this.chapterCount = 0,
    this.chapterIndex = 0,
    this.onPrevious,
    this.onNext,
  });

  final String html;
  final int chapterCount;
  final int chapterIndex;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  State<WebDocumentView> createState() => _WebDocumentViewState();
}

class _WebDocumentViewState extends State<WebDocumentView> {
  WebviewController? _controller;
  bool _ready = false;
  String _loadedHtml = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final WebviewController controller = WebviewController();
    try {
      await controller.initialize();
      _controller = controller;
      _loadedHtml = WebSanitize.injectCsp(WebSanitize.sanitize(widget.html));
      await controller.loadStringContent(_loadedHtml);
      if (mounted) {
        setState(() => _ready = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _ready = true); // 显示错误态
      }
      debugPrint('WebView 初始化失败: $e');
    }
  }

  @override
  void didUpdateWidget(WebDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html && _controller != null && _ready) {
      _loadedHtml = WebSanitize.injectCsp(WebSanitize.sanitize(widget.html));
      _controller!.loadStringContent(_loadedHtml);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: _ready
              ? Webview(_controller!)
              : const Center(child: CircularProgressIndicator()),
        ),
        if (widget.chapterCount > 1) _buildChapterBar(),
      ],
    );
  }

  Widget _buildChapterBar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: VibekitsColors.surface,
        border: Border(top: BorderSide(color: VibekitsColors.divider)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: widget.chapterIndex > 0 ? widget.onPrevious : null,
          ),
          Text(
            '${widget.chapterIndex + 1} / ${widget.chapterCount}',
            style: const TextStyle(
              fontSize: 12,
              color: VibekitsColors.textSecondary,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: widget.chapterIndex + 1 < widget.chapterCount
                ? widget.onNext
                : null,
          ),
        ],
      ),
    );
  }
}
