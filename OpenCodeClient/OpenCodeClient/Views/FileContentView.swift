//
//  FileContentView.swift
//  OpenCodeClient
//

import SwiftUI
import MarkdownUI

struct FileContentView: View {
    @Bindable var state: AppState
    let filePath: String
    @State private var content: String?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showPreview = true

    private var isMarkdown: Bool {
        filePath.lowercased().hasSuffix(".md") || filePath.lowercased().hasSuffix(".markdown")
    }

    private var fileName: String {
        filePath.split(separator: "/").last.map(String.init) ?? filePath
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let content {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: content, subject: Text(fileName)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        if isMarkdown {
            ToolbarItem(placement: .primaryAction) {
                Button(showPreview ? "Markdown" : "Preview") {
                    showPreview.toggle()
                }
            }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if let text = content {
                contentView(text: text)
            } else {
                ContentUnavailableView("No content", systemImage: "doc.text")
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear {
            loadContent()
        }
        .refreshable {
            loadContent()
        }
    }

    @ViewBuilder
    private func contentView(text: String) -> some View {
        if isMarkdown {
            if showPreview {
                MarkdownPreviewView(text: text)
            } else {
                RawTextView(text: text, monospaced: true)
            }
        } else {
            CodeView(text: text, path: filePath)
        }
    }

    private func loadContent() {
        isLoading = true
        loadError = nil
        Task {
            do {
                let fc = try await state.loadFileContent(path: filePath)
                await MainActor.run {
                    content = fc.text ?? fc.content
                    isLoading = false
                    if content == nil && fc.type == "binary" {
                        loadError = "Binary file"
                    }
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

/// Simple code view with line numbers
struct CodeView: View {
    let text: String
    let path: String

    private var lines: [String] {
        text.components(separatedBy: .newlines)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 8)
                .frame(minWidth: 400, alignment: .leading)
            }
        }
    }
}

/// Markdown preview using MarkdownUI library for full GFM rendering.
struct MarkdownPreviewView: View {
    let text: String

    var body: some View {
        ScrollView {
            Markdown(text)
                .textSelection(.enabled)
                .padding()
        }
    }
}

/// Raw text view for Markdown source (wraps to fill available width).
struct RawTextView: View {
    let text: String
    var monospaced: Bool = false

    var body: some View {
        ScrollView {
            Text(text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}
