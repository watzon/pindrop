//
//  TranscriptEdit.swift
//  Pindrop
//
//  Created on 2026-04-17.
//
//  Shared value type representing a single find/replace edit against a transcript.
//  Used as the coordinator-side contract for the edit-list refinement path; the Apple
//  Foundation Models enhancer populates a parallel `@Generable` variant and converts
//  to this type before returning. Kept free of FoundationModels imports so the
//  coordinator can use it unconditionally on all supported OS versions.
//

import Foundation

struct TranscriptEdit: Equatable, Hashable, Sendable {
   /// Exact substring to find in the transcript. Case-sensitive, verbatim match.
   let find: String

   /// Replacement text. May be empty to delete.
   let replacement: String

   init(find: String, replacement: String) {
      self.find = find
      self.replacement = replacement
   }
}
