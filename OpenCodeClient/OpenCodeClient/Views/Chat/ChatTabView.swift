//
//  ChatTabView.swift
//  OpenCodeClient
//

import SwiftUI

struct ChatTabView: View {
    @Bindable var state: AppState
    var showSettingsInToolbar: Bool = false
    var onSettingsTap: (() -> Void)?
    @State private var inputText = ""
    @State private var isSending = false
    @State private var showSessionList = false
    @State private var showRenameAlert = false
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await state.createSession()
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.accentColor)
                        }
                        Button {
                            renameText = state.currentSession?.title ?? ""
                            showRenameAlert = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.accentColor)
                        }
                        Button {
                            showSessionList = true
                        } label: {
                            Image(systemName: "list.bullet.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.accentColor)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(Array(state.modelPresets.enumerated()), id: \.element.id) { index, preset in
                            Button {
                                state.selectedModelIndex = index
                            } label: {
                                Text(preset.displayName)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        state.selectedModelIndex == index
                                            ? AnyShapeStyle(Color.accentColor.gradient)
                                            : AnyShapeStyle(Color(.systemGray5))
                                    )
                                    .foregroundColor(state.selectedModelIndex == index ? .white : .secondary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        if showSettingsInToolbar, let onSettingsTap {
                            Button {
                                onSettingsTap()
                            } label: {
                                Image(systemName: "gear")
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(state.pendingPermissions.filter { $0.sessionID == state.currentSessionID }) { perm in
                                PermissionCardView(permission: perm) { approved in
                                    Task { await state.respondPermission(perm, approved: approved) }
                                }
                            }
                        ForEach(state.messages, id: \.info.id) { msg in
                            MessageRowView(message: msg, state: state)
                        }
                        if let streamingPart = streamingReasoningPart {
                            StreamingReasoningView(part: streamingPart, state: state)
                        }
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .textSelection(.enabled)
                    .onChange(of: scrollAnchor) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                Divider()
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Ask anything...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...8)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(.systemGray4), lineWidth: 0.5)
                        )

                    Button {
                        Task {
                            let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            inputText = ""
                            isSending = true
                            let success = await state.sendMessage(text)
                            isSending = false
                            if !success {
                                inputText = text
                            }
                        }
                    } label: {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)

                    if state.isBusy {
                        Button {
                            Task { await state.abortSession() }
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle(state.currentSession?.title ?? "Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let status = state.currentSessionStatus {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor(status))
                                .frame(width: 6, height: 6)
                            Text(statusLabel(status))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSessionList) {
                SessionListView(state: state)
            }
            .alert("发送失败", isPresented: Binding(
                get: { state.sendError != nil },
                set: { if !$0 { state.sendError = nil } }
            )) {
                Button("确定") { state.sendError = nil }
            }             message: {
                if let error = state.sendError {
                    Text(error)
                }
            }
            .alert("重命名 Session", isPresented: $showRenameAlert) {
                TextField("标题", text: $renameText)
                Button("取消", role: .cancel) { showRenameAlert = false }
                Button("确定") {
                    guard let id = state.currentSessionID else { return }
                    Task { await state.updateSessionTitle(sessionID: id, title: renameText) }
                    showRenameAlert = false
                }
            } message: {
                Text("输入新标题")
            }
        }
    }

    /// 仅在 streaming 时显示：当 session busy 且最后一条 assistant 消息的最后一个 part 是 reasoning
    private var streamingReasoningPart: Part? {
        guard state.isBusy else { return nil }
        guard let lastMsg = state.messages.last, lastMsg.info.isAssistant else { return nil }
        guard let lastPart = lastMsg.parts.last, lastPart.isReasoning else { return nil }
        return lastPart
    }

    /// 内容变化时用于触发自动滚动
    private var scrollAnchor: String {
        let perm = state.pendingPermissions.filter { $0.sessionID == state.currentSessionID }.count
        let msg = state.messages.map { "\($0.info.id)-\($0.parts.count)" }.joined(separator: "|")
        return "\(perm)-\(msg)"
    }

    private func statusColor(_ status: SessionStatus) -> Color {
        switch status.type {
        case "busy": return .blue
        case "error": return .red
        default: return .green
        }
    }

    private func statusLabel(_ status: SessionStatus) -> String {
        switch status.type {
        case "busy": return "Busy"
        case "retry": return "Retrying..."
        default: return "Idle"
        }
    }
}
