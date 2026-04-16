//
//  MCPServer.swift
//  Pindrop
//
//  Created on 2026-04-15.
//

import Foundation
import Network

/// Lightweight localhost HTTP server that hosts the MCP endpoint.
/// Start it when mcpServerEnabled is true; stop it when the user disables it or the app quits.
@MainActor
final class MCPServer {
    private(set) var isRunning = false
    private var listener: NWListener?
    private var activeConnections: [MCPHTTPConnection] = []

    let port: UInt16
    let token: String

    /// Injected by AppCoordinator after initialization.
    weak var coordinator: AppCoordinator?

    init(port: UInt16, token: String) {
        self.port = port
        self.token = token
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] nwConn in
                Task { @MainActor [weak self] in
                    self?.acceptConnection(nwConn)
                }
            }

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerState(state)
                }
            }

            listener.start(queue: .global(qos: .userInitiated))
            isRunning = true
            Log.mcp.info("MCP server started on port \(self.port)")
        } catch {
            Log.mcp.error("Failed to start MCP server on port \(self.port): \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        activeConnections.forEach { $0.cancel() }
        activeConnections.removeAll()
        isRunning = false
        Log.mcp.info("MCP server stopped")
    }

    // MARK: - Connection management

    func removeConnection(_ connection: MCPHTTPConnection) {
        activeConnections.removeAll { $0 === connection }
    }

    // MARK: - Private

    private func acceptConnection(_ nwConnection: NWConnection) {
        let connection = MCPHTTPConnection(nwConnection: nwConnection, server: self)
        activeConnections.append(connection)
        connection.start()
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .failed(let error):
            Log.mcp.error("MCP listener failed: \(error)")
            isRunning = false
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }
}
