# Sync Streaming

> 目标：让 iOS 客户端在流式更新、工具调用展示上接近官方 Web 客户端的行为

## 1. 实现状态（2026-02 更新）

| 能力 | 状态 | 说明 |
|------|------|------|
| **Tool 完成后收起** | ✅ 已实现 | `ToolPartView`：running 时展开，completed 时 `onChange` 自动收起 |
| **Reasoning 展示** | ✅ 已实现 | 历史不显示；streaming 时 `StreamingReasoningView` 动态显示，think 完成后消失 |
| **Text/Reasoning delta 流式** | ❌ 未实现 | 仍全量 `loadMessages()`，无打字机效果 |
| **Tool output 实时流式** | ❌ API 不支持 | output 仅在 completed 时一次性发送（GH #5024） |
| **Tool input 流式** | ❌ API 未实现 | `tool-input-delta` 在 server 端被丢弃（GH #9737） |

## 2. 待实现：Delta 增量更新

当前 `handleSSEEvent` 对 `message.part.updated` 只做全量 reload：

```swift
case "message.updated", "message.part.updated":
    if currentSessionID != nil {
        await loadMessages()  // 全量 reload
    }
```

**实现要点**：
- 解析 `properties.delta` 与 `properties.part`（messageID、partID）
- 定位到 `messages` 中对应 Part，将 delta 追加到 text
- 若有 delta 则增量更新，否则 fallback 全量 reload

**API 参考**：GH #9480 确认 `{ kind: "delta", part: TextPart | ReasoningPart, delta?: string }` 结构。

## 3. 不纳入（受 API 限制）

- Tool output 实时流式（terminal 逐行）
- Tool input 流式（partial args）

## 4. 参考资料

- [GH #5024](https://github.com/anomalyco/opencode/issues/5024) - Bash tool call deltas
- [GH #9480](https://github.com/anomalyco/opencode/issues/9480) - Fix updatePart input narrowing for delta wrapper
- [GH #9737](https://github.com/anomalyco/opencode/issues/9737) - Expose partial tool arguments via state.raw
