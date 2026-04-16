//
//  MCPJobRegistry.swift
//  Pindrop
//
//  Created on 2026-04-15.
//

import Foundation

/// Maps MCP-issued job IDs to the internal MediaTranscriptionJobState IDs, and vice-versa.
/// The MCP job ID is returned to the agent; the state ID is used internally.
@MainActor
final class MCPJobRegistry {
    static let shared = MCPJobRegistry()

    private var mcpToState: [String: UUID] = [:]   // mcpJobID → jobState.id
    private var stateToMCP: [UUID: String] = [:]   // jobState.id → mcpJobID

    private init() {}

    func register(mcpJobID: String, stateID: UUID) {
        mcpToState[mcpJobID] = stateID
        stateToMCP[stateID] = mcpJobID
        Log.mcp.debug("Registered job mcpID=\(mcpJobID)")
    }

    func stateID(for mcpJobID: String) -> UUID? {
        mcpToState[mcpJobID]
    }

    func mcpJobID(for stateID: UUID) -> String? {
        stateToMCP[stateID]
    }

    func unregister(mcpJobID: String) {
        if let stateID = mcpToState.removeValue(forKey: mcpJobID) {
            stateToMCP.removeValue(forKey: stateID)
        }
    }

    /// Remove registry entries for jobs whose state IDs are no longer in the known set.
    func prune(keepingStateIDs known: Set<UUID>) {
        let toRemove = mcpToState.filter { !known.contains($0.value) }
        for (mcpID, stateID) in toRemove {
            mcpToState.removeValue(forKey: mcpID)
            stateToMCP.removeValue(forKey: stateID)
        }
    }
}
