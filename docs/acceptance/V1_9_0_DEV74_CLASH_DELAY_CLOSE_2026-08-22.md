# v1.9.0-dev.74 Clash 测速与关闭验收

- 顶部运行态显示“全部测速”：PASS。
- 顶部运行态显示“关闭代理”：PASS。
- 每个代理组提供单组测速：PASS。
- 节点显示延迟或超时：PASS。
- 全量测速最多 6 路并发且不阻塞关闭：PASS。
- 关闭代理取消测速、停止 Mihomo、恢复 Windows 原代理：PASS。
- Mihomo `/delay` 接口定向测试：PASS。
- 用户真实 32 节点 Profile 延迟请求：PASS，整项 6 秒。
- Windows Release：`1.9.0-dev.74+84`。
- EXE SHA-256：`7B13440CC7AE129C2267D4FBCF9645409CC69D9C1B17B70C64C42E2A68471A0E`。

失败标准：按钮仅改变 UI、不调用 Mihomo；测速时不能关闭；停止后 Windows 仍指向 Vibekits 代理端口。
