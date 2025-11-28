//
//  RecipeDetectorIntegration.swift
//  Integration wrapper for Recipe Column Detector
//
//  This file bridges the RecipeColumnDetector with your existing app
//

import SwiftUI
import Vision
import Combine

// MARK: - Main Integration View
/// Use this view to test the recipe detector with your existing images
struct RecipeDetectorTestingView: View {
    @StateObject private var viewModel = RecipeDetectorTestViewModel()
    @State private var showImagePicker = false
    @State private var showAssetSelector = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Image Display
                    imageDisplaySection
                    
                    // Control Buttons
                    controlButtonsSection
                    
                    // Progress Indicator
                    if viewModel.isAnalyzing {
                        ProgressView("Analyzing recipe columns...")
                            .padding()
                    }
                    
                    // Results Display
                    resultsSection
                    
                    // Error Display
                    if let error = viewModel.errorMessage {
                        errorDisplaySection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Recipe Detector Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showAssetSelector = true }) {
                            Label("Load Test Image", systemImage: "photo.stack")
                        }
                        Button(action: { showImagePicker = true }) {
                            Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        }
                        Button(action: { viewModel.clearResults() }) {
                            Label("Clear", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                RecipeImagePicker(image: $viewModel.selectedImage, sourceType: .photoLibrary)
            }
            .sheet(isPresented: $showAssetSelector) {
                AssetImageSelectorView(selectedImage: $viewModel.selectedImage)
            }
        }
    }
    
    // MARK: - View Components
    
    private var imageDisplaySection: some View {
        Group {
            if let displayImage = viewModel.displayImage {
                VStack(spacing: 12) {
                    Image(uiImage: displayImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                    
                    // Image info
                    if let image = viewModel.selectedImage {
                        Text("Size: \(Int(image.size.width)) × \(Int(image.size.height)) px")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                placeholderView
            }
        }
    }
    
    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Image Selected")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Tap the menu (⋯) to load a test image")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var controlButtonsSection: some View {
        VStack(spacing: 12) {
            // Main analyze button
            if viewModel.selectedImage != nil {
                Button(action: {
                    viewModel.analyzeCurrentImage()
                }) {
                    HStack {
                        if viewModel.isAnalyzing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Analyzing...")
                        } else {
                            Label("Analyze Recipe Columns", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isAnalyzing)
                
                // Debug toggle (only show if analysis completed)
                if viewModel.debugImage != nil {
                    HStack(spacing: 15) {
                        Button(action: {
                            viewModel.toggleDebugView()
                        }) {
                            Label(
                                viewModel.showingDebug ? "Show Original" : "Show Debug Overlay",
                                systemImage: viewModel.showingDebug ? "eye.slash" : "eye"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        // Export debug image
                        if let debugImage = viewModel.debugImage {
                            ShareLink(item: Image(uiImage: debugImage), preview: SharePreview("Debug Image")) {
                                Label("Share Debug", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }
    
    private var resultsSection: some View {
        Group {
            if let resultText = viewModel.resultText {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Analysis Results")
                        .font(.headline)
                    
                    Text(resultText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    
                    // Quick stats
                    if let analysis = viewModel.currentAnalysis {
                        quickStatsView(analysis)
                    }
                }
            }
        }
    }
    
    private func quickStatsView(_ analysis: RecipeAnalysis) -> some View {
        VStack(spacing: 8) {
            HStack {
                StatBadge(
                    icon: "line.3.horizontal",
                    value: "\(analysis.ingredientRows.count)",
                    label: "Rows",
                    color: .blue
                )
                
                StatBadge(
                    icon: analysis.columnLayout.verticalDividerX != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    value: analysis.columnLayout.verticalDividerX != nil ? "Yes" : "No",
                    label: "Divider",
                    color: analysis.columnLayout.verticalDividerX != nil ? .green : .orange
                )
                
                if let dividerX = analysis.columnLayout.verticalDividerX {
                    StatBadge(
                        icon: "arrow.left.and.right",
                        value: String(format: "%.1f%%", dividerX * 100),
                        label: "Position",
                        color: .purple
                    )
                }
            }
        }
    }
    
    private func errorDisplaySection(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(error)
                .font(.callout)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Stat Badge Component
struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - View Model
@MainActor
class RecipeDetectorTestViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var displayImage: UIImage?
    @Published var debugImage: UIImage?
    @Published var resultText: String?
    @Published var errorMessage: String?
    @Published var isAnalyzing = false
    @Published var showingDebug = false
    @Published var currentAnalysis: RecipeAnalysis?
    
    private let detector = RecipeColumnDetector()
    
    func analyzeCurrentImage() {
        guard let image = selectedImage else {
            errorMessage = "No image selected"
            return
        }
        
        // Reset state
        displayImage = image
        isAnalyzing = true
        errorMessage = nil
        resultText = nil
        debugImage = nil
        showingDebug = false
        currentAnalysis = nil
        
        // Run detection using Task
        Task {
            let result = await performAnalysis(image: image)
            
            // Back on MainActor automatically
            self.isAnalyzing = false
            self.handleAnalysisResult(result, originalImage: image)
        }
    }
    
    // Perform analysis (stays on main actor since detector requires it)
    private func performAnalysis(image: UIImage) async -> Result<RecipeAnalysis, Error> {
        await withCheckedContinuation { continuation in
            detector.analyzeRecipeCard(image: image) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    private func handleAnalysisResult(_ result: Result<RecipeAnalysis, Error>, originalImage: UIImage) {
        switch result {
        case .success(let analysis):
            currentAnalysis = analysis
            resultText = formatAnalysis(analysis)
            
            // Generate debug visualization
            debugImage = detector.generateDebugVisualization(
                originalImage: originalImage,
                analysis: analysis,
                options: .default
            )
            
        case .failure(let error):
            errorMessage = "Analysis failed: \(error.localizedDescription)"
        }
    }
    
    func toggleDebugView() {
        showingDebug.toggle()
        
        if showingDebug, let debug = debugImage {
            displayImage = debug
        } else if let original = selectedImage {
            displayImage = original
        }
    }
    
    func clearResults() {
        selectedImage = nil
        displayImage = nil
        debugImage = nil
        resultText = nil
        errorMessage = nil
        currentAnalysis = nil
        showingDebug = false
    }
    
    private func formatAnalysis(_ analysis: RecipeAnalysis) -> String {
        var text = "📊 ANALYSIS RESULTS\n"
        text += String(repeating: "=", count: 50) + "\n\n"
        
        // Image info
        text += "📐 Image Size: \(Int(analysis.imageSize.width)) × \(Int(analysis.imageSize.height))\n"
        
        // Upscaling info
        if analysis.wasUpscaled, let originalSize = analysis.originalImageSize {
            text += "⚠️ Image was upscaled from \(Int(originalSize.width)) × \(Int(originalSize.height))\n"
            text += "   (Original was too small for optimal detection)\n"
        }
        text += "\n"
        
        // Divider detection
        text += "🔍 COLUMN DETECTION:\n"
        if let dividerX = analysis.columnLayout.verticalDividerX {
            let pixelX = Int(dividerX * analysis.imageSize.width)
            text += "✅ Vertical divider found at x=\(String(format: "%.3f", dividerX)) (\(pixelX)px)\n"
            
            // Quality assessment
            if dividerX >= 0.30 && dividerX <= 0.45 {
                text += "   ✓ Position looks good (0.30-0.45 range)\n"
            } else {
                text += "   ⚠️  Position outside typical range (0.30-0.45)\n"
            }
        } else {
            text += "⚠️  No divider detected - using heuristic fallback\n"
        }
        text += "\n"
        
        // Row count
        text += "📝 INGREDIENT ROWS: \(analysis.ingredientRows.count)\n\n"
        
        // Row details
        text += "📋 ROW BREAKDOWN:\n"
        for (i, row) in analysis.ingredientRows.enumerated() {
            let leftCount = row.leftColumnBlocks.count
            let rightCount = row.rightColumnBlocks.count
            let leftText = row.leftColumnBlocks.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            let rightText = row.rightColumnBlocks.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            
            text += "Row \(i+1): L=\(leftCount) R=\(rightCount)\n"
            if !leftText.isEmpty {
                text += "  Left: \(leftText)\n"
            }
            if !rightText.isEmpty {
                text += "  Right: \(rightText)\n"
            }
            text += "\n"
        }
        
        // Sections
        if !analysis.sections.isEmpty {
            text += "📑 SECTIONS DETECTED: \(analysis.sections.count)\n"
            for (i, section) in analysis.sections.enumerated() {
                text += "  \(i+1). \(section.type) (y=\(String(format: "%.3f", section.boundingBox.minY)))\n"
            }
        }
        
        return text
    }
}

// MARK: - Asset Image Selector
/// Helper view to select images from Assets catalog
struct AssetImageSelectorView: View {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    // Add your test image names here
    private let testImageNames = [
        "AmNC", "CaPi", "Mpio", "LaYS", "CoCh", "CuRa", "DhCh",
        "GrCu", "KhCh", "LiCh", "MaCh", "PaCh", "ToCh"
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                    ForEach(testImageNames, id: \.self) { imageName in
                        if let image = UIImage(named: imageName) {
                            Button(action: {
                                selectedImage = image
                                dismiss()
                            }) {
                                VStack {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 150)
                                        .cornerRadius(8)
                                    
                                    Text(imageName)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Select Test Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    RecipeDetectorTestingView()
}
