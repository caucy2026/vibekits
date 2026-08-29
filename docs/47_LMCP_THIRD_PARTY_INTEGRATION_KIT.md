# LMCP/1 第三方程序接入包

## 新程序

新程序应原生提供标准 MCP server，并实现 `LMCP/1` 广播。复制 `docs/schemas/lmcp-app-manifest-1.0.schema.json` 作为构建门禁；发布时使用稳定、非秘密的 `instanceId`，根据规范化 `tools/list` 生成 `capabilityDigest`。

## 旧程序或暂时不能改源码的程序

使用 Sidecar：准备应用清单，然后由任意 Node.js 18+ 进程运行：

```text
node tool/lmcp_reference_peer.mjs examples/lmcp/future-app.manifest.json
```

Sidecar 只负责发现广播，不代理、不保存也不读取 MCP 凭据。应用仍必须在声明端口提供安全 MCP 传输。发布前执行：

```text
node tool/lmcp_reference_peer.mjs examples/lmcp/future-app.manifest.json --validate-only
```

输出包含最终广播和 UTF-8 字节数；超过 1024 字节或安全字段缺失立即失败。

## 所有程序的共同完成标准

- 能被至少一个不同厂商/代码库的 LMCP 客户端发现。
- 未经目标端同意不能建立 MCP。
- 配对后标准 `initialize/tools/list/tools/call` 可用。
- 工具 Schema 足够让智能体自动填写参数，风险和副作用准确。
- 控制操作由实际执行端批准，不允许主控端代批。
- 长任务实现统一 start/status/cancel；相同 requestId 不重复执行。
- 离线、拒绝、取消、超时和部分失败均结构化返回。
- 发现包、日志、结果和错误不泄露凭据。

Harness 的协作逻辑不按应用名写死：先发现节点，再连接读取真实 `tools/list`，按能力和负载选择节点。未来应用新增工具不需要修改 VibeKits，只要 MCP Schema 和 LMCP 声明合规即可进入候选能力池。
