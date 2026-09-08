import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/app/app_localizations.dart';
import 'package:vibekits/app/app_settings.dart';

void main() {
  test('语言设置映射为稳定 Locale', () {
    expect(VibeLocalizations.localeFor(AppLanguage.system), isNull);
    expect(
      VibeLocalizations.localeFor(AppLanguage.simplifiedChinese),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    );
    expect(
      VibeLocalizations.localeFor(AppLanguage.traditionalChinese),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    expect(
      VibeLocalizations.localeFor(AppLanguage.english),
      const Locale('en'),
    );
  });

  test('三种语言提供导航与核心操作文案', () {
    const List<String> keys = <String>[
      '智能体（Harness）',
      '应用中心',
      '关于我们',
      '设置',
      '下载并安装',
    ];
    final List<VibeLocalizations> languages = <VibeLocalizations>[
      const VibeLocalizations(
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      ),
      const VibeLocalizations(
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ),
      const VibeLocalizations(Locale('en')),
    ];
    for (final VibeLocalizations language in languages) {
      for (final String key in keys) {
        expect(language.text(key), isNotEmpty);
      }
    }
    expect(languages.last.text('应用中心'), 'App Center');
    expect(languages[1].text('关于我们'), '關於我們');
  });
}
