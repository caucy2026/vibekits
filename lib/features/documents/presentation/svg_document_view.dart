import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// SVG 安全渲染视图（docs/00 §5.4，DOC-204）。
///
/// 使用 `flutter_svg` 本地渲染，不执行脚本、不加载外部资源。
class SvgDocumentView extends StatelessWidget {
  const SvgDocumentView({super.key, required this.svgText});

  final String svgText;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InteractiveViewer(
        maxScale: 8,
        child: SvgPicture.string(svgText, fit: BoxFit.contain),
      ),
    );
  }
}
