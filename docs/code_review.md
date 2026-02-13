# Code Review

本文档记录一次面向「准备继续迭代」的整体 Code Review，重点覆盖：

- 明显的架构不足
- 设计方面的缺陷（产品/交互/可维护性/可观测性）

Review 范围以 iOS 端为主（`OpenCodeClient/`），以及与 OpenCode server API/SSE 的契合度。

## 1. 明显的架构不足

### 1.1 `AppState` 过于“上帝对象”

`OpenCodeClient/OpenCodeClient/AppState.swift` 同时承担：

- 连接配置（URL/用户名密码）
- REST 调用（通过 `APIClient`）
- SSE 生命周期管理（连接/断开/事件分发）
- Session / Message / Diff / FileTree / Todo 的状态与缓存
- 发送后的轮询策略

问题：

- 单文件/单类型职责过多，后续加功能时容易“牵一发动全身”
- 难以单测：大部分逻辑绑定在 `@MainActor` + 实网调用 + 定时轮询上
- 事件处理和 UI 状态更新耦合，未来做 streaming/delta 合并会更难

建议：

- 拆出更细的 domain store：`SessionStore` / `MessageStore` / `FileStore` / `TodoStore`
- SSE 事件先在一个非 UI 的 reducer 层做「解析/过滤/归并」，再更新 store
- 将轮询与重试策略从 state 中抽成 `SyncCoordinator`

### 1.2 SSE 解析与重连策略偏“最小可用”，鲁棒性不足

`OpenCodeClient/OpenCodeClient/Services/SSEClient.swift`：

- 仅按单行 `\n` 处理 `data:`，未覆盖 SSE 规范里的多行 data、`event:`、空行分隔、comment keep-alive（":" 开头）等
- 没有指数退避/重连策略（断网/切后台/服务端重启时体验会抖）
- `AsyncThrowingStream` 内部启动的 `Task` 没和 `continuation.onTermination` 绑定，长期看更难控制资源

建议：

- 按 SSE 标准以 event 为单位解析（以空行 `\n\n` 作为 event 结束）
- 增加重连：指数退避 + 最大间隔 + 前台恢复时快速重连
- 建议加 `Accept: text/event-stream`、`Cache-Control: no-cache`

### 1.3 SSE 事件未按 session 过滤导致潜在的跨 session 污染

`AppState.handleSSEEvent` 在 `message.updated` / `message.part.updated` 上只判断 `currentSessionID != nil` 就触发 `loadMessages()`，没有检查 event 是否属于当前 session。

问题：

- 多 session 并发时，会频繁拉取“当前 session”但事件可能来自其他 session
- 不必要的网络开销与 UI 抖动

建议：

- 参考 `opencode-official` 的处理方式：基于 event properties 的 `sessionID/messageID` 做过滤
- 如果服务端 event payload 不含 sessionID，需要在 SSE 解析层补齐（或回退到定时 sync）

### 1.4 “文件/跳转路径”属于跨模块的协议，应该单独建一个统一的规范化层

目前路径规范化散落在 `Message.swift` 的 `normalizedFilePathForAPI()`、以及视图里对 path 的 `trim`。

建议：

- 抽到 `PathNormalizer` / `FilePath` 类型，统一处理：`a/` `b/` 前缀、`#L..`、`:line:col`、URL 编码等
- 增加对异常 path 的可观测性：当 server 返回 empty content 时记录 request url/path 以及响应摘要

## 2. 设计方面的缺陷

### 2.1 连接配置与凭证存储缺失（与 RFC/PRD 不一致）

RFC/PRD 提到 UserDefaults + Keychain，但代码里 `username/password/serverURL` 仅存在内存态。

影响：

- App 重启丢配置
- 体验割裂，且容易误以为“已保存”

建议：

- `serverURL/username` 使用 `@AppStorage`
- `password` 使用 Keychain（最少做：保存/读取/清除；并在 UI 里明确）

### 2.2 Chat 的可选中与交互冲突风险

Chat 区域使用 `.textSelection(.enabled)` 能解决复制问题，但会改变滚动/点击手势的优先级。

风险点：

- 长按选择文字可能干扰按钮点击（尤其在 tool 卡片/patch 卡片密集区域）
- 移除了“点空白收键盘”，可能让键盘收起变得不直观

建议：

- 保持选择能力，但考虑补一个显式的「Done/收起键盘」入口
- 对按钮区域（工具卡片的按钮）验证手势冲突，必要时对局部禁用 selection 或增加 hit testing 策略

### 2.3 `ChatTabView.swift` 体积过大，可维护性下降 ✅ 已拆分

已拆至 `Views/Chat/`：`ChatTabView.swift`、`MessageRowView.swift`、`ToolPartView.swift`、`PatchPartView.swift`、`PermissionCardView.swift`、`StreamingReasoningView.swift`、`TodoListInlineView.swift`。原 `Views/ChatTabView.swift` 集中定义了大量子 View（消息行、tool 卡片、patch 卡片、权限卡片、todo 卡片）。

问题：

- 小改动经常触发大范围 diff
- 编译增量与 SwiftUI preview 体验会变差

建议：

- 将子视图拆分到 `Views/Chat/` 目录（每个卡片一个文件）
- 将纯格式化/映射逻辑（比如状态 label、颜色等）移到专门的 formatter

### 2.4 Todo 渲染的“重复表达”可能让用户困惑

目前同时存在：

- Chat 顶部常驻 Task List 卡片（基于 `/session/:id/todo` + `todo.updated`）
- `todowrite` tool 卡片内也渲染 todo

问题：

- 同一信息在消息流与顶部卡片同时出现，用户可能不知道哪个是“权威状态”

建议：

- 明确一个为主：
  - 方案 A：顶部卡片作为“当前状态”，tool 卡片只显示“更新摘要/完成比”
  - 方案 B：只在 tool 卡片里展示，不做顶部常驻

### 2.5 Observability：大量 `print` 不利于线上定位

`print()` 虽然开发快，但难以分级/过滤，也无法跨模块串联。

建议：

- 引入 `Logger`（os.log）并按 subsystem/category 分类
- 日志里包含：sessionID/messageID/path/request url/statusCode/response length
