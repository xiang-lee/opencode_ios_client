//
//  SplitSidebarView.swift
//  OpenCodeClient
//

import SwiftUI

/// iPad / Vision Pro split layout sidebar:
/// - Top: File tree
/// - Bottom: Sessions list (selecting switches the chat on the right)
struct SplitSidebarView: View {
    @Bindable var state: AppState

    private let filesRatio: CGFloat = 0.62
    private let minFilesHeight: CGFloat = 260
    private let minSessionsHeight: CGFloat = 220

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let filesHeight = max(minFilesHeight, geo.size.height * filesRatio)
                let sessionsHeight = max(minSessionsHeight, geo.size.height - filesHeight)

                VStack(spacing: 0) {
                    FileTreeView(state: state)
                        .searchable(text: $state.fileSearchQuery, prompt: "Search files")
                        .onSubmit(of: .search) {
                            Task { await state.searchFiles(query: state.fileSearchQuery) }
                        }
                        .onChange(of: state.fileSearchQuery) { _, newValue in
                            if newValue.isEmpty {
                                state.fileSearchResults = []
                            } else {
                                Task {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    guard !Task.isCancelled else { return }
                                    await state.searchFiles(query: newValue)
                                }
                            }
                        }
                        .frame(height: filesHeight)

                    Divider()

                    SessionsSidebarList(state: state)
                        .frame(height: sessionsHeight)
                }
            }
            .navigationTitle("Workspace")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct SessionsSidebarList: View {
    @Bindable var state: AppState

    var body: some View {
        List {
            Section("Sessions") {
                ForEach(state.sortedSessions) { session in
                    SessionRowView(
                        session: session,
                        status: state.sessionStatuses[session.id],
                        isSelected: state.currentSessionID == session.id
                    ) {
                        state.selectSession(session)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await state.refreshSessions()
        }
    }
}
