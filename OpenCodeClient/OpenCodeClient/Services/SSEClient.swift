//
//  SSEClient.swift
//  OpenCodeClient
//

import Foundation

struct SSEEvent: Codable {
    let directory: String
    let payload: SSEPayload
}

struct SSEPayload: Codable {
    let type: String
    let properties: [String: AnyCodable]?
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let string = try? container.decode(String.self) { value = string }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let array = try? container.decode([AnyCodable].self) { value = array.map { $0.value } }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict.mapValues { $0.value } }
        else if container.decodeNil() { value = NSNull() }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let bool as Bool: try container.encode(bool)
        case let array as [Any]: try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}

actor SSEClient {
    func connect(
        baseURL: String,
        username: String? = nil,
        password: String? = nil
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        let urlString = baseURL.hasPrefix("http") ? baseURL : "http://\(baseURL)"
        guard let url = URL(string: "\(urlString)/global/event") else {
            return AsyncThrowingStream { $0.finish(throwing: APIError.invalidURL) }
        }
        var request = URLRequest(url: url)
        if let username, let password {
            let credential = "\(username):\(password)"
            if let data = credential.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    var buffer = ""
                    for try await byte in bytes {
                        let char = Character(Unicode.Scalar(byte))
                        if char == "\n" {
                            if buffer.hasPrefix("data: ") {
                                let json = String(buffer.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                                if json != "[DONE]", !json.isEmpty,
                                   let data = json.data(using: .utf8),
                                   let event = try? JSONDecoder().decode(SSEEvent.self, from: data) {
                                    continuation.yield(event)
                                }
                            }
                            buffer = ""
                        } else {
                            buffer.append(char)
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                continuation.finish()
            }
        }
    }
}
