import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 应用级快捷键定义，对应 docs/01_WINDOWS_UI_LAYOUT.md 第 10.3 节。
abstract final class AppShortcuts {
  /// 主窗口快捷键：
  /// - `Ctrl+1`～`Ctrl+5` 切换五个一级 Tab；
  /// - `Ctrl+,` 打开设置。
  static Map<ShortcutActivator, VoidCallback> forShell({
    required void Function(int index) onSelectTab,
    required VoidCallback onOpenSettings,
    required VoidCallback onOpen,
    required VoidCallback onFind,
  }) {
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
          onSelectTab(0),
      const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
          onSelectTab(1),
      const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
          onSelectTab(2),
      const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
          onSelectTab(3),
      const SingleActivator(LogicalKeyboardKey.digit5, control: true): () =>
          onSelectTab(4),
      const SingleActivator(LogicalKeyboardKey.comma, control: true):
          onOpenSettings,
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): onOpen,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): onFind,
    };
  }
}
