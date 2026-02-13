//
//  AIBuildersAudioClient.swift
//  OpenCodeClient
//

import Foundation

struct TranscriptionResponse: Codable {
    let requestID: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case text
    }
}

enum AIBuildersAudioError: Error {
    case invalidBaseURL
    case missingToken
    case invalidResponse
    case httpError(statusCode: Int, body: Data)
}

enum AIBuildersAudioClient {
    static func transcribe(
        baseURL: String,
        token: String,
        audioFileURL: URL,
        language: String? = nil,
        prompt: String? = nil,
        terms: String? = nil
    ) async throws -> TranscriptionResponse {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { throw AIBuildersAudioError.invalidBaseURL }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIBuildersAudioError.missingToken }

        let normalizedBase: String = {
            if trimmedBase.hasPrefix("http://") || trimmedBase.hasPrefix("https://") { return trimmedBase }
            return "https://\(trimmedBase)"
        }()

        guard let url = URL(string: "\(normalizedBase)/v1/audio/transcriptions") else {
            throw AIBuildersAudioError.invalidBaseURL
        }

        let audioData = try Data(contentsOf: audioFileURL)
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        if let language, !language.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            append("\(language)\r\n")
        }
        if let prompt, !prompt.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            append("\(prompt)\r\n")
        }
        if let terms, !terms.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"terms\"\r\n\r\n")
            append("\(terms)\r\n")
        }

        let filename = audioFileURL.lastPathComponent.isEmpty ? "audio.m4a" : audioFileURL.lastPathComponent
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"audio_file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(audioData)
        append("\r\n")
        append("--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIBuildersAudioError.invalidResponse
        }
        guard http.statusCode < 400 else {
            throw AIBuildersAudioError.httpError(statusCode: http.statusCode, body: data)
        }

        return try JSONDecoder().decode(TranscriptionResponse.self, from: data)
    }

    /// 测试 AI Builder 连接（调用 embeddings API，验证 token 有效）
    static func testConnection(baseURL: String, token: String) async throws {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { throw AIBuildersAudioError.invalidBaseURL }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIBuildersAudioError.missingToken }

        let normalizedBase: String = {
            if trimmedBase.hasPrefix("http://") || trimmedBase.hasPrefix("https://") { return trimmedBase }
            return "https://\(trimmedBase)"
        }()

        guard let url = URL(string: "\(normalizedBase)/v1/embeddings") else {
            throw AIBuildersAudioError.invalidBaseURL
        }

        let body = try JSONEncoder().encode(["input": "ok"])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIBuildersAudioError.invalidResponse
        }
        guard http.statusCode < 400 else {
            throw AIBuildersAudioError.httpError(statusCode: http.statusCode, body: data)
        }
    }
}
