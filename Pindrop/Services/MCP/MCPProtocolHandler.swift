//
//  MCPProtocolHandler.swift
//  Pindrop
//
//  Created on 2026-04-15.
//

import Foundation

/// Implements MCP JSON-RPC 2.0: initialize, tools/list, tools/call.
@MainActor
enum MCPProtocolHandler {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    static func handle(body: Data, coordinator: AppCoordinator) async -> Data {
        let request: MCPRequest
        do {
            request = try JSONDecoder().decode(MCPRequest.self, from: body)
        } catch {
            let response = MCPResponse(id: nil, error: .parseError)
            return encode(response)
        }

        Log.mcp.debug("MCP method: \(request.method)")

        let response: MCPResponse
        switch request.method {
        case "initialize":
            response = handleInitialize(id: request.id)
        case "notifications/initialized":
            return Data()
        case "tools/list":
            response = handleToolsList(id: request.id)
        case "tools/call":
            response = await handleToolsCall(id: request.id, params: request.params ?? [:], coordinator: coordinator)
        default:
            Log.mcp.warning("Unknown MCP method: \(request.method)")
            response = MCPResponse(id: request.id, error: .methodNotFound)
        }

        return encode(response)
    }

    private static func handleInitialize(id: JSONValue?) -> MCPResponse {
        let result: JSONValue = .object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object([
                "name": .string("pindrop"),
                "version": .string(Bundle.main.appShortVersionString)
            ])
        ])
        return MCPResponse(id: id, result: result)
    }

    private static func handleToolsList(id: JSONValue?) -> MCPResponse {
        let tools = MCPToolDispatcher.allToolDefinitions()
        let toolValues: [JSONValue] = tools.map { tool in
            let propsObj: [String: JSONValue] = tool.inputSchema.properties.reduce(into: [:]) { dict, pair in
                var prop: [String: JSONValue] = [
                    "type": .string(pair.value.type),
                    "description": .string(pair.value.description)
                ]
                if let enums = pair.value.enumValues {
                    prop["enum"] = .array(enums.map { .string($0) })
                }
                dict[pair.key] = .object(prop)
            }
            var schema: [String: JSONValue] = [
                "type": .string("object"),
                "properties": .object(propsObj)
            ]
            if let req = tool.inputSchema.required {
                schema["required"] = .array(req.map { .string($0) })
            }
            return .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": .object(schema)
            ])
        }
        return MCPResponse(id: id, result: .object(["tools": .array(toolValues)]))
    }

    private static func handleToolsCall(
        id: JSONValue?,
        params: [String: JSONValue],
        coordinator: AppCoordinator
    ) async -> MCPResponse {
        guard let toolName = params["name"]?.stringValue else {
            return MCPResponse(id: id, error: .invalidParams)
        }
        let arguments = params["arguments"]?.objectValue ?? [:]
        let result = await MCPToolDispatcher.dispatch(
            toolName: toolName,
            arguments: arguments,
            coordinator: coordinator
        )
        return MCPResponse(id: id, result: result.toJSONValue())
    }

    private static func encode(_ response: MCPResponse) -> Data {
        (try? encoder.encode(response)) ?? Data("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Encode error\"}}".utf8)
    }
}
