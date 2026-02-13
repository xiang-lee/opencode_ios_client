//
//  AppState.swift
//  OpenCodeClient
//

import Foundation
import CryptoKit
import Observation
import os

@Observable
@MainActor
final class AppState {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OpenCodeClient",
        category: "AppState"
    )

    struct ServerURLInfo {
        let raw: String
        let normalized: String?
        let scheme: String?
        let host: String?
        let isLocal: Bool
        let isAllowed: Bool
        let warning: String?
    }

    /// LAN allows HTTP; WAN requires HTTPS.
    nonisolated static func serverURLInfo(_ raw: String) -> ServerURLInfo {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .init(raw: raw, normalized: nil, scheme: nil, host: nil, isLocal: true, isAllowed: false, warning: "Server address is empty")
        }

        func parseHost(_ s: String) -> String? {
            if let u = URL(string: s), let h = u.host { return h }
            if let u = URL(string: "http://\(s)"), let h = u.host { return h }
            return nil
        }

        func isPrivateIPv4(_ host: String) -> Bool {
            let parts = host.split(separator: ".")
            guard parts.count == 4,
                  let a = Int(parts[0]), let b = Int(parts[1]) else { return false }
            if a == 10 || a == 127 { return true }
            if a == 192 && b == 168 { return true }
            if a == 172 && (16...31).contains(b) { return true }
            if a == 169 && b == 254 { return true }
            if host == "0.0.0.0" { return true }
            return false
        }

        let hasScheme = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
        let host = parseHost(trimmed)
        let isLocal: Bool = {
            guard let host else { return true }
            if host == "localhost" { return true }
            if host.hasSuffix(".local") { return true }
            if isPrivateIPv4(host) { return true }
            return false
        }()

        let scheme: String = {
            if let u = URL(string: trimmed), let s = u.scheme { return s }
            return isLocal ? "http" : "https"
        }()

        if scheme == "http", !isLocal {
            return .init(
                raw: raw,
                normalized: hasScheme ? trimmed : nil,
                scheme: "http",
                host: host,
                isLocal: false,
                isAllowed: false,
                warning: "WAN address must use HTTPS (http:// is only allowed on LAN)"
            )
        }

        let normalized = hasScheme ? trimmed : "\(scheme)://\(trimmed)"
        let parsed = URL(string: normalized)
        return .init(
            raw: raw,
            normalized: normalized,
            scheme: parsed?.scheme,
            host: parsed?.host,
            isLocal: isLocal,
            isAllowed: parsed != nil,
            warning: parsed == nil ? "Invalid server URL" : (scheme == "http" ? "Using HTTP on LAN" : nil)
        )
    }
    private var _serverURL: String = APIClient.defaultServer
    var serverURL: String {
        get { _serverURL }
        set {
            _serverURL = newValue
            UserDefaults.standard.set(newValue, forKey: Self.serverURLKey)
        }
    }

    private var _username: String = ""
    var username: String {
        get { _username }
        set {
            _username = newValue
            UserDefaults.standard.set(newValue, forKey: Self.usernameKey)
        }
    }

    private var _password: String = ""
    var password: String {
        get { _password }
        set {
            _password = newValue
            if newValue.isEmpty {
                KeychainHelper.delete(Self.passwordKeychainKey)
            } else {
                KeychainHelper.save(newValue, forKey: Self.passwordKeychainKey)
            }
        }
    }

    private static let serverURLKey = "serverURL"
    private static let usernameKey = "username"
    private static let passwordKeychainKey = "password"
    private static let aiBuilderBaseURLKey = "aiBuilderBaseURL"
    private static let aiBuilderTokenKeychainKey = "aiBuilderToken"
    private static let aiBuilderLastOKSignatureKey = "aiBuilderLastOKSignature"
    private static let aiBuilderLastOKTestedAtKey = "aiBuilderLastOKTestedAt"

    init() {
        _serverURL = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? APIClient.defaultServer
        _username = UserDefaults.standard.string(forKey: Self.usernameKey) ?? ""
        _password = KeychainHelper.load(forKey: Self.passwordKeychainKey) ?? ""

        _aiBuilderBaseURL = UserDefaults.standard.string(forKey: Self.aiBuilderBaseURLKey) ?? "https://space.ai-builders.com/backend"
        _aiBuilderToken = KeychainHelper.load(forKey: Self.aiBuilderTokenKeychainKey) ?? ""

        // Restore last known-good AI Builder connection state if token/baseURL unchanged.
        let storedSig = UserDefaults.standard.string(forKey: Self.aiBuilderLastOKSignatureKey)
        let currentSig = Self.aiBuilderSignature(baseURL: _aiBuilderBaseURL, token: _aiBuilderToken)
        if let storedSig, storedSig == currentSig, !currentSig.isEmpty {
            aiBuilderConnectionOK = true
            if let ts = UserDefaults.standard.object(forKey: Self.aiBuilderLastOKTestedAtKey) as? Double {
                aiBuilderLastTestedAt = Date(timeIntervalSince1970: ts)
            }
        }
    }

    private static func aiBuilderSignature(baseURL: String, token: String) -> String {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let tok = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !tok.isEmpty else { return "" }
        let input = "\(base)|\(tok)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var _aiBuilderBaseURL: String = "https://space.ai-builders.com/backend"
    var aiBuilderBaseURL: String {
        get { _aiBuilderBaseURL }
        set {
            _aiBuilderBaseURL = newValue
            UserDefaults.standard.set(newValue, forKey: Self.aiBuilderBaseURLKey)
            aiBuilderConnectionOK = false
            aiBuilderConnectionError = nil
            aiBuilderLastTestedAt = nil
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKSignatureKey)
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKTestedAtKey)
        }
    }

    private var _aiBuilderToken: String = ""
    var aiBuilderToken: String {
        get { _aiBuilderToken }
        set {
            _aiBuilderToken = newValue
            if newValue.isEmpty {
                KeychainHelper.delete(Self.aiBuilderTokenKeychainKey)
            } else {
                KeychainHelper.save(newValue, forKey: Self.aiBuilderTokenKeychainKey)
            }
            aiBuilderConnectionOK = false
            aiBuilderConnectionError = nil
            aiBuilderLastTestedAt = nil
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKSignatureKey)
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKTestedAtKey)
        }
    }
    var aiBuilderConnectionError: String? = nil
    var aiBuilderConnectionOK: Bool = false
    var aiBuilderLastTestedAt: Date? = nil
    var isTestingAIBuilderConnection: Bool = false
    var isConnected: Bool = false
    var serverVersion: String?
    var connectionError: String?
    var sendError: String?

    private let sessionStore = SessionStore()
    private let messageStore = MessageStore()
    private let fileStore = FileStore()
    private let todoStore = TodoStore()

    var sessions: [Session] { get { sessionStore.sessions } set { sessionStore.sessions = newValue } }
    var sortedSessions: [Session] { sessions.sorted { $0.time.updated > $1.time.updated } }
    var currentSessionID: String? { get { sessionStore.currentSessionID } set { sessionStore.currentSessionID = newValue } }
    var sessionStatuses: [String: SessionStatus] { get { sessionStore.sessionStatuses } set { sessionStore.sessionStatuses = newValue } }

    var messages: [MessageWithParts] { get { messageStore.messages } set { messageStore.messages = newValue } }
    var partsByMessage: [String: [Part]] { get { messageStore.partsByMessage } set { messageStore.partsByMessage = newValue } }
    var streamingPartTexts: [String: String] { get { messageStore.streamingPartTexts } set { messageStore.streamingPartTexts = newValue } }

    /// 固定三个模型，不再从 server 导入
    var modelPresets: [ModelPreset] = [
        ModelPreset(displayName: "GPT-5.2", providerID: "openai", modelID: "gpt-5.2"),
        ModelPreset(displayName: "GPT-5.3 Codex Spark", providerID: "openai", modelID: "gpt-5.3-codex-spark"),
        ModelPreset(displayName: "Opus 4.6", providerID: "poe", modelID: "anthropic/claude-opus-4-6"),
        ModelPreset(displayName: "GLM5", providerID: "zai-coding-plan", modelID: "glm-5"),
    ]
    var selectedModelIndex: Int = 0

    var pendingPermissions: [PendingPermission] = []

    var themePreference: String = "auto"  // "auto" | "light" | "dark"

    var sessionDiffs: [FileDiff] { get { fileStore.sessionDiffs } set { fileStore.sessionDiffs = newValue } }
    var selectedDiffFile: String? { get { fileStore.selectedDiffFile } set { fileStore.selectedDiffFile = newValue } }
    var selectedTab: Int = 0  // 0=Chat, 1=Files, 2=Settings
    var fileToOpenInFilesTab: String?  // 从 Chat 中 tool 点击跳转时设置，Files tab 或 sheet 展示

    var sessionTodos: [String: [TodoItem]] { get { todoStore.sessionTodos } set { todoStore.sessionTodos = newValue } }

    var fileTreeRoot: [FileNode] { get { fileStore.fileTreeRoot } set { fileStore.fileTreeRoot = newValue } }
    var fileStatusMap: [String: String] { get { fileStore.fileStatusMap } set { fileStore.fileStatusMap = newValue } }
    var expandedPaths: Set<String> { get { fileStore.expandedPaths } set { fileStore.expandedPaths = newValue } }
    var fileChildrenCache: [String: [FileNode]] { get { fileStore.fileChildrenCache } set { fileStore.fileChildrenCache = newValue } }
    var fileSearchQuery: String { get { fileStore.fileSearchQuery } set { fileStore.fileSearchQuery = newValue } }
    var fileSearchResults: [String] { get { fileStore.fileSearchResults } set { fileStore.fileSearchResults = newValue } }

    // Provider config cache (for context usage ring)
    var providersResponse: ProvidersResponse? = nil
    var providerModelsIndex: [String: ProviderModel] = [:]

    private let apiClient = APIClient()
    private let sseClient = SSEClient()
    private var sseTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    /// Latest streaming reasoning part (for typewriter thinking display)
    var streamingReasoningPart: Part? = nil

    var selectedModel: ModelPreset? {
        guard modelPresets.indices.contains(selectedModelIndex) else { return nil }
        return modelPresets[selectedModelIndex]
    }

    var currentSession: Session? {
        guard let id = currentSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    var currentSessionStatus: SessionStatus? {
        guard let id = currentSessionID else { return nil }
        return sessionStatuses[id]
    }

    var isBusy: Bool {
        currentSessionStatus?.type == "busy"
    }

    var currentTodos: [TodoItem] {
        guard let id = currentSessionID else { return [] }
        return sessionTodos[id] ?? []
    }

    func configure(serverURL: String, username: String? = nil, password: String? = nil) {
        // Keep raw user input; security normalization happens at request time.
        self.serverURL = serverURL
        self.username = username ?? ""
        self.password = password ?? ""
    }

    func testConnection() async {
        connectionError = nil

        let info = Self.serverURLInfo(serverURL)
        guard info.isAllowed, let baseURL = info.normalized else {
            isConnected = false
            connectionError = info.warning ?? "Invalid server URL"
            return
        }

        await apiClient.configure(baseURL: baseURL, username: username.isEmpty ? nil : username, password: password.isEmpty ? nil : password)
        do {
            let health = try await apiClient.health()
            isConnected = health.healthy
            serverVersion = health.version
        } catch {
            isConnected = false
            connectionError = error.localizedDescription
        }
    }

    func loadSessions() async {
        guard isConnected else { return }
        do {
            sessions = try await apiClient.sessions()
            if currentSessionID == nil, let first = sessions.first {
                currentSessionID = first.id
            }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func refreshSessions() async {
        guard isConnected else { return }
        await loadSessions()
        if let statuses = try? await apiClient.sessionStatus() {
            sessionStatuses = statuses
        }
    }

    func selectSession(_ session: Session) {
        guard currentSessionID != session.id else { return }
        streamingReasoningPart = nil
        streamingPartTexts = [:]
        messages = []
        partsByMessage = [:]
        currentSessionID = session.id
        Task {
            await loadMessages()
            await loadSessionDiff()
            await loadSessionTodos()
        }
    }

    func loadSessionTodos() async {
        guard let sessionID = currentSessionID else { return }
        do {
            let todos = try await apiClient.sessionTodos(sessionID: sessionID)
            sessionTodos[sessionID] = todos
        } catch {
            // keep previous value if any
        }
    }

    func createSession() async {
        guard isConnected else { return }
        do {
            let session = try await apiClient.createSession()
            sessions.insert(session, at: 0)
            currentSessionID = session.id
            messages = []
            partsByMessage = [:]
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func loadMessages() async {
        guard let sessionID = currentSessionID else { return }
        do {
            let loaded = try await apiClient.messages(sessionID: sessionID)
            messages = loaded
            partsByMessage = Dictionary(uniqueKeysWithValues: loaded.map { ($0.info.id, $0.parts) })
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func loadSessionDiff() async {
        guard let sessionID = currentSessionID else { sessionDiffs = []; return }
        do {
            sessionDiffs = try await apiClient.sessionDiff(sessionID: sessionID)
        } catch {
            sessionDiffs = []
        }
    }

    func loadFileTree() async {
        do {
            fileTreeRoot = try await apiClient.fileList(path: "")
        } catch {
            fileTreeRoot = []
        }
    }

    func loadFileStatus() async {
        do {
            let entries = try await apiClient.fileStatus()
            fileStatusMap = Dictionary(uniqueKeysWithValues: entries.compactMap { e in
                guard let p = e.path else { return nil }
                return (p, e.status ?? "")
            })
        } catch {
            fileStatusMap = [:]
        }
    }

    func loadFileChildren(path: String) async -> [FileNode] {
        do {
            let children = try await apiClient.fileList(path: path)
            fileChildrenCache[path] = children
            return children
        } catch {
            fileChildrenCache[path] = []
            return []
        }
    }

    func cachedChildren(for path: String) -> [FileNode]? {
        fileChildrenCache[path]
    }

    func searchFiles(query: String) async {
        guard !query.isEmpty else { fileSearchResults = []; return }
        do {
            fileSearchResults = try await apiClient.findFile(query: query)
        } catch {
            fileSearchResults = []
        }
    }

    func loadFileContent(path: String) async throws -> FileContent {
        let resolved = PathNormalizer.resolveWorkspaceRelativePath(path, workspaceDirectory: currentSession?.directory)
        let fc = try await apiClient.fileContent(path: resolved)
        if fc.type == "text" {
            let text = fc.content ?? ""
            if text.isEmpty {
                let base = Self.serverURLInfo(serverURL).normalized ?? "nil"
                Self.logger.warning(
                    "Empty file content. base=\(base, privacy: .public) raw=\(path, privacy: .public) resolved=\(resolved, privacy: .public) session=\(self.currentSessionID ?? "nil", privacy: .public)"
                )
            }
        }
        return fc
    }

    func transcribeAudio(audioFileURL: URL, language: String? = nil) async throws -> String {
        let token = aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw AIBuildersAudioError.missingToken }

        let base = aiBuilderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resp = try await AIBuildersAudioClient.transcribe(
            baseURL: base,
            token: token,
            audioFileURL: audioFileURL,
            language: language
        )
        return resp.text
    }

    func testAIBuilderConnection() async {
        guard !isTestingAIBuilderConnection else { return }
        isTestingAIBuilderConnection = true
        defer { isTestingAIBuilderConnection = false }

        aiBuilderConnectionError = nil
        aiBuilderConnectionOK = false
        let token = aiBuilderToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            aiBuilderConnectionError = "Token is empty"
            aiBuilderLastTestedAt = Date()
            return
        }
        let base = aiBuilderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await AIBuildersAudioClient.testConnection(baseURL: base, token: token)
            aiBuilderConnectionOK = true
            aiBuilderLastTestedAt = Date()

            let sig = Self.aiBuilderSignature(baseURL: base, token: token)
            UserDefaults.standard.set(sig, forKey: Self.aiBuilderLastOKSignatureKey)
            UserDefaults.standard.set(aiBuilderLastTestedAt?.timeIntervalSince1970, forKey: Self.aiBuilderLastOKTestedAtKey)
        } catch {
            aiBuilderLastTestedAt = Date()
            aiBuilderConnectionOK = false
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKSignatureKey)
            UserDefaults.standard.removeObject(forKey: Self.aiBuilderLastOKTestedAtKey)
            switch error {
            case AIBuildersAudioError.missingToken:
                aiBuilderConnectionError = "Token is empty"
            case AIBuildersAudioError.invalidBaseURL:
                aiBuilderConnectionError = "Invalid base URL"
            case AIBuildersAudioError.httpError(let statusCode, _):
                aiBuilderConnectionError = "HTTP \(statusCode)"
            default:
                aiBuilderConnectionError = error.localizedDescription
            }
        }
    }

    func toggleFileExpanded(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
    }

    func isFileExpanded(_ path: String) -> Bool {
        expandedPaths.contains(path)
    }

    func sendMessage(_ text: String) async -> Bool {
        sendError = nil
        guard let sessionID = currentSessionID else {
            sendError = "请先选择或创建 Session"
            return false
        }
        let model = selectedModel.map { Message.ModelInfo(providerID: $0.providerID, modelID: $0.modelID) }
        do {
            try await apiClient.promptAsync(sessionID: sessionID, text: text, model: model)
            startPollingAfterSend()
            return true
        } catch {
            sendError = error.localizedDescription
            return false
        }
    }

    private func startPollingAfterSend() {
        pollingTask?.cancel()
        pollingTask = Task {
            for i in 0..<30 {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await loadMessages()

                // Refresh sessions a few times after send to pick up server-generated titles.
                if i == 2 || i == 6 || i == 12 {
                    await loadSessions()
                }
            }
        }
    }

    func abortSession() async {
        guard let sessionID = currentSessionID else { return }
        do {
            try await apiClient.abort(sessionID: sessionID)
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func summarizeSession() async {
        guard let sessionID = currentSessionID else { return }
        do {
            try await apiClient.summarize(sessionID: sessionID)
            await loadMessages()
            await refreshSessions()
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func updateSessionTitle(sessionID: String, title: String) async {
        do {
            _ = try await apiClient.updateSession(sessionID: sessionID, title: title)
            await refreshSessions()
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func respondPermission(_ perm: PendingPermission, approved: Bool) async {
        guard approved else {
            pendingPermissions.removeAll { $0.id == perm.id }
            return
        }
        do {
            try await apiClient.respondPermission(sessionID: perm.sessionID, permissionID: perm.permissionID)
            pendingPermissions.removeAll { $0.id == perm.id }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func connectSSE() {
        sseTask?.cancel()
        sseTask = Task {
            var attempt = 0
            while !Task.isCancelled {
                let info = Self.serverURLInfo(serverURL)
                guard info.isAllowed, let baseURL = info.normalized else {
                    return
                }

                let stream = await sseClient.connect(
                    baseURL: baseURL,
                    username: username.isEmpty ? nil : username,
                    password: password.isEmpty ? nil : password
                )

                do {
                    for try await event in stream {
                        attempt = 0
                        await handleSSEEvent(event)
                    }
                } catch {
                    // Reconnect with exponential backoff
                    attempt += 1
                    let base = min(30.0, pow(2.0, Double(attempt)))
                    try? await Task.sleep(for: .seconds(base))
                }
            }
        }
    }

    func disconnectSSE() {
        sseTask?.cancel()
        sseTask = nil
    }

    /// 是否应处理 message.updated：有 sessionID 时需匹配当前 session，否则保持原行为
    nonisolated static func shouldProcessMessageEvent(eventSessionID: String?, currentSessionID: String?) -> Bool {
        guard currentSessionID != nil else { return false }
        if let sid = eventSessionID { return sid == currentSessionID }
        return true  // 无 sessionID 时保持原行为（向后兼容）
    }

    private func handleSSEEvent(_ event: SSEEvent) async {
        let type = event.payload.type
        let props = event.payload.properties ?? [:]

        switch type {
        case "session.status":
            if let sessionID = props["sessionID"]?.value as? String,
               let statusObj = props["status"]?.value as? [String: Any] {
                if let status = try? JSONSerialization.data(withJSONObject: statusObj),
                   let decoded = try? JSONDecoder().decode(SessionStatus.self, from: status) {
                    sessionStatuses[sessionID] = decoded
                    if sessionID == currentSessionID, decoded.type != "busy" {
                        streamingReasoningPart = nil
                        streamingPartTexts = [:]
                    }
                }
            }
        case "session.updated":
            let infoVal = props["info"]?.value ?? props["session"]?.value
            if let infoObj = infoVal,
               JSONSerialization.isValidJSONObject(infoObj),
               let data = try? JSONSerialization.data(withJSONObject: infoObj),
               let session = try? JSONDecoder().decode(Session.self, from: data) {
                if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[idx] = session
                } else {
                    sessions.insert(session, at: 0)
                }
            }
        case "message.updated":
            let eventSessionID = props["sessionID"]?.value as? String
            if Self.shouldProcessMessageEvent(eventSessionID: eventSessionID, currentSessionID: currentSessionID) {
                streamingReasoningPart = nil
                streamingPartTexts = [:]
                await loadMessages()
                await loadSessionDiff()
            }
        case "message.part.updated":
            if let sessionID = props["sessionID"]?.value as? String,
               sessionID == currentSessionID {
                let partObj = props["part"]?.value as? [String: Any]
                let msgID = partObj?["messageID"] as? String
                let partID = partObj?["id"] as? String
                let partType = partObj?["type"] as? String

                if let msgID, let partID, partType == "reasoning" {
                    streamingReasoningPart = Part(
                        id: partID,
                        messageID: msgID,
                        sessionID: sessionID,
                        type: "reasoning",
                        text: nil,
                        tool: nil,
                        callID: nil,
                        state: nil,
                        metadata: nil,
                        files: nil
                    )
                }

                if let delta = props["delta"]?.value as? String,
                   let msgID,
                   let partID,
                   !delta.isEmpty {
                    let key = "\(msgID):\(partID)"
                    streamingPartTexts[key] = (streamingPartTexts[key] ?? "") + delta
                } else {
                    streamingReasoningPart = nil
                    streamingPartTexts = [:]
                    await loadMessages()
                    await loadSessionDiff()
                }
            }
        case "permission.asked":
            if let sessionID = props["sessionID"]?.value as? String,
               let permissionID = props["permissionID"]?.value as? String {
                let desc = (props["description"]?.value as? String) ?? (props["tool"]?.value as? String) ?? "Permission required"
                let perm = PendingPermission(sessionID: sessionID, permissionID: permissionID, description: desc)
                if !pendingPermissions.contains(where: { $0.permissionID == permissionID }) {
                    pendingPermissions.append(perm)
                }
            }
        case "todo.updated":
            if let sessionID = props["sessionID"]?.value as? String,
               let todosObj = props["todos"]?.value,
               JSONSerialization.isValidJSONObject(todosObj),
               let todosData = try? JSONSerialization.data(withJSONObject: todosObj),
               let decoded = try? JSONDecoder().decode([TodoItem].self, from: todosData) {
                sessionTodos[sessionID] = decoded
            }
        default:
            break
        }
    }

    func refresh() async {
        await testConnection()
        if isConnected {
            await loadProvidersConfig()
            await loadSessions()
            await loadMessages()
            await loadSessionDiff()
            await loadSessionTodos()
            await loadFileTree()
            await loadFileStatus()
            let statuses = try? await apiClient.sessionStatus()
            if let statuses { sessionStatuses = statuses }
        }
    }

    func loadProvidersConfig() async {
        do {
            let resp = try await apiClient.providers()
            providersResponse = resp
            var idx: [String: ProviderModel] = [:]
            for p in resp.providers ?? [] {
                for (modelID, m) in p.models ?? [:] {
                    let key = "\(p.id)/\(modelID)"
                    idx[key] = m
                }
            }
            providerModelsIndex = idx
        } catch {
            // Optional feature; ignore provider config errors.
        }
    }
}

struct PendingPermission: Identifiable {
    var id: String { "\(sessionID)/\(permissionID)" }
    let sessionID: String
    let permissionID: String
    let description: String
}
