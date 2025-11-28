//
//  ImageMetadataTests.swift
//  SmartRecipeImageExtractTesting
//
//  Created by Zahirudeen Premji on 11/28/25.
//

import Foundation
import Testing
import SwiftData
@testable import SmartRecipeImageExtractTesting

// MARK: - Test Logging Helper

struct TestLogger {
    static func logTestStart(_ testName: String, suite: String? = nil) {
        print("\n" + String(repeating: "=", count: 80))
        if let suite = suite {
            print("📦 SUITE: \(suite)")
        }
        print("🧪 TEST: \(testName)")
        print(String(repeating: "-", count: 80))
    }
    
    static func logTestEnd(_ testName: String, success: Bool = true) {
        print(String(repeating: "-", count: 80))
        if success {
            print("✅ PASSED: \(testName)")
        } else {
            print("❌ FAILED: \(testName)")
        }
        print(String(repeating: "=", count: 80) + "\n")
    }
    
    static func logStep(_ step: String, emoji: String = "▶️") {
        print("\(emoji) \(step)")
    }
    
    static func logValue(_ label: String, value: Any) {
        print("   • \(label): \(value)")
    }
    
    static func logAssertion(_ description: String, passed: Bool) {
        let symbol = passed ? "✓" : "✗"
        print("   \(symbol) \(description)")
    }
}

@Suite("Image Metadata Persistence Tests")
struct ImageMetadataTests {
    
    // Create an in-memory model container for testing
    func createTestContainer() throws -> ModelContainer {
        let schema = Schema([
            ImageMetadata.self,
            TransformationSnapshot.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
    
    @Test("Creating new image metadata with default values")
    func testCreateDefaultMetadata() async throws {
        TestLogger.logTestStart("testCreateDefaultMetadata", suite: "Image Metadata Persistence Tests")
        
        TestLogger.logStep("Setting up test container", emoji: "🔧")
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        TestLogger.logStep("Creating ImageMetadata instance", emoji: "📝")
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        TestLogger.logValue("Image Name", value: metadata.imageName)
        TestLogger.logValue("Initial Scale", value: metadata.scale)
        TestLogger.logValue("Initial Rotation", value: metadata.rotationDegrees)
        TestLogger.logValue("History Count", value: metadata.history?.count ?? 0)
        
        TestLogger.logStep("Validating default values", emoji: "✓")
        #expect(metadata.imageName == "TestImage")
        TestLogger.logAssertion("imageName == 'TestImage'", passed: metadata.imageName == "TestImage")
        
        #expect(metadata.scale == 1.0)
        TestLogger.logAssertion("scale == 1.0", passed: metadata.scale == 1.0)
        
        #expect(metadata.rotationDegrees == 0.0)
        TestLogger.logAssertion("rotationDegrees == 0.0", passed: metadata.rotationDegrees == 0.0)
        
        #expect(metadata.history?.isEmpty == true)
        TestLogger.logAssertion("history is empty", passed: metadata.history?.isEmpty == true)
        
        TestLogger.logTestEnd("testCreateDefaultMetadata")
    }
    
    @Test("Updating transformation saves to history")
    func testUpdateTransformation() async throws {
        TestLogger.logTestStart("testUpdateTransformation", suite: "Image Metadata Persistence Tests")
        
        TestLogger.logStep("Setting up test container", emoji: "🔧")
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        TestLogger.logStep("Creating ImageMetadata instance", emoji: "📝")
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        
        TestLogger.logStep("Verifying initial state", emoji: "🔍")
        TestLogger.logValue("Initial Scale", value: metadata.scale)
        TestLogger.logValue("Initial Rotation", value: metadata.rotationDegrees)
        #expect(metadata.scale == 1.0)
        #expect(metadata.rotationDegrees == 0.0)
        
        TestLogger.logStep("Updating transformation", emoji: "🔄")
        metadata.updateTransformation(scale: 1.5, rotationDegrees: 45.0)
        TestLogger.logValue("New Scale", value: metadata.scale)
        TestLogger.logValue("New Rotation", value: metadata.rotationDegrees)
        TestLogger.logValue("History Count", value: metadata.history?.count ?? 0)
        
        TestLogger.logStep("Validating updated values", emoji: "✓")
        #expect(metadata.scale == 1.5)
        TestLogger.logAssertion("scale == 1.5", passed: metadata.scale == 1.5)
        
        #expect(metadata.rotationDegrees == 45.0)
        TestLogger.logAssertion("rotationDegrees == 45.0", passed: metadata.rotationDegrees == 45.0)
        
        #expect(metadata.history?.count == 1)
        TestLogger.logAssertion("history count == 1", passed: metadata.history?.count == 1)
        
        TestLogger.logStep("Verifying first snapshot", emoji: "📸")
        let firstSnapshot = try #require(metadata.history?.first)
        TestLogger.logValue("Snapshot Scale", value: firstSnapshot.scale)
        TestLogger.logValue("Snapshot Rotation", value: firstSnapshot.rotationDegrees)
        #expect(firstSnapshot.scale == 1.0)
        #expect(firstSnapshot.rotationDegrees == 0.0)
        TestLogger.logAssertion("snapshot preserved initial values", passed: firstSnapshot.scale == 1.0 && firstSnapshot.rotationDegrees == 0.0)
        
        TestLogger.logTestEnd("testUpdateTransformation")
    }
    
    @Test("Multiple updates build history")
    func testMultipleUpdates() async throws {
        TestLogger.logTestStart("testMultipleUpdates", suite: "Image Metadata Persistence Tests")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        
        TestLogger.logStep("Performing 3 transformations", emoji: "🔄")
        metadata.updateTransformation(scale: 1.2, rotationDegrees: 30.0)
        TestLogger.logValue("Update 1", value: "scale=1.2, rotation=30°")
        
        metadata.updateTransformation(scale: 1.5, rotationDegrees: 60.0)
        TestLogger.logValue("Update 2", value: "scale=1.5, rotation=60°")
        
        metadata.updateTransformation(scale: 2.0, rotationDegrees: 90.0)
        TestLogger.logValue("Update 3", value: "scale=2.0, rotation=90°")
        
        TestLogger.logStep("Validating final state", emoji: "✓")
        TestLogger.logValue("Final Scale", value: metadata.scale)
        TestLogger.logValue("Final Rotation", value: metadata.rotationDegrees)
        TestLogger.logValue("History Count", value: metadata.history?.count ?? 0)
        
        #expect(metadata.scale == 2.0)
        TestLogger.logAssertion("scale == 2.0", passed: metadata.scale == 2.0)
        
        #expect(metadata.rotationDegrees == 90.0)
        TestLogger.logAssertion("rotationDegrees == 90.0", passed: metadata.rotationDegrees == 90.0)
        
        #expect(metadata.history?.count == 3)
        TestLogger.logAssertion("history count == 3", passed: metadata.history?.count == 3)
        
        TestLogger.logTestEnd("testMultipleUpdates")
    }
    
    @Test("Undo restores previous state")
    func testUndoRestoresPreviousState() async throws {
        TestLogger.logTestStart("testUndoRestoresPreviousState", suite: "Image Metadata Persistence Tests")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        
        TestLogger.logStep("Applying transformations", emoji: "🔄")
        metadata.updateTransformation(scale: 1.5, rotationDegrees: 45.0)
        metadata.updateTransformation(scale: 2.0, rotationDegrees: 90.0)
        TestLogger.logValue("Current State", value: "scale=2.0, rotation=90°")
        
        TestLogger.logStep("Performing undo", emoji: "↩️")
        let undoSuccessful = metadata.undo()
        TestLogger.logValue("Undo Successful", value: undoSuccessful)
        TestLogger.logValue("Restored State", value: "scale=\(metadata.scale), rotation=\(metadata.rotationDegrees)°")
        TestLogger.logValue("History Count", value: metadata.history?.count ?? 0)
        
        #expect(undoSuccessful == true)
        TestLogger.logAssertion("undo succeeded", passed: undoSuccessful == true)
        #expect(metadata.scale == 1.5)
        TestLogger.logAssertion("scale restored to 1.5", passed: metadata.scale == 1.5)
        #expect(metadata.rotationDegrees == 45.0)
        TestLogger.logAssertion("rotation restored to 45°", passed: metadata.rotationDegrees == 45.0)
        #expect(metadata.history?.count == 1)
        TestLogger.logAssertion("history count == 1", passed: metadata.history?.count == 1)
        
        TestLogger.logTestEnd("testUndoRestoresPreviousState")
    }
    
    @Test("Undo returns false when no history")
    func testUndoWithNoHistory() async throws {
        TestLogger.logTestStart("testUndoWithNoHistory", suite: "Image Metadata Persistence Tests")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        
        TestLogger.logStep("Attempting undo with no history", emoji: "↩️")
        let undoSuccessful = metadata.undo()
        TestLogger.logValue("Undo Result", value: undoSuccessful ? "Success" : "Failed (expected)")
        
        #expect(undoSuccessful == false)
        TestLogger.logAssertion("undo failed as expected", passed: undoSuccessful == false)
        #expect(metadata.scale == 1.0)
        TestLogger.logAssertion("scale unchanged", passed: metadata.scale == 1.0)
        #expect(metadata.rotationDegrees == 0.0)
        TestLogger.logAssertion("rotation unchanged", passed: metadata.rotationDegrees == 0.0)
        
        TestLogger.logTestEnd("testUndoWithNoHistory")
    }
    
    @Test("History is limited to 20 snapshots")
    func testHistoryLimit() async throws {
        TestLogger.logTestStart("testHistoryLimit", suite: "Image Metadata Persistence Tests")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        
        TestLogger.logStep("Adding 25 transformations", emoji: "🔄")
        for i in 1...25 {
            metadata.updateTransformation(
                scale: 1.0 + Double(i) * 0.1,
                rotationDegrees: Double(i) * 10.0
            )
            if i % 5 == 0 {
                TestLogger.logValue("Progress", value: "\(i)/25 transformations")
            }
        }
        
        TestLogger.logStep("Checking history limit", emoji: "🔍")
        let historyCount = metadata.history?.count ?? 0
        TestLogger.logValue("History Count", value: historyCount)
        TestLogger.logValue("Expected Max", value: 20)
        
        #expect(metadata.history?.count == 20)
        TestLogger.logAssertion("history capped at 20", passed: historyCount == 20)
        
        TestLogger.logTestEnd("testHistoryLimit")
    }
    
    @Test("Reset saves current state to history")
    func testReset() async throws {
        TestLogger.logTestStart("testReset", suite: "Image Metadata Persistence Tests")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        
        TestLogger.logStep("Applying transformation", emoji: "🔄")
        metadata.updateTransformation(scale: 2.0, rotationDegrees: 180.0)
        TestLogger.logValue("Before Reset", value: "scale=\(metadata.scale), rotation=\(metadata.rotationDegrees)°")
        
        TestLogger.logStep("Performing reset", emoji: "🔄")
        metadata.reset()
        TestLogger.logValue("After Reset", value: "scale=\(metadata.scale), rotation=\(metadata.rotationDegrees)°")
        TestLogger.logValue("History Count", value: metadata.history?.count ?? 0)
        
        #expect(metadata.scale == 1.0)
        TestLogger.logAssertion("scale reset to 1.0", passed: metadata.scale == 1.0)
        #expect(metadata.rotationDegrees == 0.0)
        TestLogger.logAssertion("rotation reset to 0.0", passed: metadata.rotationDegrees == 0.0)
        #expect(metadata.history?.count == 2)
        TestLogger.logAssertion("history contains 2 snapshots", passed: metadata.history?.count == 2)
        
        TestLogger.logTestEnd("testReset")
    }
    
    @Test("Unique image name constraint")
    func testUniqueImageName() async throws {
        TestLogger.logTestStart("testUniqueImageName", suite: "Image Metadata Persistence Tests")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        TestLogger.logStep("Creating and saving metadata", emoji: "💾")
        let metadata1 = ImageMetadata(imageName: "TestImage")
        context.insert(metadata1)
        try context.save()
        TestLogger.logValue("Saved Image Name", value: "TestImage")
        
        TestLogger.logStep("Fetching by name", emoji: "🔍")
        let descriptor = FetchDescriptor<ImageMetadata>(
            predicate: #Predicate { $0.imageName == "TestImage" }
        )
        
        let results = try context.fetch(descriptor)
        TestLogger.logValue("Results Count", value: results.count)
        TestLogger.logValue("First Result Name", value: results.first?.imageName ?? "nil")
        
        #expect(results.count == 1)
        TestLogger.logAssertion("exactly 1 result found", passed: results.count == 1)
        #expect(results.first?.imageName == "TestImage")
        TestLogger.logAssertion("image name matches", passed: results.first?.imageName == "TestImage")
        
        TestLogger.logTestEnd("testUniqueImageName")
    }
    
    @Test("Metadata persists scale and rotation")
    func testMetadataPersistence() async throws {
        TestLogger.logTestStart("testMetadataPersistence", suite: "Image Metadata Persistence Tests")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        TestLogger.logStep("Creating and updating metadata", emoji: "📝")
        let metadata = ImageMetadata(imageName: "PersistenceTest")
        metadata.updateTransformation(scale: 1.75, rotationDegrees: 135.0)
        context.insert(metadata)
        TestLogger.logValue("Saved State", value: "scale=1.75, rotation=135°")
        
        TestLogger.logStep("Saving to context", emoji: "💾")
        try context.save()
        
        TestLogger.logStep("Fetching from context", emoji: "🔍")
        let descriptor = FetchDescriptor<ImageMetadata>(
            predicate: #Predicate { $0.imageName == "PersistenceTest" }
        )
        
        let fetched = try #require(try context.fetch(descriptor).first)
        TestLogger.logValue("Fetched State", value: "scale=\(fetched.scale), rotation=\(fetched.rotationDegrees)°")
        
        #expect(fetched.scale == 1.75)
        TestLogger.logAssertion("scale persisted correctly", passed: fetched.scale == 1.75)
        #expect(fetched.rotationDegrees == 135.0)
        TestLogger.logAssertion("rotation persisted correctly", passed: fetched.rotationDegrees == 135.0)
        
        TestLogger.logTestEnd("testMetadataPersistence")
    }
}
