//
//  AIEnhancementService+ResolvedAssignment.swift
//  Pindrop
//
//  Created on 2026-04-16.
//
//  Compatibility overlays that let callers invoke AIEnhancementService with a pre-resolved
//  `ResolvedAssignment` bundle from the v2 config. These overloads pick apart the bundle
//  and delegate to the existing loose-argument methods, so call sites migrate one at a
//  time. Once every caller has moved over, the legacy signatures can be deleted.
//
//  The service itself does not reach into `SettingsStore` — prompt lookups (preset → text)
//  remain the caller's responsibility. The `defaultPrompt` argument is the fallback used
//  when the assignment carries no `promptOverride`.
//

import Foundation

extension AIEnhancementService {

   /// Full-context enhance() overload driven by a ResolvedAssignment.
   func enhance(
      text: String,
      assignment: ResolvedAssignment,
      defaultPrompt: String,
      imageBase64: String? = nil,
      context: ContextMetadata = .none
   ) async throws -> String {
      try await enhance(
         text: text,
         apiEndpoint: assignment.endpoint ?? "",
         apiKey: assignment.apiKey,
         model: assignment.modelID,
         customPrompt: assignment.prompt ?? defaultPrompt,
         imageBase64: imageBase64,
         context: context,
         provider: assignment.kind
      )
   }

   /// enhanceNote() overload driven by ResolvedAssignments. Takes one assignment for body
   /// enhancement and an optional separate assignment for metadata generation — callers that
   /// want note metadata to run on a different provider than note body enhancement pass
   /// both; callers that want to reuse a single provider pass the same value twice (or pass
   /// `nil` for metadata and set `generateMetadata: false`).
   func enhanceNote(
      content: String,
      bodyAssignment: ResolvedAssignment,
      metadataAssignment: ResolvedAssignment?,
      bodyDefaultPrompt: String,
      generateMetadata: Bool = true,
      existingTags: [String] = [],
      context: ContextMetadata = .none
   ) async throws -> EnhancedNote {
      guard !content.isEmpty else {
         return EnhancedNote(content: content, title: "Untitled Note", tags: [])
      }

      let enhancedContent = try await enhance(
         text: content,
         assignment: bodyAssignment,
         defaultPrompt: bodyDefaultPrompt,
         imageBase64: nil,
         context: context
      )

      var title = generateFallbackTitle(from: enhancedContent)
      var tags: [String] = []

      if generateMetadata, let metadataAssignment {
         do {
            let metadata = try await generateNoteMetadata(
               content: enhancedContent,
               apiEndpoint: metadataAssignment.endpoint ?? "",
               apiKey: metadataAssignment.apiKey,
               model: metadataAssignment.modelID,
               existingTags: existingTags,
               provider: metadataAssignment.kind
            )
            title = metadata.title
            tags = metadata.tags
         } catch {
            Log.aiEnhancement.warning(
               "Metadata generation failed, using fallback: \(error.localizedDescription)")
         }
      }

      return EnhancedNote(content: enhancedContent, title: title, tags: tags)
   }

   /// generateTranscriptionMetadata() overload driven by a ResolvedAssignment.
   func generateTranscriptionMetadata(
      transcription: String,
      assignment: ResolvedAssignment,
      includeTitle: Bool
   ) async throws -> (title: String?, summary: String) {
      try await generateTranscriptionMetadata(
         transcription: transcription,
         apiEndpoint: assignment.endpoint ?? "",
         apiKey: assignment.apiKey,
         model: assignment.modelID,
         includeTitle: includeTitle,
         provider: assignment.kind
      )
   }
}
