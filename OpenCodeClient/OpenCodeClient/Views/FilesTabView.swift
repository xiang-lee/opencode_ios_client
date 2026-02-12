//
//  FilesTabView.swift
//  OpenCodeClient
//

import SwiftUI

struct FilesTabView: View {
    @Bindable var state: AppState
    @State private var selectedSegment = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedSegment) {
                    Text("File Tree").tag(0)
                    Text("Session Changes").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Group {
                    if selectedSegment == 0 {
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
                    } else {
                        sessionChangesView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Files")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var sessionChangesView: some View {
        if state.sessionDiffs.isEmpty {
            ContentUnavailableView(
                "Session Changes",
                systemImage: "doc.text.magnifyingglass",
                description: Text("No file changes in this session. The diff API may return empty; see WORKING.md.")
            )
            .refreshable { await state.loadSessionDiff() }
        } else {
            List {
                ForEach(state.sessionDiffs) { diff in
                    NavigationLink(value: diff) {
                        HStack {
                            Image(systemName: statusIcon(diff.status))
                                .foregroundStyle(statusColor(diff.status))
                            Text(diff.file)
                            Spacer()
                            Text("+\(diff.additions) -\(diff.deletions)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationDestination(for: FileDiff.self) { diff in
                DiffDetailView(diff: diff)
            }
            .refreshable { await state.loadSessionDiff() }
        }
    }

    private func statusIcon(_ status: String?) -> String {
        switch status {
        case "added": return "plus.circle.fill"
        case "deleted": return "minus.circle.fill"
        default: return "pencil.circle.fill"
        }
    }

    private func statusColor(_ status: String?) -> Color {
        switch status {
        case "added": return .green
        case "deleted": return .red
        default: return .orange
        }
    }
}

struct DiffDetailView: View {
    let diff: FileDiff

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("File: \(diff.file)")
                    .font(.headline)
                Text("+\(diff.additions) -\(diff.deletions)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !diff.before.isEmpty || !diff.after.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Before:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(diff.before)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(4)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("After:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(diff.after)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(diff.file)
        .navigationBarTitleDisplayMode(.inline)
    }
}
