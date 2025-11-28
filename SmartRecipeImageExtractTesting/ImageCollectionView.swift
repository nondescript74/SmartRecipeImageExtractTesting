//
//  ImageCollectionView.swift
//  SmartRecipeImageExtractTesting
//
//  Created by Zahirudeen Premji on 11/26/25.
//


import SwiftUI
import SwiftData

// MARK: - Main Collection View
struct ImageCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allMetadata: [ImageMetadata]
    
    // Replace with your actual asset names
    let imageNames = ["AmNC", "CaPi", "Mpio", "LaYS", "CoCh", "CuRa", "DhCh", "DrCa", "VeSo", "KaSM", "LeCh", "EgRa", "GaMa", "GhCb", "Sher", "HoYo", "Kach", "Vs", "Itc"]
    
    @State private var selectedImage: String?
    
    let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 16)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(imageNames, id: \.self) { imageName in
                        ImageThumbnail(
                            imageName: imageName,
                            hasModifications: hasModifications(for: imageName)
                        )
                        .onTapGesture {
                            selectedImage = imageName
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Image Collection")
            .sheet(item: Binding(
                get: { selectedImage.map { ImageItem(name: $0) } },
                set: { selectedImage = $0?.name }
            )) { item in
                ImageDetailView(imageName: item.name)
            }
        }
    }
    
    /// Check if an image has saved modifications
    private func hasModifications(for imageName: String) -> Bool {
        guard let metadata = allMetadata.first(where: { $0.imageName == imageName }) else {
            return false
        }
        return metadata.scale != 1.0 || metadata.rotationDegrees != 0.0
    }
}

// MARK: - Thumbnail View
struct ImageThumbnail: View {
    let imageName: String
    let hasModifications: Bool
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(hasModifications ? Color.blue : Color.gray.opacity(0.3), lineWidth: hasModifications ? 2 : 1)
                )
                .shadow(radius: 3)
            
            // Badge indicator for modified images
            if hasModifications {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    )
                    .offset(x: 5, y: -5)
            }
        }
    }
}

// MARK: - Detail View with Scale and Rotation
struct ImageDetailView: View {
    let imageName: String
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var scale: CGFloat = 1.0
    @State private var rotation: Angle = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastRotation: Angle = .zero
    @State private var imageMetadata: ImageMetadata?
    @State private var canUndo: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.opacity(0.9)
                    .ignoresSafeArea()
                
                VStack {
                    Spacer()
                    
                    // Main Image with gestures
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .rotationEffect(rotation)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    saveMetadata()
                                }
                        )
                        .gesture(
                            RotationGesture()
                                .onChanged { value in
                                    rotation = lastRotation + value
                                }
                                .onEnded { _ in
                                    lastRotation = rotation
                                    saveMetadata()
                                }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Spacer()
                    
                    // Control Panel
                    VStack(spacing: 20) {
                        // Scale Control
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "minus.magnifyingglass")
                                    .foregroundColor(.white)
                                
                                Slider(value: $scale, in: 0.5...3.0)
                                    .accentColor(.white)
                                    .onChange(of: scale) { oldValue, newValue in
                                        lastScale = newValue
                                    }
                                
                                Image(systemName: "plus.magnifyingglass")
                                    .foregroundColor(.white)
                            }
                            
                            Text("Scale: \(scale, specifier: "%.2f")x")
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                        
                        // Rotation Control
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "rotate.left")
                                    .foregroundColor(.white)
                                
                                Slider(value: Binding(
                                    get: { rotation.degrees },
                                    set: {
                                        rotation = .degrees($0)
                                        lastRotation = rotation
                                    }
                                ), in: -180...180)
                                .accentColor(.white)
                                
                                Image(systemName: "rotate.right")
                                    .foregroundColor(.white)
                            }
                            
                            Text("Rotation: \(rotation.degrees, specifier: "%.0f")°")
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                        
                        // Action Buttons
                        HStack(spacing: 16) {
                            // Undo Button
                            Button(action: undoLastChange) {
                                Label("Undo", systemImage: "arrow.uturn.backward")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(canUndo ? Color.orange : Color.gray)
                                    .cornerRadius(10)
                            }
                            .disabled(!canUndo)
                            
                            // Reset Button
                            Button(action: resetTransformations) {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                            
                            // Save Button
                            Button(action: saveMetadata) {
                                Label("Save", systemImage: "checkmark")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(Color.green)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.5))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        saveMetadata()
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .principal) {
                    Text(imageName)
                        .foregroundColor(.white)
                        .font(.headline)
                }
            }
        }
        .onAppear {
            loadMetadata()
        }
    }
    
    /// Loads saved metadata for the image
    private func loadMetadata() {
        let descriptor = FetchDescriptor<ImageMetadata>(
            predicate: #Predicate { $0.imageName == imageName }
        )
        
        if let existing = try? modelContext.fetch(descriptor).first {
            imageMetadata = existing
            scale = existing.scale
            rotation = .degrees(existing.rotationDegrees)
            lastScale = existing.scale
            lastRotation = .degrees(existing.rotationDegrees)
            canUndo = !(existing.history?.isEmpty ?? true)
        } else {
            // Create new metadata for this image
            let newMetadata = ImageMetadata(imageName: imageName)
            modelContext.insert(newMetadata)
            imageMetadata = newMetadata
            canUndo = false
        }
    }
    
    /// Saves current transformation state
    private func saveMetadata() {
        guard let metadata = imageMetadata else { return }
        
        // Only save if values have actually changed
        let hasChanged = abs(metadata.scale - scale) > 0.01 || 
                        abs(metadata.rotationDegrees - rotation.degrees) > 0.1
        
        if hasChanged {
            metadata.updateTransformation(
                scale: scale,
                rotationDegrees: rotation.degrees
            )
            
            do {
                try modelContext.save()
                canUndo = !(metadata.history?.isEmpty ?? true)
            } catch {
                print("Error saving metadata: \(error)")
            }
        }
    }
    
    /// Undoes the last transformation
    private func undoLastChange() {
        guard let metadata = imageMetadata else { return }
        
        if metadata.undo() {
            scale = metadata.scale
            rotation = .degrees(metadata.rotationDegrees)
            lastScale = metadata.scale
            lastRotation = .degrees(metadata.rotationDegrees)
            
            do {
                try modelContext.save()
                canUndo = !(metadata.history?.isEmpty ?? true)
            } catch {
                print("Error saving undo: \(error)")
            }
        }
    }
    
    /// Resets transformations to default
    private func resetTransformations() {
        guard let metadata = imageMetadata else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            metadata.reset()
            scale = 1.0
            rotation = .zero
            lastScale = 1.0
            lastRotation = .zero
            
            do {
                try modelContext.save()
                canUndo = !(metadata.history?.isEmpty ?? true)
            } catch {
                print("Error resetting metadata: \(error)")
            }
        }
    }
}

// MARK: - Helper Model
struct ImageItem: Identifiable {
    let id = UUID()
    let name: String
}

// MARK: - Preview
#Preview {
    ImageCollectionView()
}
