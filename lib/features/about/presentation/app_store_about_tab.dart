import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/app_distribution.dart';
import '../../../app/app_version.dart';

/// About page for the offline Mac App Store edition.
///
/// The copy intentionally describes only features reachable in this target.
class AppStoreAboutTab extends StatelessWidget {
  const AppStoreAboutTab({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('app-store-about-page'),
    color: context.vibe.canvas,
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 34),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Vibekits',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text('本地文件工具箱', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                AppDistribution.macAppStoreDisplayVersion.isEmpty
                    ? AppVersion.display
                    : 'v${AppDistribution.macAppStoreDisplayVersion}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 28),
              const _StoreCapability(
                icon: Icons.folder_zip_outlined,
                title: '压缩文件',
                description: '查看和安全提取 ZIP、TAR、GZ、BZ2 与 XZ，并在覆盖前给出明确选择。',
              ),
              const SizedBox(height: 12),
              const _StoreCapability(
                icon: Icons.article_outlined,
                title: '文档阅读',
                description: '读取文本、源码、Markdown、JSON、XML、CSV、SVG、EPUB 与二进制文件。',
              ),
              const SizedBox(height: 12),
              const _StoreCapability(
                icon: Icons.shield_outlined,
                title: '隐私与本地处理',
                description: '文件只在本机处理；应用仅访问你主动选择的文件。',
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.vibe.panelRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.vibe.border),
                ),
                child: const Text(
                  '使用方法：选择左侧“解压缩”或“文档阅读”，再通过页面中的“打开”按钮选择本机文件。Vibekits 只访问你明确选择的文件。',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _StoreCapability extends StatelessWidget {
  const _StoreCapability({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 5),
                Text(description),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
