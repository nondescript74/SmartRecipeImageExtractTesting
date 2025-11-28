//
//  ImageMetadataManagerView.swift
//  SmartRecipeImageExtractTesting
//
//  Created by Zahirudeen Premji on 11/28/25.
//

import SwiftUI
import SwiftData

/// A utility view for managing image metadata across the collection
/// Useful for debugging, bulk operations, or administrative tasks
struct ImageMetadataManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ImageMetadata.lastModified, order: .reverse) private var allMetadata: [ImageMetadata]
    
    @State private var showingClearAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Statistics") {
                    HStack {
                        Text("Total Images with Metadata")
                        Spacer()
                        Text("\(allMetadata.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Modified Images")
                        Spacer()
                        Text("\(modifiedImagesCount)")
                            .foregroundColor(.blue)
                    }
                    
                    HStack {
                        Text("Total History Entries")
                        Spacer()
                        Text("\(totalHistoryCount)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("All Image Metadata") {
                    if allMetadata.isEmpty {
                        Text("No metadata saved yet")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(allMetadata) { metadata in
                            ImageMetadataRow(metadata: metadata)
                        }
                        .onDelete(perform: deleteMetadata)
                    }
                }
                
                Section("Actions") {
                    Button(role: .destructive, action: {
                        showingClearAlert = true
                    }) {
                        Label("Clear All Metadata", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Metadata Manager")
            .alert("Clear All Metadata?", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive, action: clearAllMetadata)
            } message: {
                Text("This will delete all saved transformations. Original images will not be affected.")
            }
        }
    }
    
    private var modifiedImagesCount: Int {
        allMetadata.filter { $0.scale != 1.0 || $0.rotationDegrees != 0.0 }.count
    }
    
    private var totalHistoryCount: Int {
        allMetadata.reduce(0) { $0 + ($1.history?.count ?? 0) }
    }
    
    private func deleteMetadata(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(allMetadata[index])
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Error deleting metadata: \(error)")
        }
    }
    
    private func clearAllMetadata() {
        for metadata in allMetadata {
            modelContext.delete(metadata)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Error clearing metadata: \(error)")
        }
    }
}

// MARK: - Metadata Row View
struct ImageMetadataRow: View {
    let metadata: ImageMetadata
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(metadata.imageName)
                    .font(.headline)
                
                Spacer()
                
                if isModified {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            
            HStack {
                Label("\(metadata.scale, specifier: "%.2f")x", systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Label("\(metadata.rotationDegrees, specifier: "%.0f")°", systemImage: "rotate.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Modified: \(metadata.lastModified, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let historyCount = metadata.history?.count, historyCount > 0 {
                    Text("\(historyCount) in history")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var isModified: Bool {
        metadata.scale != 1.0 || metadata.rotationDegrees != 0.0
    }
}

// MARK: - Preview
#Preview {
    ImageMetadataManagerView()
        .modelContainer(for: [ImageMetadata.self, TransformationSnapshot.self])
}

// MARK: - Example Usage in Main App
/// Add this extension to integrate the metadata manager into your app
extension ImageCollectionView {
    /// Modified collection view with metadata manager access
    struct WithMetadataManager: View {
        @State private var showingManager = false
        
        var body: some View {
            ImageCollectionView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingManager = true }) {
                            Image(systemName: "gearshape.fill")
                        }
                    }
                }
                .sheet(isPresented: $showingManager) {
                    ImageMetadataManagerView()
                }
        }
    }
}
