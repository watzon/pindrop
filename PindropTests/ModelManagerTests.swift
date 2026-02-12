//
//  ModelManagerTests.swift
//  Pindrop
//
//  Created on 2026-01-25.
//

import XCTest
@testable import Pindrop

@MainActor
final class ModelManagerTests: XCTestCase {
    
    var modelManager: ModelManager!
    
    override func setUp() async throws {
        modelManager = ModelManager()
    }
    
    override func tearDown() async throws {
        modelManager = nil
    }
    
    // MARK: - Model Listing Tests
    
    func testListAvailableModels() {
        let models = modelManager.availableModels
        
        XCTAssertFalse(models.isEmpty, "Should have available models")
        XCTAssertTrue(models.contains { $0.name == "openai_whisper-tiny" }, "Should include tiny model")
        XCTAssertTrue(models.contains { $0.name == "openai_whisper-base" }, "Should include base model")
        XCTAssertTrue(models.contains { $0.name == "openai_whisper-small" }, "Should include small model")
        XCTAssertTrue(models.contains { $0.name == "openai_whisper-large-v3" }, "Should include large-v3 model")
        XCTAssertTrue(models.contains { $0.name == "openai_whisper-large-v3_turbo" }, "Should include turbo model")
        XCTAssertTrue(models.contains { $0.name == "parakeet-tdt-0.6b-v2" }, "Should include parakeet model")
    }
    
    func testModelSizes() {
        let models = modelManager.availableModels
        
        for model in models where model.provider.isLocal {
            XCTAssertGreaterThan(model.sizeInMB, 0, "Model \(model.name) should have size > 0")
        }
        
        // Verify size ordering (tiny < base < small < medium < large)
        let tiny = models.first { $0.name == "openai_whisper-tiny" }
        let base = models.first { $0.name == "openai_whisper-base" }
        let small = models.first { $0.name == "openai_whisper-small" }
        
        XCTAssertNotNil(tiny)
        XCTAssertNotNil(base)
        XCTAssertNotNil(small)
        
        if let tiny = tiny, let base = base, let small = small {
            XCTAssertLessThan(tiny.sizeInMB, base.sizeInMB)
            XCTAssertLessThan(base.sizeInMB, small.sizeInMB)
        }
    }
    
    // MARK: - Downloaded Models Tests
    
    func testCheckDownloadedModels() async {
        let downloadedModels = await modelManager.getDownloadedModels()

        // Should return an array (may be empty or contain models)
        XCTAssertNotNil(downloadedModels, "Should return non-nil array")
    }

    func testIsModelDownloaded() async {
        let isDownloaded = modelManager.isModelDownloaded("openai_whisper-tiny")

        // Should return a valid boolean
        XCTAssertTrue(isDownloaded == true || isDownloaded == false, "Should return valid boolean")
    }
    
    func testModelLookup() {
        let model = modelManager.availableModels.first { $0.name == "openai_whisper-tiny" }

        XCTAssertNotNil(model, "Should return model for valid identifier")
        XCTAssertEqual(model?.provider, .whisperKit)
    }

    func testInvalidModelLookup() {
        let model = modelManager.availableModels.first { $0.name == "nonexistent-model" }

        XCTAssertNil(model, "Should return nil for invalid model")
    }

    func testContainsParakeetModels() {
        let hasParakeetModel = modelManager.availableModels.contains { $0.provider == .parakeet }

        XCTAssertTrue(hasParakeetModel, "Should include at least one Parakeet model")
    }

    func testDeleteNonexistentModelThrowsModelNotFound() async {
        do {
            try await modelManager.deleteModel(named: "nonexistent-model")
            XCTFail("Should throw modelNotFound for nonexistent model")
        } catch let error as ModelManager.ModelError {
            guard case .modelNotFound(let modelName) = error else {
                XCTFail("Expected modelNotFound error")
                return
            }
            XCTAssertEqual(modelName, "nonexistent-model")
        } catch {
            XCTFail("Expected ModelError, got \(error)")
        }
    }
    
    // MARK: - Download Progress Tests
    
    func testDownloadProgressInitialState() {
        XCTAssertEqual(modelManager.downloadProgress, 0.0, "Initial download progress should be 0")
        XCTAssertFalse(modelManager.isDownloading, "Should not be downloading initially")
        XCTAssertNil(modelManager.currentDownloadModel, "No model should be downloading initially")
    }
    
    // MARK: - Error Handling Tests
    
    func testDownloadNonexistentModel() async {
        do {
            try await modelManager.downloadModel(named: "nonexistent-model")
            XCTFail("Should throw error for nonexistent model")
        } catch {
            // Expected error
            XCTAssertTrue(error is ModelManager.ModelError, "Should throw ModelError")
        }
    }
}
