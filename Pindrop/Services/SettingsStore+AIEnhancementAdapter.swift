//
//  SettingsStore+AIEnhancementAdapter.swift
//  Pindrop
//
//  Created on 2026-07-09.
//
//  Simplified single-flow accessor layer over the per-purpose Assignments system.
//  Targets `.transcriptionEnhancement` so the redesigned AI pane can bind one toggle +
//  provider/model/preset without removing the advanced multi-purpose substrate.
//

import Foundation

extension SettingsStore {

    // MARK: - Simplified "Enhance transcripts" adapter

    /// Whether the transcription-enhancement purpose has an assignment (the simplified
    /// "Enhance transcripts" toggle). Reads/writes through `assignment(for: .transcriptionEnhancement)`.
    var enhanceTranscriptsEnabled: Bool {
        get { assignment(for: .transcriptionEnhancement) != nil }
        set {
            if newValue {
                guard assignment(for: .transcriptionEnhancement) == nil else { return }
                // Prefer an existing provider so enabling the toggle is one click away
                // when the user already configured credentials for another purpose.
                let provider = providers.first
                guard let provider else { return }
                setAssignment(
                    ModelAssignment(
                        providerID: provider.id,
                        modelID: aiModel.isEmpty ? Defaults.aiModel : aiModel,
                        promptPresetID: BuiltInPresetID.cleanTranscript
                    ),
                    for: .transcriptionEnhancement
                )
            } else {
                setAssignment(nil, for: .transcriptionEnhancement)
            }
        }
    }

    /// Provider UUID for the simplified enhance-transcripts flow.
    var enhanceTranscriptsProviderID: UUID? {
        get { assignment(for: .transcriptionEnhancement)?.providerID }
        set {
            guard let newValue else {
                setAssignment(nil, for: .transcriptionEnhancement)
                return
            }
            var existing = assignment(for: .transcriptionEnhancement)
                ?? ModelAssignment(
                    providerID: newValue,
                    modelID: aiModel.isEmpty ? Defaults.aiModel : aiModel,
                    promptPresetID: BuiltInPresetID.cleanTranscript
                )
            existing.providerID = newValue
            setAssignment(existing, for: .transcriptionEnhancement)
        }
    }

    /// Model ID for the simplified enhance-transcripts flow.
    var enhanceTranscriptsModelID: String? {
        get { assignment(for: .transcriptionEnhancement)?.modelID }
        set {
            guard var existing = assignment(for: .transcriptionEnhancement) else { return }
            existing.modelID = newValue ?? ""
            setAssignment(existing, for: .transcriptionEnhancement)
        }
    }

    /// Prompt preset identifier for the simplified enhance-transcripts flow.
    /// Setting a built-in preset clears any custom override.
    var enhanceTranscriptsPresetID: String? {
        get {
            let assignment = assignment(for: .transcriptionEnhancement)
            if assignment?.promptOverride != nil { return nil }
            return assignment?.promptPresetID
        }
        set {
            guard var existing = assignment(for: .transcriptionEnhancement) else { return }
            existing.promptPresetID = newValue
            existing.promptOverride = nil
            setAssignment(existing, for: .transcriptionEnhancement)
            if let newValue {
                selectedPresetId = newValue
            }
        }
    }

    /// Custom prompt override for transcription enhancement, if any.
    /// Setting a value equal to a built-in English prompt stores `nil` (English guarantee).
    var enhanceTranscriptsPromptOverride: String? {
        get { assignment(for: .transcriptionEnhancement)?.promptOverride }
        set {
            guard var existing = assignment(for: .transcriptionEnhancement) else { return }
            let normalized = BuiltInPresets.normalizedPromptOverride(
                newValue,
                presetID: existing.promptPresetID
            )
            if let normalized {
                existing.promptOverride = normalized
                existing.promptPresetID = nil
            } else {
                existing.promptOverride = nil
                if existing.promptPresetID == nil {
                    existing.promptPresetID = BuiltInPresetID.cleanTranscript
                }
            }
            setAssignment(existing, for: .transcriptionEnhancement)
        }
    }

    /// English prompt text that will be sent for transcription enhancement.
    /// Never returns a display-localized variant of a built-in default.
    func enhanceTranscriptsResolvedEnglishPrompt(
        fallback: String = Defaults.aiEnhancementPrompt
    ) -> String? {
        guard let assignment = assignment(for: .transcriptionEnhancement) else { return nil }
        return BuiltInPresets.resolvedEnglishPrompt(
            override: assignment.promptOverride,
            presetID: assignment.promptPresetID,
            fallback: fallback
        )
    }

    /// User-facing note for the AI pane: prompts are always sent in English.
    static let promptsSentInEnglishNoteKey = "Prompts are sent in English"
}
