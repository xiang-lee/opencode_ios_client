# Think Streaming

> 目标：Text/Reasoning 的 delta 流式，实现打字机效果

## 1. 范围

**仅实现**：Text/Reasoning delta 流式（打字机效果）

**不实现**（API 不支持，从文档中移除）：
- Tool output 实时流式
- Tool input 流式

## 2. 期望行为

- **Streaming 时**：不显示独立的 "sync" 栏或 "Thinking..." 标题，直接用**灰色字体**展示正在输入的内容，实现打字机效果（逐字/逐块浮现）
- **Streaming 结束后**：整个 think 内容**删除**，紧接着显示下一行（工具调用或实际 response）
- 与 production 行为一致，仅增加打字机效果

## 3. 实现状态

| 能力 | 状态 | 说明 |
|------|------|------|
| **Tool 完成后收起** | ✅ 已实现 | `ToolPartView`：running 展开，completed 收起 |
| **Reasoning 展示** | ✅ 已实现 | 历史不显示；streaming 时动态显示，结束后删除 |
| **Text/Reasoning delta 流式** | ✅ 已实现 | 解析 `delta` 增量追加，灰色字体、打字机效果 |

## 4. Delta 增量更新（已实现）

`handleSSEEvent` 对 `message.part.updated` 的处理：

- 若有 `properties.delta` 且 `properties.part` 含 messageID/id：将 delta 追加到 `streamingPartTexts[messageID:partID]`
- 否则：全量 reload 并清空 `streamingPartTexts`

## 5. UI

- `StreamingReasoningView`：无 sync 栏，灰色字体展示累积文本（`streamingPartTexts` 或 `part.text`）
