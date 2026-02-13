//
//  SettingsTabView.swift
//  OpenCodeClient
//

import SwiftUI

struct SettingsTabView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Connection") {
                    let info = AppState.serverURLInfo(state.serverURL)

                    TextField("Address", text: $state.serverURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)

                    TextField("Username", text: $state.username)
                        .textContentType(.username)
                        .autocapitalization(.none)

                    SecureField("Password", text: $state.password)
                        .textContentType(.password)

                    if let scheme = info.scheme {
                        HStack(spacing: 4) {
                            LabeledContent("Scheme", value: scheme.uppercased())
                                .foregroundStyle(scheme == "http" ? .red : .secondary)
                            if scheme == "http" {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.red)
                                    .help(schemeHelpText(info: info))
                            }
                        }
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        if state.isConnected {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Disconnected", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    if let error = state.connectionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Test Connection") {
                        Task { await state.refresh() }
                    }
                    .buttonStyle(.plain)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $state.themePreference) {
                        Text("Auto").tag("auto")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }

                Section("Speech Recognition") {
                    TextField("AI Builder Base URL", text: $state.aiBuilderBaseURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)

                    SecureField("AI Builder Token", text: $state.aiBuilderToken)
                        .textContentType(.password)

                    HStack {
                        Button {
                            Task { await state.testAIBuilderConnection() }
                        } label: {
                            if state.isTestingAIBuilderConnection {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.9)
                                    Text("Testing...")
                                }
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(
                            state.aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || state.isTestingAIBuilderConnection
                        )
                        Spacer()
                        if state.aiBuilderConnectionOK {
                            Label("OK", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if let err = state.aiBuilderConnectionError {
                            Text(err)
                                .foregroundStyle(.red)
                        }
                    }
                }
                Section("About") {
                    if let version = state.serverVersion {
                        LabeledContent("Server Version", value: version)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func schemeHelpText(info: AppState.ServerURLInfo) -> String {
        if info.isLocal {
            return "LAN: HTTP allowed. Recommended only on trusted networks. Warning: HTTP is insecure."
        } else {
            return "WAN: HTTPS required (HTTP will be blocked). Warning: HTTP is insecure."
        }
    }
}
