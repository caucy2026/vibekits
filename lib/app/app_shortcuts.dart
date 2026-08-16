import 'dart:io';

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
    required VoidCallback onSave,
  }) {
    SingleActivator primary(LogicalKeyboardKey key) => SingleActivator(
      key,
      control: !Platform.isMacOS,
      meta: Platform.isMacOS,
    );
    return <ShortcutActivator, VoidCallback>{
      primary(LogicalKeyboardKey.digit1): () => onSelectTab(0),
      primary(LogicalKeyboardKey.digit2): () => onSelectTab(1),
      primary(LogicalKeyboardKey.digit3): () => onSelectTab(2),
      primary(LogicalKeyboardKey.digit4): () => onSelectTab(3),
      primary(LogicalKeyboardKey.digit5): () => onSelectTab(4),
      primary(LogicalKeyboardKey.comma): onOpenSettings,
      primary(LogicalKeyboardKey.keyO): onOpen,
      primary(LogicalKeyboardKey.keyF): onFind,
      primary(LogicalKeyboardKey.keyS): onSave,
    };
  }
}
