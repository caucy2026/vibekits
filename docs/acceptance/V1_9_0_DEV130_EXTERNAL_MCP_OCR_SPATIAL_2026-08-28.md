# v1.9.0-dev.130 外部智能体 MCP 与 OCR 空间理解验收

日期：2026-08-28
版本：`1.9.0-dev.130+2130`

## 交付结果

1. 任意支持 stdio MCP 的外部智能体可通过 `tool/start_vibekits_mcp.ps1` 发现并调用与内置 Harness 相同的 VibeKits 工具。
2. 底层 APP 桥仅监听 `127.0.0.1`，使用随机 Bearer Token；客户端不接触 DeepSeek API Key。
3. `docs/37_HARNESS_CAPABILITY_CATALOG.md` 从实际注册表生成，包含内部 ID、真实 MCP 名称、用途、风险和参数；发布测试自动重写并核对文档，不让文档生成拖慢或阻断正常 APP 构建。
4. 截图 OCR 返回像素位置和分辨率无关的位置，供没有多模态视觉的 Harness 理解页面空间。

## OCR 返回合同

```json
{
  "coordinateSystem": {
    "origin": "top-left",
    "relativeUnit": "0..1",
    "readingOrder": "top-to-bottom,left-to-right"
  },
  "spatialText": "[top-left] 设置",
  "lines": [
    {
      "index": 1,
      "text": "设置",
      "confidence": 0.98,
      "boundsPx": {"left": 20, "top": 10, "right": 100, "bottom": 42},
      "boundsRelative": {
        "left": 0.01,
        "top": 0.01,
        "right": 0.05,
        "bottom": 0.04,
        "centerX": 0.03,
        "centerY": 0.025
      },
      "region": "top-left"
    }
  ]
}
```

旧 `bounds` 字段继续保留，已有 Harness 会话不需要迁移。

## 模型结论

- 最大参数高精度组合：`PP-OCRv6_medium_det` 15.5M + `PP-OCRv6_medium_rec` 19M，共 34.5M。
- 桌面：Medium 为高精度档，设置中的模型管理可主动安装；三文件全部按官方 SHA-256 校验并事务导入后自动优先使用，缺失时立即回退 Tiny。
- Android：Tiny 为默认档；Medium 不进入基础 APK，避免约 139 MB 模型增加安装、内存和首次推理成本。

## 验收证据

| 项目 | 结果 |
| --- | --- |
| 能力目录生成、注册表一致性、Harness 注入 | 4/4 通过 |
| OCR 坐标、越界钳制、字典、CTC、官方图片真实推理 | 5/5 通过 |
| 环回令牌、HTTP 调用、审批、内置 Node MCP | 5/5 通过 |
| Tiny/Medium 模型供应链锁定 | 2/2 通过 |
| 截图后自动 OCR 工作区组件 | 1/1 通过 |
| Windows Release 构建 | 通过，`build/windows/x64/runner/Release/vibekits.exe` |

新 Release 已以 `--open-harness` 启动，验收时进程 PID 为 15060。

静态 Analyze 在依赖分析阶段长时间无输出后人工取消；上述定向测试均编译本次变更并通过，不把取消的 Analyze 伪报为通过。
