//
//  APIClient.swift
//  OpenCodeClient
//

import Foundation

actor APIClient {
    private var baseURL: String
    private var username: String?
    private var password: String?

    static let defaultServer = "192.168.180.128:4096"

    init(baseURL: String = defaultServer, username: String? = nil, password: String? = nil) {
        self.baseURL = baseURL.hasPrefix("http") ? baseURL : "http://\(baseURL)"
        self.username = username
        self.password = password
    }

    func configure(baseURL: String, username: String? = nil, password: String? = nil) {
        self.baseURL = baseURL.hasPrefix("http") ? baseURL : "http://\(baseURL)"
        self.username = username
        self.password = password
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> (Data, URLResponse) {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let username, let password {
            let credential = "\(username):\(password)"
            if let data = credential.data(using: .utf8) {
                let encoded = data.base64EncodedString()
                request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
            }
        }

        if let body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw APIError.httpError(statusCode: http.statusCode, data: data)
        }
        return (data, response)
    }

    func health() async throws -> HealthResponse {
        let (data, _) = try await makeRequest(path: "/global/health")
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func sessions() async throws -> [Session] {
        let (data, _) = try await makeRequest(path: "/session")
        return try JSONDecoder().decode([Session].self, from: data)
    }

    func createSession(title: String? = nil) async throws -> Session {
        let body = title.map { ["title": $0] } ?? [:]
        let data = try JSONEncoder().encode(body)
        let (responseData, _) = try await makeRequest(path: "/session", method: "POST", body: data)
        return try JSONDecoder().decode(Session.self, from: responseData)
    }

    func messages(sessionID: String) async throws -> [MessageWithParts] {
        let (data, _) = try await makeRequest(path: "/session/\(sessionID)/message")
        return try JSONDecoder().decode([MessageWithParts].self, from: data)
    }

    func promptAsync(sessionID: String, text: String, agent: String = "build", model: Message.ModelInfo?) async throws {
        struct PromptBody: Encodable {
            let parts: [PartInput]
            let agent: String
            let model: ModelInput?
            struct PartInput: Encodable {
                let type = "text"
                let text: String
            }
            struct ModelInput: Encodable {
                let providerID: String
                let modelID: String
            }
        }
        let body = PromptBody(
            parts: [.init(text: text)],
            agent: agent,
            model: model.map { .init(providerID: $0.providerID, modelID: $0.modelID) }
        )
        let bodyData = try JSONEncoder().encode(body)
        let (_, response) = try await makeRequest(path: "/session/\(sessionID)/prompt_async", method: "POST", body: bodyData)
        if let http = response as? HTTPURLResponse, http.statusCode != 204 {
            throw APIError.httpError(statusCode: http.statusCode, data: Data())
        }
    }

    func abort(sessionID: String) async throws {
        let (_, response) = try await makeRequest(path: "/session/\(sessionID)/abort", method: "POST")
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.httpError(statusCode: http.statusCode, data: Data())
        }
    }

    func sessionStatus() async throws -> [String: SessionStatus] {
        let (data, _) = try await makeRequest(path: "/session/status")
        return try JSONDecoder().decode([String: SessionStatus].self, from: data)
    }

    func respondPermission(sessionID: String, permissionID: String) async throws {
        let (_, response) = try await makeRequest(path: "/session/\(sessionID)/permissions/\(permissionID)", method: "POST")
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.httpError(statusCode: http.statusCode, data: Data())
        }
    }
}

struct HealthResponse: Codable {
    let healthy: Bool
    let version: String?
}

enum APIError: Error {
    case invalidURL
    case httpError(statusCode: Int, data: Data)
}
