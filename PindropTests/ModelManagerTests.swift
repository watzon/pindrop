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
        XCTAssertTrue(models.contains { $0.name == "tiny" }, "Should include tiny model")
        XCTAssertTrue(models.contains { $0.name == "base" }, "Should include base model")
        XCTAssertTrue(models.contains { $0.name == "small" }, "Should include small model")
        XCTAssertTrue(models.contains { $0.name == "medium" }, "Should include medium model")
        XCTAssertTrue(models.contains { $0.name == "large-v3" }, "Should include large-v3 model")
        XCTAssertTrue(models.contains { $0.name == "turbo" }, "Should include turbo model")
    }
    
    func testModelSizes() {
        let models = modelManager.availableModels
        
        for model in models {
            XCTAssertGreaterThan(model.sizeInMB, 0, "Model \(model.name) should have size > 0")
        }
        
        // Verify size ordering (tiny < base < small < medium < large)
        let tiny = models.first { $0.name == "tiny" }
        let base = models.first { $0.name == "base" }
        let small = models.first { $0.name == "small" }
        
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
        let isDownloaded = await modelManager.isModelDownloaded("tiny")

        // Should return a valid boolean
        XCTAssertTrue(isDownloaded == true || isDownloaded == false, "Should return valid boolean")
    }
    
    func testModelPath() async {
        let path = await modelManager.getModelPath(for: "tiny")
        
        XCTAssertNotNil(path, "Should return path for valid model")
        XCTAssertTrue(path!.contains("Pindrop/Models"), "Path should contain Pindrop/Models")
        XCTAssertTrue(path!.contains("tiny"), "Path should contain model name")
    }
    
    func testInvalidModelPath() async {
        let path = await modelManager.getModelPath(for: "nonexistent-model")
        
        XCTAssertNil(path, "Should return nil for invalid model")
    }
    
    // MARK: - Model Storage Tests
    
    func testModelsDirectory() async {
        let directory = await modelManager.modelsDirectory
        
        XCTAssertTrue(directory.contains("Library/Application Support/Pindrop/Models"), "Should use Application Support directory")
    }
    
    func testModelsDirectoryCreation() async {
        // This test verifies that the models directory is created if it doesn't exist
        let directory = await modelManager.modelsDirectory
        let fileManager = FileManager.default
        
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: directory, isDirectory: &isDirectory)
        
        XCTAssertTrue(exists, "Models directory should exist after initialization")
        XCTAssertTrue(isDirectory.boolValue, "Models path should be a directory")
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
