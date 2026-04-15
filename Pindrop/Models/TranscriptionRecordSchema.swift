//
//  TranscriptionRecordSchema.swift
//  Pindrop
//
//  Created on 2026-01-28.
//  Schema versioning for TranscriptionRecord to support migrations
//

import Foundation
import SwiftData

enum TranscriptionRecordSchema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 5)
    
    static var models: [any PersistentModel.Type] {
        [
            TranscriptionRecord.self,
            MediaFolder.self,
            ParticipantProfile.self,
            ParticipantTrainingEvidence.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self
        ]
    }
    
    // V1: Original schema without AI enhancement metadata
    @Model
    final class TranscriptionRecordV1 {
        @Attribute(.unique) var id: UUID
        var text: String
        var timestamp: Date
        var duration: TimeInterval
        var modelUsed: String
        
        init(
            id: UUID = UUID(),
            text: String,
            timestamp: Date = Date(),
            duration: TimeInterval,
            modelUsed: String
        ) {
            self.id = id
            self.text = text
            self.timestamp = timestamp
            self.duration = duration
            self.modelUsed = modelUsed
        }
    }
    
    // V3: Current schema with AI enhancement + diarization metadata
    @Model
    final class TranscriptionRecord {
        @Attribute(.unique) var id: UUID
        var text: String
        var originalText: String?
        var timestamp: Date
        var duration: TimeInterval
        var modelUsed: String
        var enhancedWith: String?
        var diarizationSegmentsJSON: String?
        var sourceKindRawValue: String?
        var sourceDisplayName: String?
        var originalSourceURL: String?
        var managedMediaPath: String?
        var thumbnailPath: String?
        var folder: MediaFolder?
        @Transient var wasEnhanced: Bool = false
        @Transient var sourceKind: MediaSourceKind = .voiceRecording
        
        init(
            id: UUID = UUID(),
            text: String,
            originalText: String? = nil,
            timestamp: Date = Date(),
            duration: TimeInterval,
            modelUsed: String,
            enhancedWith: String? = nil,
            diarizationSegmentsJSON: String? = nil,
            sourceKind: MediaSourceKind = .voiceRecording,
            sourceDisplayName: String? = nil,
            originalSourceURL: String? = nil,
            managedMediaPath: String? = nil,
            thumbnailPath: String? = nil
        ) {
            self.id = id
            self.text = text
            self.originalText = originalText
            self.timestamp = timestamp
            self.duration = duration
            self.modelUsed = modelUsed
            self.enhancedWith = enhancedWith
            self.diarizationSegmentsJSON = diarizationSegmentsJSON
            self.wasEnhanced = originalText != nil && originalText != text
            self.sourceKindRawValue = sourceKind.rawValue
            self.sourceDisplayName = sourceDisplayName
            self.originalSourceURL = originalSourceURL
            self.managedMediaPath = managedMediaPath
            self.thumbnailPath = thumbnailPath
            self.sourceKind = sourceKind
        }
    }

    @Model
    final class MediaFolder {
        @Attribute(.unique) var id: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date
        var records: [TranscriptionRecord]

        init(
            id: UUID = UUID(),
            name: String,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            records: [TranscriptionRecord] = []
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.records = records
        }
    }

    @Model
    final class ParticipantProfile {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var normalizedName: String
        var displayName: String
        var centroidEmbeddingData: Data?
        var evidenceCount: Int
        var totalEvidenceDuration: TimeInterval
        var createdAt: Date
        var updatedAt: Date
        var evidence: [ParticipantTrainingEvidence]

        init(
            id: UUID = UUID(),
            normalizedName: String,
            displayName: String,
            centroidEmbeddingData: Data? = nil,
            evidenceCount: Int = 0,
            totalEvidenceDuration: TimeInterval = 0,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            evidence: [ParticipantTrainingEvidence] = []
        ) {
            self.id = id
            self.normalizedName = normalizedName
            self.displayName = displayName
            self.centroidEmbeddingData = centroidEmbeddingData
            self.evidenceCount = evidenceCount
            self.totalEvidenceDuration = totalEvidenceDuration
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.evidence = evidence
        }
    }

    @Model
    final class ParticipantTrainingEvidence {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var evidenceKey: String
        var sourceTypeRawValue: String
        var recordID: UUID?
        var sourceSpeakerID: String
        var segmentStartTime: TimeInterval
        var segmentEndTime: TimeInterval
        var segmentDuration: TimeInterval
        var confidence: Float
        var embeddingData: Data
        var createdAt: Date
        var updatedAt: Date
        var profile: ParticipantProfile?

        init(
            id: UUID = UUID(),
            evidenceKey: String,
            sourceTypeRawValue: String,
            recordID: UUID? = nil,
            sourceSpeakerID: String,
            segmentStartTime: TimeInterval,
            segmentEndTime: TimeInterval,
            segmentDuration: TimeInterval,
            confidence: Float,
            embeddingData: Data,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            profile: ParticipantProfile? = nil
        ) {
            self.id = id
            self.evidenceKey = evidenceKey
            self.sourceTypeRawValue = sourceTypeRawValue
            self.recordID = recordID
            self.sourceSpeakerID = sourceSpeakerID
            self.segmentStartTime = segmentStartTime
            self.segmentEndTime = segmentEndTime
            self.segmentDuration = segmentDuration
            self.confidence = confidence
            self.embeddingData = embeddingData
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.profile = profile
        }
    }
}

// V1 Schema Version
enum TranscriptionRecordSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [
            TranscriptionRecordV1.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self
        ]
    }
    
    @Model
    final class TranscriptionRecordV1 {
        @Attribute(.unique) var id: UUID
        var text: String
        var timestamp: Date
        var duration: TimeInterval
        var modelUsed: String
        
        init(
            id: UUID = UUID(),
            text: String,
            timestamp: Date = Date(),
            duration: TimeInterval,
            modelUsed: String
        ) {
            self.id = id
            self.text = text
            self.timestamp = timestamp
            self.duration = duration
            self.modelUsed = modelUsed
        }
    }
}

// V2 Schema Version
enum TranscriptionRecordSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 1)

    static var models: [any PersistentModel.Type] {
        [
            TranscriptionRecord.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self
        ]
    }

    @Model
    final class TranscriptionRecord {
        @Attribute(.unique) var id: UUID
        var text: String
        var originalText: String?
        var timestamp: Date
        var duration: TimeInterval
        var modelUsed: String
        var enhancedWith: String?
        @Transient var wasEnhanced: Bool = false
        
        init(
            id: UUID = UUID(),
            text: String,
            originalText: String? = nil,
            timestamp: Date = Date(),
            duration: TimeInterval,
            modelUsed: String,
            enhancedWith: String? = nil
        ) {
            self.id = id
            self.text = text
            self.originalText = originalText
            self.timestamp = timestamp
            self.duration = duration
            self.modelUsed = modelUsed
            self.enhancedWith = enhancedWith
            self.wasEnhanced = originalText != nil && originalText != text
        }
    }
}

// V3 Schema Version (Current)
enum TranscriptionRecordSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 2)

    static var models: [any PersistentModel.Type] {
        [
            TranscriptionRecord.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self
        ]
    }

    @Model
    final class TranscriptionRecord {
        @Attribute(.unique) var id: UUID
        var text: String
        var originalText: String?
        var timestamp: Date
        var duration: TimeInterval
        var modelUsed: String
        var enhancedWith: String?
        var diarizationSegmentsJSON: String?
        @Transient var wasEnhanced: Bool = false
        
        init(
            id: UUID = UUID(),
            text: String,
            originalText: String? = nil,
            timestamp: Date = Date(),
            duration: TimeInterval,
            modelUsed: String,
            enhancedWith: String? = nil,
            diarizationSegmentsJSON: String? = nil
        ) {
            self.id = id
            self.text = text
            self.originalText = originalText
            self.timestamp = timestamp
            self.duration = duration
            self.modelUsed = modelUsed
            self.enhancedWith = enhancedWith
            self.diarizationSegmentsJSON = diarizationSegmentsJSON
            self.wasEnhanced = originalText != nil && originalText != text
        }
    }
}

// V4 Schema Version (Current)
enum TranscriptionRecordSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 3)

    static var models: [any PersistentModel.Type] {
        [
            TranscriptionRecord.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self
        ]
    }

    @Model
    final class TranscriptionRecord {
        @Attribute(.unique) var id: UUID
        var text: String
        var originalText: String?
        var timestamp: Date
        var duration: TimeInterval
        var modelUsed: String
        var enhancedWith: String?
        var diarizationSegmentsJSON: String?
        var sourceKindRawValue: String?
        var sourceDisplayName: String?
        var originalSourceURL: String?
        var managedMediaPath: String?
        var thumbnailPath: String?
        @Transient var wasEnhanced: Bool = false
        @Transient var sourceKind: MediaSourceKind = .voiceRecording

        init(
            id: UUID = UUID(),
            text: String,
            originalText: String? = nil,
            timestamp: Date = Date(),
            duration: TimeInterval,
            modelUsed: String,
            enhancedWith: String? = nil,
            diarizationSegmentsJSON: String? = nil,
            sourceKind: MediaSourceKind = .voiceRecording,
            sourceDisplayName: String? = nil,
            originalSourceURL: String? = nil,
            managedMediaPath: String? = nil,
            thumbnailPath: String? = nil
        ) {
            self.id = id
            self.text = text
            self.originalText = originalText
            self.timestamp = timestamp
            self.duration = duration
            self.modelUsed = modelUsed
            self.enhancedWith = enhancedWith
            self.diarizationSegmentsJSON = diarizationSegmentsJSON
            self.sourceKindRawValue = sourceKind.rawValue
            self.sourceDisplayName = sourceDisplayName
            self.originalSourceURL = originalSourceURL
            self.managedMediaPath = managedMediaPath
            self.thumbnailPath = thumbnailPath
            self.wasEnhanced = originalText != nil && originalText != text
            self.sourceKind = sourceKind
        }
    }
}

// V5 Schema Version (Current)
enum TranscriptionRecordSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 4)

    static var models: [any PersistentModel.Type] {
        [
            TranscriptionRecord.self,
            MediaFolder.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self
        ]
    }

    @Model
    final class MediaFolder {
        @Attribute(.unique) var id: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date
        var records: [TranscriptionRecord]

        init(
            id: UUID = UUID(),
            name: String,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            records: [TranscriptionRecord] = []
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.records = records
        }
    }

    @Model
    final class TranscriptionRecord {
        @Attribute(.unique) var id: UUID
        var text: String
        var originalText: String?
        var timestamp: Date
        var duration: TimeInterval
        var modelUsed: String
        var enhancedWith: String?
        var diarizationSegmentsJSON: String?
        var sourceKindRawValue: String?
        var sourceDisplayName: String?
        var originalSourceURL: String?
        var managedMediaPath: String?
        var thumbnailPath: String?
        var folder: MediaFolder?
        @Transient var wasEnhanced: Bool = false
        @Transient var sourceKind: MediaSourceKind = .voiceRecording

        init(
            id: UUID = UUID(),
            text: String,
            originalText: String? = nil,
            timestamp: Date = Date(),
            duration: TimeInterval,
            modelUsed: String,
            enhancedWith: String? = nil,
            diarizationSegmentsJSON: String? = nil,
            sourceKind: MediaSourceKind = .voiceRecording,
            sourceDisplayName: String? = nil,
            originalSourceURL: String? = nil,
            managedMediaPath: String? = nil,
            thumbnailPath: String? = nil,
            folder: MediaFolder? = nil
        ) {
            self.id = id
            self.text = text
            self.originalText = originalText
            self.timestamp = timestamp
            self.duration = duration
            self.modelUsed = modelUsed
            self.enhancedWith = enhancedWith
            self.diarizationSegmentsJSON = diarizationSegmentsJSON
            self.sourceKindRawValue = sourceKind.rawValue
            self.sourceDisplayName = sourceDisplayName
            self.originalSourceURL = originalSourceURL
            self.managedMediaPath = managedMediaPath
            self.thumbnailPath = thumbnailPath
            self.folder = folder
            self.wasEnhanced = originalText != nil && originalText != text
            self.sourceKind = sourceKind
        }
    }
}

// V6 Schema Version (Current)
enum TranscriptionRecordSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 5)

    static var models: [any PersistentModel.Type] {
        [
            TranscriptionRecord.self,
            MediaFolder.self,
            ParticipantProfile.self,
            ParticipantTrainingEvidence.self,
            WordReplacement.self,
            VocabularyWord.self,
            Note.self,
            PromptPreset.self
        ]
    }

    @Model
    final class MediaFolder {
        @Attribute(.unique) var id: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date
        var records: [TranscriptionRecord]

        init(
            id: UUID = UUID(),
            name: String,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            records: [TranscriptionRecord] = []
        ) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.records = records
        }
    }

    @Model
    final class ParticipantProfile {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var normalizedName: String
        var displayName: String
        var centroidEmbeddingData: Data?
        var evidenceCount: Int
        var totalEvidenceDuration: TimeInterval
        var createdAt: Date
        var updatedAt: Date
        var evidence: [ParticipantTrainingEvidence]

        init(
            id: UUID = UUID(),
            normalizedName: String,
            displayName: String,
            centroidEmbeddingData: Data? = nil,
            evidenceCount: Int = 0,
            totalEvidenceDuration: TimeInterval = 0,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            evidence: [ParticipantTrainingEvidence] = []
        ) {
            self.id = id
            self.normalizedName = normalizedName
            self.displayName = displayName
            self.centroidEmbeddingData = centroidEmbeddingData
            self.evidenceCount = evidenceCount
            self.totalEvidenceDuration = totalEvidenceDuration
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.evidence = evidence
        }
    }

    @Model
    final class ParticipantTrainingEvidence {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var evidenceKey: String
        var sourceTypeRawValue: String
        var recordID: UUID?
        var sourceSpeakerID: String
        var segmentStartTime: TimeInterval
        var segmentEndTime: TimeInterval
        var segmentDuration: TimeInterval
        var confidence: Float
        var embeddingData: Data
        var createdAt: Date
        var updatedAt: Date
        var profile: ParticipantProfile?

        init(
            id: UUID = UUID(),
            evidenceKey: String,
            sourceTypeRawValue: String,
            recordID: UUID? = nil,
            sourceSpeakerID: String,
            segmentStartTime: TimeInterval,
            segmentEndTime: TimeInterval,
            segmentDuration: TimeInterval,
            confidence: Float,
            embeddingData: Data,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            profile: ParticipantProfile? = nil
        ) {
            self.id = id
            self.evidenceKey = evidenceKey
            self.sourceTypeRawValue = sourceTypeRawValue
            self.recordID = recordID
            self.sourceSpeakerID = sourceSpeakerID
            self.segmentStartTime = segmentStartTime
            self.segmentEndTime = segmentEndTime
            self.segmentDuration = segmentDuration
            self.confidence = confidence
            self.embeddingData = embeddingData
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.profile = profile
        }
    }

    @Model
    final class TranscriptionRecord {
        @Attribute(.unique) var id: UUID
        var text: String
        var originalText: String?
        var timestamp: Date
        var duration: TimeInterval
        var modelUsed: String
        var enhancedWith: String?
        var diarizationSegmentsJSON: String?
        var sourceKindRawValue: String?
        var sourceDisplayName: String?
        var originalSourceURL: String?
        var managedMediaPath: String?
        var thumbnailPath: String?
        var folder: MediaFolder?
        @Transient var wasEnhanced: Bool = false
        @Transient var sourceKind: MediaSourceKind = .voiceRecording

        init(
            id: UUID = UUID(),
            text: String,
            originalText: String? = nil,
            timestamp: Date = Date(),
            duration: TimeInterval,
            modelUsed: String,
            enhancedWith: String? = nil,
            diarizationSegmentsJSON: String? = nil,
            sourceKind: MediaSourceKind = .voiceRecording,
            sourceDisplayName: String? = nil,
            originalSourceURL: String? = nil,
            managedMediaPath: String? = nil,
            thumbnailPath: String? = nil,
            folder: MediaFolder? = nil
        ) {
            self.id = id
            self.text = text
            self.originalText = originalText
            self.timestamp = timestamp
            self.duration = duration
            self.modelUsed = modelUsed
            self.enhancedWith = enhancedWith
            self.diarizationSegmentsJSON = diarizationSegmentsJSON
            self.sourceKindRawValue = sourceKind.rawValue
            self.sourceDisplayName = sourceDisplayName
            self.originalSourceURL = originalSourceURL
            self.managedMediaPath = managedMediaPath
            self.thumbnailPath = thumbnailPath
            self.folder = folder
            self.wasEnhanced = originalText != nil && originalText != text
            self.sourceKind = sourceKind
        }
    }
}

// Migration Plan
enum TranscriptionRecordMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            TranscriptionRecordSchemaV1.self,
            TranscriptionRecordSchemaV2.self,
            TranscriptionRecordSchemaV3.self,
            TranscriptionRecordSchemaV4.self,
            TranscriptionRecordSchemaV5.self,
            TranscriptionRecordSchemaV6.self
        ]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6]
    }

    // Lightweight migration from V1 to V2
    // Adds optional originalText and enhancedWith fields
    // Existing records will have nil values for new fields
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: TranscriptionRecordSchemaV1.self,
        toVersion: TranscriptionRecordSchemaV2.self
    )

    // Lightweight migration from V2 to V3
    // Adds optional diarizationSegmentsJSON field
    // Existing records will have nil values for the new field
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: TranscriptionRecordSchemaV2.self,
        toVersion: TranscriptionRecordSchemaV3.self
    )

    // Lightweight migration from V3 to V4.
    // Adds optional media metadata fields; existing records derive voiceRecording at read time.
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: TranscriptionRecordSchemaV3.self,
        toVersion: TranscriptionRecordSchemaV4.self
    )

    // Lightweight migration from V4 to V5.
    // Adds the optional media-folder relationship and folder table.
    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: TranscriptionRecordSchemaV4.self,
        toVersion: TranscriptionRecordSchemaV5.self
    )

    // Lightweight migration from V5 to V6.
    // Adds participant profiles and training evidence tables.
    static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: TranscriptionRecordSchemaV5.self,
        toVersion: TranscriptionRecordSchemaV6.self
    )
}
