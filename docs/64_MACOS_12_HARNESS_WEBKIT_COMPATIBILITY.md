# macOS 12 至 14.3 Harness WebKit 兼容性说明

状态：已完成根因定位和macOS 12.6.4 Intel实机验证；全部兼容改动已进入 `main`，商城版 `1.9.0-dev.164+2164`已通过真实App聊天与MCP验收。

适用范围：Vibekits 内置 DeepSeek Harness Web，macOS 12.x、13.x及14.0至14.3。产品最低系统为macOS 12.0，因此不处理macOS 11及更早版本。

## 1. 现象

在较新的 Mac 上，同一份 Harness runtime 可以直接运行；在 macOS 12.6.4 Intel Mac 上依次出现：

1. Harness Web 白屏或不能完成初始化。
2. 页面能显示后，模型长期停在“正在加载模型…”。
3. 选择目录后提示 `directory picker failed: client api: directoryPicker/pick failed: Load failed`。
4. 修复目录选择请求后，目录选择器能返回，但界面长期停在“正在加载工作区…”。
5. 智能体不能从 App 聊天框形成完整的用户消息、工具调用和回复记录。

API Key 不是本次故障根因。相同 Key 的独立推理能够成功；修复Web兼容层后，App 内同一Key也能完成推理和MCP调用。

## 2. 根因

这是Safari 17.4以前的WKWebView与当前DSH浏览器端代码之间的三层兼容问题。其中XHR的 `Load failed` 已在macOS 12.6.4实机复现；`AbortSignal.any()`缺失覆盖Safari 17.3及更早版本。

| 层次 | 旧系统行为 | 结果 | 补丁 |
|---|---|---|---|
| JavaScript语法 | 官方主前端和动态 `client.js` 含Safari 15不能解析的现代语法 | 白屏、插件不加载、模型状态不完整 | 用esbuild `target: safari15`生成独立兼容副本 |
| 一元JSON RPC | `dsh-client-connection`默认通过 `globalThis.fetch`访问本地同源RPC；该机WKWebView返回系统级 `Load failed` | `directoryPicker/pick`等RPC失败 | 仅兼容副本使用 `XMLHttpRequest`适配Fetch所需的最小响应接口 |
| 事件流初始化 | `dsh-api-gateway`调用 `AbortSignal.any()`；该API在Safari 17.4才提供 | WebSocket事件流不能初始化，工作区和会话投影不更新 | 仅兼容副本用 `AbortController`组合多个AbortSignal |

目录选择器能弹出，证明 `directoryPicker/pick`已经到达Host；选中后仍停在“正在加载工作区”，进一步把第二个卡点定位到工作区投影依赖的事件流，而不是文件权限或路径本身。

## 3. 兼容方案

### 3.1 构建期双份产物

`tool/prepare_harness_runtime_macos.sh`保留官方文件，并额外生成以下历史命名的兼容产物。`macos12`是首次引入时的产物名，不代表运行期只允许macOS 12使用：

- 官方主前端：`dsh-web-frontend/dist`
- macOS 12主前端：`dsh-web-frontend/dist-macos12`
- 官方动态插件：`@deepseek-ai/*/lib/client.js`
- macOS 12动态插件：`@deepseek-ai/*/lib/client.macos12.js`

`tool/transpile_harness_web_macos.mjs`只写入 `dist-macos12`和 `.macos12.js`。官方 `dist`及 `client.js`不被转译或覆盖。

### 3.2 运行期按系统分流

`harnessLegacyWebKitDistIndex()`只在当前平台是macOS且系统版本属于以下范围时返回兼容入口：

- macOS 12.x；
- macOS 13.x；
- macOS 14.0至14.3。

此时App向DSH进程设置 `VIBEKITS_DSH_WEB_DIST_INDEX`。DSH Web加载 `dist-macos12`，动态模块加载器把 `client.js`映射到 `client.macos12.js`。

未设置该变量时，所有代码继续使用DSH官方路径。这包括：

- macOS 14.4及以上；
- 无法可靠识别版本的macOS；
- Windows、Linux及其他平台。

采用保守回退：若macOS 14只有主版本而没有可解析的小版本，不猜测为14.0，也不启用兼容补丁。

## 4. 为macOS 12编译和运行通过所做的改动

### 4.1 编译目标和Universal运行时

- `macos/Podfile`、Xcode工程和 `Info.plist`把最低系统统一为macOS 12.0。
- `tool/prepare_harness_runtime_macos.sh`准备Universal Node/DSH运行时；发布包同时包含 `x86_64`和 `arm64`。
- `tool/verify_macos_release_compat.sh`扫描App及内置Mach-O，拒绝缺少架构或最低系统版本高于12.0的产物。
- `.github/workflows/macos-release.yml`在GitHub构建中执行运行时准备、兼容文件完整性、Flutter测试和Release兼容检查。

### 4.2 Node、V8和签名

- `macos/Runner/HarnessNode.entitlements`为Developer ID签名的Node保留 `allow-jit`和 `allow-unsigned-executable-memory`。
- `macos/Runner/HarnessNodeAdHoc.entitlements`在上述权限外仅为本地ad-hoc验证增加 `disable-library-validation`。
- `tool/package_harness_runtime_macos.sh`、`tool/sign_macos_release.sh`和 `tool/sign_macos_developer_id.sh`对内置Node单独签名，避免Hardened Runtime下V8初始化触发 `SIGTRAP`。
- `deepseek_harness_service.dart`在macOS使用真实运行参数 `--expose-internals`，不再使用会禁用WebAssembly并导致Undici失败的 `--jitless`。
- `tool/verify_macos_harness_signed_runtime.sh`验证两个V8权限，并在Intel路径按App真实参数启动DSH，而不是仅执行 `node --version`。

### 4.3 WKWebView和Harness Web

- `tool/transpile_harness_web_macos.mjs`以esbuild `target: safari15`生成独立的 `dist-macos12`主前端和48个 `client.macos12.js`动态插件。
- 仅在 `dsh-client-connection`兼容副本中使用XHR，解决WKWebView本地同源Fetch的 `Load failed`。
- 仅在 `dsh-api-gateway`兼容副本中用 `AbortController`组合Signal，替代Safari 17.4以前缺失的 `AbortSignal.any()`。
- 上游目标代码不存在时立即构建失败，避免升级DSH后静默生成不完整兼容产物。
- `deepseek_harness_service.dart`只为macOS 12.x、13.x及14.0至14.3设置兼容入口；14.4+、版本未知和非macOS继续使用官方资源。

### 4.4 自动化回归和改动边界

- `test/harness_macos_compatibility_test.dart`覆盖版本分流、官方/兼容资源隔离、XHR和Abort实现。
- `test/harness_tool_server_test.dart`覆盖macOS Node启动参数，防止重新引入 `--jitless`。
- 官方DSH `dist`和 `client.js`保持不变；不修改DSH业务协议、MCP服务器、模型选择逻辑、会话格式或其他平台启动逻辑。

对应Git提交：

- `0bbfe20`：隔离Monterey兼容资源、Node签名权限、构建和CI门禁；
- `366de71`：补齐动态插件Safari 15转译；
- `c1b48ca`：补齐XHR、`AbortSignal.any()`兼容和macOS 12至14.3版本分流。

## 5. 版本影响矩阵

| 运行环境 | 主前端 | 动态插件 | RPC/Abort实现 | 预期影响 |
|---|---|---|---|---|
| macOS 12.x | `dist-macos12` | `client.macos12.js` | XHR + AbortController组合 | 修复已实机复现的问题 |
| macOS 13.x | `dist-macos12` | `client.macos12.js` | XHR + AbortController组合 | 兼容Safari 16及可升级WebKit |
| macOS 14.0至14.3 | `dist-macos12` | `client.macos12.js` | XHR + AbortController组合 | 兼容缺少 `AbortSignal.any()` 的Safari 17.0至17.3 |
| macOS 14.4+ | 官方 `dist` | 官方 `client.js` | 官方Fetch + 原生API | 无行为变化 |
| macOS版本未知 | 官方 `dist` | 官方 `client.js` | 官方实现 | 无行为变化 |
| 非macOS | 官方路径 | 官方路径 | 官方实现 | 无行为变化 |

兼容副本增加安装包体积，但不会改变新系统执行路径。

## 6. 发布门禁

提交和发布前必须通过：

1. 重新执行 `./tool/prepare_harness_runtime_macos.sh`，确保补丁基于当前锁定DSH版本重新生成。
2. 执行 `flutter test --no-pub test/harness_macos_compatibility_test.dart`。
3. 验证官方与兼容文件同时存在，且官方文件未包含XHR兼容代码。
4. 验证macOS 12.x、13.x和14.0至14.3选择兼容入口；14.4+、未知版本和非macOS选择官方入口。
5. 打包后执行 `codesign --verify --deep --strict`。
6. 在macOS 12真实App内完成：显示工作区名称、显示具体模型、聊天框发送命令、产生工具调用和智能体回复。
7. CI继续执行 `.github/workflows/macos-release.yml`中的兼容文件完整性检查和Flutter测试。

## 7. 本机验收证据

环境：macOS 12.6.4、Intel Mac、Vibekits内置WKWebView。

完成兼容补丁后，真实用户路径得到以下结果：

- 聊天页可见工作区 `vibekits`；
- 模型显示 `DeepSeek-V4-Flash High`，不再停在加载状态；
- 通过聊天框发送MCP数量查询，消息进入同一App聊天记录；
- 智能体完成6次工具调用、3条消息，用时约41秒；
- 会话投影与压缩会话日志均产生更新。

该验收不是独立headless进程测试，覆盖了WKWebView、RPC、WebSocket事件流、模型、聊天记录和MCP调用的完整App路径。

## 8. 后续维护

升级 `@deepseek-ai/dsh`时，先运行构建脚本。若被替换的上游目标文本变化，构建会失败，必须重新审查而不能放宽为模糊替换。

当产品最低macOS版本提升，或上游DSH明确提供Safari 15兼容实现后，可按以下顺序移除补丁：

1. 在macOS 12实机验证上游主前端和全部动态插件。
2. 验证本地RPC不再出现 `Load failed`。
3. 验证工作区/会话事件流不依赖缺失Web API。
4. 删除兼容分流与副本生成逻辑。
5. 保留一轮发布周期的官方路径回归测试。
