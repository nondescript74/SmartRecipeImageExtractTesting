//
//  ImageMetadataTests.swift
//  SmartRecipeImageExtractTesting
//
//  Created by Zahirudeen Premji on 11/28/25.
//

import Testing
import SwiftData
@testable import SmartRecipeImageExtractTesting

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
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        
        #expect(metadata.imageName == "TestImage")
        #expect(metadata.scale == 1.0)
        #expect(metadata.rotationDegrees == 0.0)
        #expect(metadata.history?.isEmpty == true)
    }
    
    @Test("Updating transformation saves to history")
    func testUpdateTransformation() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        
        // Initial state
        #expect(metadata.scale == 1.0)
        #expect(metadata.rotationDegrees == 0.0)
        
        // Update transformation
        metadata.updateTransformation(scale: 1.5, rotationDegrees: 45.0)
        
        #expect(metadata.scale == 1.5)
        #expect(metadata.rotationDegrees == 45.0)
        #expect(metadata.history?.count == 1)
        
        // First snapshot should have the initial values
        let firstSnapshot = try #require(metadata.history?.first)
        #expect(firstSnapshot.scale == 1.0)
        #expect(firstSnapshot.rotationDegrees == 0.0)
    }
    
    @Test("Multiple updates build history")
    func testMultipleUpdates() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        
        metadata.updateTransformation(scale: 1.2, rotationDegrees: 30.0)
        metadata.updateTransformation(scale: 1.5, rotationDegrees: 60.0)
        metadata.updateTransformation(scale: 2.0, rotationDegrees: 90.0)
        
        #expect(metadata.scale == 2.0)
        #expect(metadata.rotationDegrees == 90.0)
        #expect(metadata.history?.count == 3)
    }
    
    @Test("Undo restores previous state")
    func testUndoRestoresPreviousState() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        
        metadata.updateTransformation(scale: 1.5, rotationDegrees: 45.0)
        metadata.updateTransformation(scale: 2.0, rotationDegrees: 90.0)
        
        // Undo last change
        let undoSuccessful = metadata.undo()
        
        #expect(undoSuccessful == true)
        #expect(metadata.scale == 1.5)
        #expect(metadata.rotationDegrees == 45.0)
        #expect(metadata.history?.count == 1)
    }
    
    @Test("Undo returns false when no history")
    func testUndoWithNoHistory() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        
        let undoSuccessful = metadata.undo()
        
        #expect(undoSuccessful == false)
        #expect(metadata.scale == 1.0)
        #expect(metadata.rotationDegrees == 0.0)
    }
    
    @Test("History is limited to 20 snapshots")
    func testHistoryLimit() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        
        // Add 25 transformations
        for i in 1...25 {
            metadata.updateTransformation(
                scale: 1.0 + Double(i) * 0.1,
                rotationDegrees: Double(i) * 10.0
            )
        }
        
        // History should be capped at 20
        #expect(metadata.history?.count == 20)
    }
    
    @Test("Reset saves current state to history")
    func testReset() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata = ImageMetadata(imageName: "TestImage")
        context.insert(metadata)
        
        metadata.updateTransformation(scale: 2.0, rotationDegrees: 180.0)
        
        #expect(metadata.scale == 2.0)
        #expect(metadata.rotationDegrees == 180.0)
        
        metadata.reset()
        
        #expect(metadata.scale == 1.0)
        #expect(metadata.rotationDegrees == 0.0)
        #expect(metadata.history?.count == 2) // Original + before reset
    }
    
    @Test("Unique image name constraint")
    func testUniqueImageName() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata1 = ImageMetadata(imageName: "TestImage")
        context.insert(metadata1)
        
        try context.save()
        
        // Fetch metadata by name
        let descriptor = FetchDescriptor<ImageMetadata>(
            predicate: #Predicate { $0.imageName == "TestImage" }
        )
        
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results.first?.imageName == "TestImage")
    }
    
    @Test("Metadata persists scale and rotation")
    func testMetadataPersistence() async throws {
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let metadata = ImageMetadata(imageName: "PersistenceTest")
        metadata.updateTransformation(scale: 1.75, rotationDegrees: 135.0)
        context.insert(metadata)
        
        try context.save()
        
        // Fetch and verify
        let descriptor = FetchDescriptor<ImageMetadata>(
            predicate: #Predicate { $0.imageName == "PersistenceTest" }
        )
        
        let fetched = try #require(try context.fetch(descriptor).first)
        #expect(fetched.scale == 1.75)
        #expect(fetched.rotationDegrees == 135.0)
    }
}
