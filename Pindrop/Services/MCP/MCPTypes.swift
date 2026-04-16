//
//  MCPTypes.swift
//  Pindrop
//
//  Created on 2026-04-15.
//

import Foundation
import Security

// MARK: - JSON Value

/// Type-safe JSON value for MCP protocol messages. Avoids `Any`-based encoding.
enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:            try container.encodeNil()
        case .bool(let v):     try container.encode(v)
        case .int(let v):      try container.encode(v)
        case .double(let v):   try container.encode(v)
        case .string(let v):   try container.encode(v)
        case .array(let v):    try container.encode(v)
        case .object(let v):   try container.encode(v)
        }
    }

    var stringValue: String?       { if case .string(let s) = self { return s }; return nil }
    var intValue: Int?             { if case .int(let i) = self { return i }; return nil }
    var boolValue: Bool?           { if case .bool(let b) = self { return b }; return nil }
    var doubleValue: Double?       { if case .double(let d) = self { return d }; return nil }
    var arrayValue: [JSONValue]?   { if case .array(let a) = self { return a }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    var isNull: Bool               { if case .null = self { return true }; return false }
}

// MARK: - JSON-RPC 2.0

struct MCPRequest: Codable, Sendable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String
    let params: [String: JSONValue]?
}

struct MCPResponse: Codable, Sendable {
    let jsonrpc: String
    let id: JSONValue?
    let result: JSONValue?
    let error: MCPError?

    init(id: JSONValue?, result: JSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: JSONValue?, error: MCPError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

struct MCPError: Codable, Sendable {
    let code: Int
    let message: String
    let data: JSONValue?

    init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    static let parseError    = MCPError(code: -32700, message: "Parse error")
    static let methodNotFound = MCPError(code: -32601, message: "Method not found")
    static let invalidParams  = MCPError(code: -32602, message: "Invalid params")
    static let internalError  = MCPError(code: -32603, message: "Internal error")
    static let unauthorized   = MCPError(code: -32001, message: "Unauthorized")
}

// MARK: - Tool Definitions

struct MCPToolInputSchema: Codable, Sendable {
    let type: String
    let properties: [String: MCPPropertySchema]
    let required: [String]?

    init(properties: [String: MCPPropertySchema], required: [String]? = nil) {
        self.type = "object"
        self.properties = properties
        self.required = required
    }
}

struct MCPPropertySchema: Codable, Sendable {
    let type: String
    let description: String
    let enumValues: [String]?

    init(type: String, description: String, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }

    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
    }
}

struct MCPToolDefinition: Sendable {
    let name: String
    let description: String
    let inputSchema: MCPToolInputSchema
}

// MARK: - Tool Result

struct MCPToolResult: Sendable {
    let content: JSONValue
    let isError: Bool

    init(content: JSONValue, isError: Bool = false) {
        self.content = content
        self.isError = isError
    }

    static func success(_ value: JSONValue) -> MCPToolResult {
        MCPToolResult(content: value)
    }

    static func error(_ message: String) -> MCPToolResult {
        MCPToolResult(content: .object(["error": .string(message)]), isError: true)
    }

    /// Renders the result as a MCP tools/call response value.
    func toJSONValue() -> JSONValue {
        let textContent: JSONValue
        switch content {
        case .string(let s):
            textContent = .string(s)
        default:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(content),
               let str = String(data: data, encoding: .utf8) {
                textContent = .string(str)
            } else {
                textContent = content
            }
        }
        return .object([
            "content": .array([.object(["type": .string("text"), "text": textContent])]),
            "isError": .bool(isError)
        ])
    }
}

// MARK: - Token Generation

enum MCPTokenGenerator {
    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
