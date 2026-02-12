//
//  Message.swift
//  OpenCodeClient
//

import Foundation

struct Message: Codable, Identifiable {
    let id: String
    let sessionID: String
    let role: String
    let parentID: String?
    let model: ModelInfo?
    let time: TimeInfo
    let finish: String?

    struct ModelInfo: Codable {
        let providerID: String
        let modelID: String
    }

    struct TimeInfo: Codable {
        let created: Int
        let completed: Int?
    }

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
}

struct MessageWithParts: Codable {
    let info: Message
    let parts: [Part]
}

struct Part: Codable, Identifiable {
    let id: String
    let messageID: String
    let sessionID: String
    let type: String
    let text: String?
    let tool: String?
    let callID: String?
    let state: String?
    let metadata: PartMetadata?
    let files: [FileChange]?

    struct FileChange: Codable {
        let path: String
        let additions: Int
        let deletions: Int
        let status: String?
    }

    struct PartMetadata: Codable {
        let path: String?
        let title: String?
        let input: String?
    }

    var isText: Bool { type == "text" }
    var isReasoning: Bool { type == "reasoning" }
    var isTool: Bool { type == "tool" }
    var isPatch: Bool { type == "patch" }
}
