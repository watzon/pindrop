//
//  MCPHTTPConnection.swift
//  Pindrop
//
//  Created on 2026-04-15.
//

import Foundation
import Network

/// Handles a single HTTP/1.1 connection: reads the request, validates auth,
/// routes to MCPProtocolHandler, and sends the response.
final class MCPHTTPConnection {
    private let nwConnection: NWConnection
    private weak var server: MCPServer?
    private var buffer = Data()
    private let maxBufferSize = 8 * 1024 * 1024  // 8 MB safety cap

    init(nwConnection: NWConnection, server: MCPServer) {
        self.nwConnection = nwConnection
        self.server = server
    }

    func start() {
        nwConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.notifyServerRemove()
            default:
                break
            }
        }
        nwConnection.start(queue: .global(qos: .userInitiated))
        receiveData()
    }

    func cancel() {
        nwConnection.cancel()
    }

    // MARK: - Private

    private func notifyServerRemove() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.server?.removeConnection(self)
        }
    }

    private func receiveData() {
        nwConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let data = content, !data.isEmpty {
                self.buffer.append(data)
                if self.buffer.count > self.maxBufferSize {
                    self.sendResponse(statusCode: 413, body: Data("{\"error\":\"Request too large\"}".utf8))
                    return
                }
                self.tryParseHTTPRequest()
            }

            if error != nil || isComplete {
                // If we couldn't parse a complete request, just close
                self.cancel()
                return
            }

            self.receiveData()
        }
    }

    private func tryParseHTTPRequest() {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else { return }

        guard let headerString = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            sendBadRequest(); return
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { sendBadRequest(); return }

        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { sendBadRequest(); return }
        let method = parts[0]
        let path = parts[1]

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[..<colonIdx]).lowercased()
                let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let bodyStart = buffer.index(headerEnd.lowerBound, offsetBy: 4)
        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0

        guard buffer.count >= bodyStart + contentLength else { return }  // Need more data

        let body = bodyStart + contentLength <= buffer.endIndex
            ? buffer[bodyStart..<(bodyStart + contentLength)]
            : Data()
        buffer.removeAll()

        handleRequest(method: method, path: path, headers: headers, body: Data(body))
    }

    private func handleRequest(method: String, path: String, headers: [String: String], body: Data) {
        guard let server else { cancel(); return }

        // Auth
        let authHeader = headers["authorization"] ?? ""
        guard authHeader == "Bearer \(server.token)" else {
            Log.mcp.warning("MCP request rejected: invalid token")
            sendResponse(statusCode: 401, body: Data("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32001,\"message\":\"Unauthorized\"}}".utf8))
            return
        }

        // Route
        guard method == "POST", path == "/mcp" else {
            sendResponse(statusCode: 404, body: Data("{\"error\":\"Not found. POST to /mcp\"}".utf8))
            return
        }

        Task { @MainActor [weak self, weak server] in
            guard let self, let server, let coordinator = server.coordinator else {
                self?.sendInternalError(); return
            }
            let responseData = await MCPProtocolHandler.handle(body: body, coordinator: coordinator)
            self.sendResponse(statusCode: 200, body: responseData)
        }
    }

    private func sendResponse(statusCode: Int, body: Data) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 401: statusText = "Unauthorized"
        case 404: statusText = "Not Found"
        case 413: statusText = "Payload Too Large"
        default:  statusText = "Error"
        }
        let header = "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        nwConnection.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.cancel()
        })
    }

    private func sendBadRequest() {
        sendResponse(statusCode: 400, body: Data("{\"error\":\"Bad request\"}".utf8))
    }

    private func sendInternalError() {
        sendResponse(statusCode: 500, body: Data("{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Internal error\"}}".utf8))
    }
}
