//
//  ImageMetadata.swift
//  SmartRecipeImageExtractTesting
//
//  Created by Zahirudeen Premji on 11/28/25.
//

import SwiftUI
import SwiftData

/// SwiftData model for persisting image transformation metadata
@Model
final class ImageMetadata {
    /// Unique identifier for the image (asset name)
    @Attribute(.unique) var imageName: String
    
    /// Scale factor applied to the image
    var scale: Double
    
    /// Rotation angle in degrees
    var rotationDegrees: Double
    
    /// Date when the metadata was last modified
    var lastModified: Date
    
    /// History of transformations for undo support
    @Relationship(deleteRule: .cascade) var history: [TransformationSnapshot]?
    
    init(imageName: String, scale: Double = 1.0, rotationDegrees: Double = 0.0) {
        self.imageName = imageName
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.lastModified = Date()
        self.history = []
    }
    
    /// Updates the metadata and saves current state to history
    func updateTransformation(scale: Double, rotationDegrees: Double) {
        // Save current state to history before updating
        let snapshot = TransformationSnapshot(
            scale: self.scale,
            rotationDegrees: self.rotationDegrees,
            timestamp: self.lastModified
        )
        
        if history == nil {
            history = []
        }
        history?.append(snapshot)
        
        // Limit history to last 20 snapshots to prevent unbounded growth
        if let count = history?.count, count > 20 {
            history?.removeFirst(count - 20)
        }
        
        // Update current values
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.lastModified = Date()
    }
    
    /// Restores the previous state from history
    func undo() -> Bool {
        guard let lastSnapshot = history?.popLast() else {
            return false
        }
        
        self.scale = lastSnapshot.scale
        self.rotationDegrees = lastSnapshot.rotationDegrees
        self.lastModified = Date()
        
        return true
    }
    
    /// Resets to default values
    func reset() {
        // Save current state to history
        updateTransformation(scale: 1.0, rotationDegrees: 0.0)
    }
}

/// Represents a snapshot of transformation state for undo functionality
@Model
final class TransformationSnapshot {
    var scale: Double
    var rotationDegrees: Double
    var timestamp: Date
    
    init(scale: Double, rotationDegrees: Double, timestamp: Date) {
        self.scale = scale
        self.rotationDegrees = rotationDegrees
        self.timestamp = timestamp
    }
}
