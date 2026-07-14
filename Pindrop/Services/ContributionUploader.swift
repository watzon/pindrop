//
//  ContributionUploader.swift
//  Pindrop
//
//  Created on 2026-07-14.
//
//  Upload seam for the opt-in training-data contribution program. Deliberately
//  inert: no backend exists yet, and the v1 redactor cannot remove free-form
//  personal names (see TrainingTextRedactor), so contributions MUST stay on
//  device. Wire a real uploader only together with name-level redaction and a
//  distinct upload consent — enabling collection is not consent to upload.
//

import Foundation

@MainActor
protocol ContributionUploader {
    func enqueue(_ contribution: TrainingContribution)
}

/// The only shipped implementation: does nothing, uploads nothing.
@MainActor
struct NoOpContributionUploader: ContributionUploader {
    func enqueue(_ contribution: TrainingContribution) {
        // Intentionally empty — contributions never leave this Mac.
    }
}
