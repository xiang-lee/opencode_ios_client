# TODO

## 已完成

1. ~~Chat tab 里的 AI response 支持文字选择/复制（包括 Markdown 渲染内容）。~~
2. ~~从 Chat 里点“跳转到文件”的图标后，打开的 Markdown 预览有时显示不对（空白/只显示第一行）。~~
3. ~~Tool call 卡片的“理由/标题”在收起态只显示一到两行，超出用省略号；展开后显示完整内容。~~
4. ~~支持 OpenCode 的 session task list（todo）：拉取、SSE 更新、todowrite 渲染为 Task List 卡片。~~

## 待办（Phase 3）

- **Sync Streaming delta**：解析 `message.part.updated` 的 `delta`，增量追加实现打字机效果（见 [SYNC_STREAMING.md](SYNC_STREAMING.md)）
