import 'package:flutter/material.dart';

import 'app_settings.dart';

/// Lightweight application-owned localization layer.
///
/// Keeping product copy here avoids coupling the native Harness/plugin UI to
/// Vibekits translations. Unknown keys deliberately fall back to Simplified
/// Chinese so newly added features remain readable until their translations
/// land, instead of rendering an empty label.
class VibeLocalizations {
  const VibeLocalizations(this.locale);

  final Locale locale;

  bool get _english => locale.languageCode == 'en';
  bool get _traditional =>
      locale.languageCode == 'zh' && locale.scriptCode == 'Hant';

  static const List<Locale> supportedLocales = <Locale>[
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('en'),
  ];

  static Locale? localeFor(AppLanguage language) => switch (language) {
    AppLanguage.system => null,
    AppLanguage.simplifiedChinese => supportedLocales[0],
    AppLanguage.traditionalChinese => supportedLocales[1],
    AppLanguage.english => supportedLocales[2],
  };

  static VibeLocalizations of(BuildContext context) =>
      VibeLocalizations(Localizations.localeOf(context));

  String text(String key) {
    if (_english) return _en[key] ?? key;
    if (_traditional) return _zhHant[key] ?? key;
    return key;
  }

  static const Map<String, String> _en = <String, String>{
    '智能体（Harness）': 'Agent (Harness)',
    '解压缩': 'Archives',
    '系统清理': 'System Cleaner',
    '文档阅读': 'Documents',
    '开发工具': 'Developer Tools',
    '应用中心': 'App Center',
    '关于我们': 'About',
    '开发智能体（Harness）、任务会话与截图识别（OCR）':
        'Developer agent (Harness), task sessions, and screenshot OCR',
    '安全查看、创建与提取压缩文件': 'Safely inspect, create, and extract archives',
    '扫描可清理空间并生成可核对报告': 'Scan reclaimable storage and produce auditable reports',
    '快速查看文本、结构化数据与二进制文件':
        'Quickly inspect text, structured data, and binary files',
    '独立开发工作区与转换检查工具':
        'Independent workspaces, converters, and inspection tools',
    '浏览和安装适用于当前系统的 KEMI 市场应用':
        'Browse and install KEMI Market apps for this platform',
    '产品信息、当前版本能力与隐私说明':
        'Product information, current capabilities, and privacy',
    '隐私优先': 'Privacy first',
    '设置': 'Settings',
    '主题': 'Theme',
    '语言': 'Language',
    '跟随系统': 'Follow system',
    '简体中文': 'Simplified Chinese',
    '繁體中文': 'Traditional Chinese',
    'English': 'English',
    '浅色': 'Light',
    '深色': 'Dark',
    '恢复上次打开的标签页': 'Restore the last open tab',
    '日志级别': 'Log level',
    '取消': 'Cancel',
    '保存': 'Save',
    '关闭': 'Close',
    '刷新应用列表': 'Refresh app list',
    '搜索应用名称或简介': 'Search apps by name or description',
    '搜索': 'Search',
    '全部': 'All',
    '当前系统': 'this platform',
    '应用': 'Apps',
    '应用列表加载失败': 'Could not load apps',
    '重新加载': 'Reload',
    '暂无符合条件的应用': 'No matching apps',
    '市场还没有上架当前系统应用。': 'No apps for this platform are published yet.',
    '换一个关键词再试试。': 'Try another search term.',
    '暂无简介': 'No description',
    '暂无详细介绍': 'No detailed description',
    '版本': 'Version',
    '评分': 'Rating',
    '开发者包名': 'Package ID',
    '下载量': 'Downloads',
    '该条目缺少完整的 HTTPS、文件大小或 SHA-256 信息，已禁止安装。':
        'Installation is disabled because HTTPS URL, file size, or SHA-256 metadata is incomplete.',
    '当前已是最新版本，无需重复下载。': 'You already have the latest version.',
    '已是最新版': 'Up to date',
    '下载并安装': 'Download and install',
    '正在下载并验证安装包…': 'Downloading and verifying the installer…',
    '校验通过，已交给系统打开': 'Verified and opened with the system installer',
    '当前版本能力': 'Current capabilities',
    '以下项目来自当前应用导航和已交付工具，不包含规划中或未经验证的能力。':
        'These items come from the current navigation and shipped tools; planned or unverified capabilities are excluded.',
    '本地优先的智能体与工程工具箱': 'A local-first agent and engineering toolkit',
    '正在准备系列产品内容…': 'Preparing product content…',
    '系列产品资源': 'Product family media',
    '让智能体调用真实工程能力': 'Let the agent use real engineering capabilities',
    '统一使用本机工具和经过授权的局域网 MCP，保留调用过程、结果证据与停止控制。当前网络不可用，已安全显示内置产品信息。':
        'Use local tools and authorized LAN MCP services through one interface, with visible execution, evidence, and stop controls. The network is unavailable, so built-in product information is shown safely.',
    '能力全景': 'Capability overview',
    '数字直接来自应用正在使用的格式路由表和工具注册表，新增或移除能力时会同步变化。':
        'Counts come directly from the active format router and tool registry and stay synchronized as capabilities change.',
    '文件扩展名': 'File extensions',
    '特殊文件名': 'Special filenames',
    '独立工作区': 'Independent workspaces',
    'Harness 工具入口': 'Harness tool entries',
    '支持格式与自有数据说明': 'Supported formats and proprietary data',
    '按实际路由清单逐项列出。点击分类可查看完整扩展名；未登记格式不会在这里被宣传为已支持。':
        'Generated from the real routing table. Expand a category to see every extension; unregistered formats are never advertised as supported.',
    '全部开发工具': 'All developer tools',
    '按开发工具页的真实注册表分组；每项标明用途以及需要联网还是可本地运行。':
        'Grouped from the developer-tools registry, with purpose and offline/network requirements for every item.',
    '本地可用': 'Available offline',
    '需要网络或外部设备': 'Requires network or external hardware',
    '隐私与联网：文件默认在本机处理。应用启动后低优先级检查已授权的同系列产品图片；只显示通过 HTTPS、大小、MD5、格式和解码校验的本地缓存，失败时继续使用上次完整缓存或内置内容。':
        'Privacy and network: files are processed locally by default. The app checks authorized product-family images at low priority after startup and displays only cached media that passes HTTPS, size, MD5, format, and decoding checks. On failure it keeps the last complete cache or built-in content.',
    '智能体与扩展': 'Agent and extensions',
    'MCP 协同': 'MCP orchestration',
    '压缩文件': 'Archives',
    '文档与数据': 'Documents and data',
    '保留官方 Harness 的项目、独立会话、草稿、并行任务、停止、权限、Skills、设置与插件生态。':
        'Preserves the official Harness projects, independent sessions, drafts, parallel tasks, stop controls, permissions, Skills, settings, and plugin ecosystem.',
    '发现本机与局域网能力，完成身份与证书校验、持久授权、空闲实例调度、异步结果查询和证据验真。':
        'Discovers local and LAN capabilities with identity and certificate checks, persistent authorization, idle-instance scheduling, asynchronous results, and evidence verification.',
    '查看、创建、提取与校验压缩包；执行路径穿越、容量、文件数量和覆盖策略边界检查。':
        'Inspect, create, extract, and verify archives with path-traversal, capacity, entry-count, and overwrite-policy checks.',
    '扫描缓存、日志及临时文件，先生成可核对计划，再执行受控清理，避免误删用户数据。':
        'Scans caches, logs, and temporary files, creates a reviewable plan, then performs controlled cleanup without deleting user data by mistake.',
    '读取文本、源码、配置、Office、PDF、图片、数据库、模型和音频等已登记格式。':
        'Reads registered text, source, configuration, Office, PDF, image, database, model, and audio formats.',
    '覆盖 ADB、网络测速与诊断、数据库、串口、音频、转换、哈希、时间及工程计算；下方提供完整清单。':
        'Includes ADB, network speed and diagnostics, databases, serial, audio, conversion, hashing, time, and engineering calculations; the full inventory appears below.',
  };

  static const Map<String, String> _zhHant = <String, String>{
    '智能体（Harness）': '智能體（Harness）',
    '解压缩': '解壓縮',
    '系统清理': '系統清理',
    '文档阅读': '文件閱讀',
    '开发工具': '開發工具',
    '应用中心': '應用中心',
    '关于我们': '關於我們',
    '开发智能体（Harness）、任务会话与截图识别（OCR）': '開發智能體（Harness）、任務會話與截圖識別（OCR）',
    '安全查看、创建与提取压缩文件': '安全檢視、建立與解壓縮檔案',
    '扫描可清理空间并生成可核对报告': '掃描可清理空間並產生可核對報告',
    '快速查看文本、结构化数据与二进制文件': '快速檢視文字、結構化資料與二進位檔案',
    '独立开发工作区与转换检查工具': '獨立開發工作區與轉換檢查工具',
    '浏览和安装适用于当前系统的 KEMI 市场应用': '瀏覽並安裝適用於目前系統的 KEMI 市場應用',
    '产品信息、当前版本能力与隐私说明': '產品資訊、目前版本能力與隱私說明',
    '隐私优先': '隱私優先',
    '设置': '設定',
    '主题': '主題',
    '语言': '語言',
    '跟随系统': '跟隨系統',
    '简体中文': '簡體中文',
    '浅色': '淺色',
    '深色': '深色',
    '恢复上次打开的标签页': '恢復上次開啟的分頁',
    '日志级别': '記錄層級',
    '取消': '取消',
    '保存': '儲存',
    '关闭': '關閉',
    '刷新应用列表': '重新整理應用列表',
    '搜索应用名称或简介': '搜尋應用名稱或簡介',
    '搜索': '搜尋',
    '全部': '全部',
    '当前系统': '目前系統',
    '应用': '應用',
    '应用列表加载失败': '應用列表載入失敗',
    '重新加载': '重新載入',
    '暂无符合条件的应用': '暫無符合條件的應用',
    '市场还没有上架当前系统应用。': '市場尚未上架目前系統的應用。',
    '换一个关键词再试试。': '換一個關鍵字再試試。',
    '暂无简介': '暫無簡介',
    '暂无详细介绍': '暫無詳細介紹',
    '版本': '版本',
    '评分': '評分',
    '开发者包名': '開發者套件名稱',
    '下载量': '下載量',
    '当前已是最新版本，无需重复下载。': '目前已是最新版本，無需重複下載。',
    '已是最新版': '已是最新版',
    '下载并安装': '下載並安裝',
    '正在下载并验证安装包…': '正在下載並驗證安裝套件…',
    '校验通过，已交给系统打开': '驗證通過，已交由系統開啟',
    '当前版本能力': '目前版本能力',
    '以下项目来自当前应用导航和已交付工具，不包含规划中或未经验证的能力。': '以下項目來自目前應用導覽和已交付工具，不包含規劃中或未經驗證的能力。',
    '本地优先的智能体与工程工具箱': '本機優先的智能體與工程工具箱',
    '正在准备系列产品内容…': '正在準備系列產品內容…',
    '系列产品资源': '系列產品資源',
    '让智能体调用真实工程能力': '讓智能體呼叫真實工程能力',
    '统一使用本机工具和经过授权的局域网 MCP，保留调用过程、结果证据与停止控制。当前网络不可用，已安全显示内置产品信息。':
        '統一使用本機工具和經過授權的區域網路 MCP，保留呼叫過程、結果證據與停止控制。目前網路不可用，已安全顯示內建產品資訊。',
    '能力全景': '能力全景',
    '数字直接来自应用正在使用的格式路由表和工具注册表，新增或移除能力时会同步变化。':
        '數字直接來自應用正在使用的格式路由表和工具註冊表，新增或移除能力時會同步變化。',
    '文件扩展名': '檔案副檔名',
    '特殊文件名': '特殊檔名',
    '独立工作区': '獨立工作區',
    'Harness 工具入口': 'Harness 工具入口',
    '支持格式与自有数据说明': '支援格式與自有資料說明',
    '按实际路由清单逐项列出。点击分类可查看完整扩展名；未登记格式不会在这里被宣传为已支持。':
        '按實際路由清單逐項列出。點擊分類可查看完整副檔名；未登記格式不會在這裡宣稱為已支援。',
    '全部开发工具': '全部開發工具',
    '按开发工具页的真实注册表分组；每项标明用途以及需要联网还是可本地运行。':
        '按開發工具頁的真實註冊表分組；每項標明用途以及需要連網還是可本機執行。',
    '本地可用': '本機可用',
    '需要网络或外部设备': '需要網路或外部裝置',
    '保留官方 Harness 的项目、独立会话、草稿、并行任务、停止、权限、Skills、设置与插件生态。':
        '保留官方 Harness 的專案、獨立會話、草稿、平行任務、停止、權限、Skills、設定與外掛生態。',
    '发现本机与局域网能力，完成身份与证书校验、持久授权、空闲实例调度、异步结果查询和证据验真。':
        '探索本機與區域網路能力，完成身分與憑證驗證、持久授權、閒置實例調度、非同步結果查詢和證據驗真。',
    '查看、创建、提取与校验压缩包；执行路径穿越、容量、文件数量和覆盖策略边界检查。':
        '檢視、建立、提取與驗證壓縮檔；執行路徑穿越、容量、檔案數量和覆寫策略邊界檢查。',
    '扫描缓存、日志及临时文件，先生成可核对计划，再执行受控清理，避免误删用户数据。':
        '掃描快取、記錄及暫存檔，先產生可核對計畫，再執行受控清理，避免誤刪使用者資料。',
    '读取文本、源码、配置、Office、PDF、图片、数据库、模型和音频等已登记格式。':
        '讀取文字、原始碼、設定、Office、PDF、圖片、資料庫、模型和音訊等已登記格式。',
    '覆盖 ADB、网络测速与诊断、数据库、串口、音频、转换、哈希、时间及工程计算；下方提供完整清单。':
        '涵蓋 ADB、網路測速與診斷、資料庫、序列埠、音訊、轉換、雜湊、時間及工程計算；下方提供完整清單。',
    '智能体与扩展': '智能體與擴充功能',
    'MCP 协同': 'MCP 協同',
    '压缩文件': '壓縮檔案',
    '文档与数据': '文件與資料',
  };
}

extension VibeLocalizationContext on BuildContext {
  VibeLocalizations get l10n => VibeLocalizations.of(this);
}
