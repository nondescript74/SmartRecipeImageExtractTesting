import SwiftUI
import Combine
import Vision

// MARK: - Complete Test Implementation
// Drop this into your Xcode project and run it!

struct RecipeDetectorTestApp: View {
    @StateObject private var viewModel = RecipeDetectorViewModel()
    
    var body: some View {
        NavigationView {
            VStack {
                ImageCollectionView()
            }
            VStack {
                // Image display
                if let displayImage = viewModel.displayImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                        .cornerRadius(8)
                        .padding()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 400)
                        .overlay(
                            Text("No image loaded")
                                .foregroundColor(.secondary)
                        )
                        .cornerRadius(8)
                        .padding()
                }
                
                // Control buttons
                HStack(spacing: 20) {
                    Button("Load & Analyze") {
                        viewModel.loadAndAnalyze()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isAnalyzing)
                    
                    if viewModel.debugImage != nil {
                        Button("Toggle Debug") {
                            viewModel.toggleDebugView()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                
                // Progress indicator
                if viewModel.isAnalyzing {
                    ProgressView("Analyzing recipe...")
                        .padding()
                }
                
                // Results
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let result = viewModel.resultText {
                            Text(result)
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .textSelection(.enabled)
                        }
                        
                        if let error = viewModel.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                Text(error)
                            }
                            .foregroundColor(.red)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Recipe Detector Test App")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - View Model

class RecipeDetectorViewModel: ObservableObject {
    @Published var displayImage: UIImage?
    @Published var debugImage: UIImage?
    @Published var resultText: String?
    @Published var errorMessage: String?
    @Published var isAnalyzing = false
    
    private var originalImage: UIImage?
    private var currentAnalysis: RecipeAnalysis?
    private var showingDebug = false
    
    private let detector = RecipeColumnDetector()
    
    // List of test images to cycle through
    private let testImages = ["AmNC", "CaPi", "Mpio", "LaYS", "CoCh", "CuRa", "DhCh", "DrCa", "VeSo", "KaSM", "LeCh", "EgRa", "GaMa", "GhCb", "Sher", "HoYo", "Kach", "Vs", "Itc"]
    private var currentImageIndex = 0
    
    func loadAndAnalyze() {
        // Load test image
        guard let image = loadTestImage() else {
            errorMessage = "Could not load test image. Make sure images are in Assets."
            return
        }
        
        originalImage = image
        displayImage = image
        isAnalyzing = true
        errorMessage = nil
        resultText = nil
        debugImage = nil
        showingDebug = false
        
        // Analyze
        detector.analyzeRecipeCard(image: image) { [weak self] result in
            DispatchQueue.main.async {
                self?.isAnalyzing = false
                self?.handleAnalysisResult(result)
            }
        }
    }
    
    private func loadTestImage() -> UIImage? {
        // Try to load the current test image
        let imageName = testImages[currentImageIndex]
        
        if let image = UIImage(named: imageName) {
            print("✅ Loaded image: \(imageName)")
            // Cycle to next image for next load
            currentImageIndex = (currentImageIndex + 1) % testImages.count
            return image
        }
        
        print("⚠️  Could not load image: \(imageName)")
        
        // Try next image
        for i in 0..<testImages.count {
            let tryName = testImages[i]
            if let image = UIImage(named: tryName) {
                print("✅ Loaded image: \(tryName)")
                currentImageIndex = (i + 1) % testImages.count
                return image
            }
        }
        
        return nil
    }
    
    private func handleAnalysisResult(_ result: Result<RecipeAnalysis, Error>) {
        switch result {
        case .success(let analysis):
            currentAnalysis = analysis
            resultText = formatAnalysis(analysis)
            
            // Generate debug visualization
            if let original = originalImage {
                debugImage = detector.generateDebugVisualization(
                    originalImage: original,
                    analysis: analysis,
                    options: .default
                )
            }
            
        case .failure(let error):
            errorMessage = "Analysis failed: \(error.localizedDescription)"
        }
    }
    
    func toggleDebugView() {
        showingDebug.toggle()
        
        if showingDebug, let debug = debugImage {
            displayImage = debug
        } else if let original = originalImage {
            displayImage = original
        }
    }
    
    private func formatAnalysis(_ analysis: RecipeAnalysis) -> String {
        var text = "📊 ANALYSIS RESULTS\n"
        text += String(repeating: "=", count: 50) + "\n\n"
        
        // Image info
        text += "📐 Image Size: \(Int(analysis.imageSize.width)) x \(Int(analysis.imageSize.height))\n\n"
        
        // Divider detection
        text += "🔍 COLUMN DETECTION:\n"
        if let dividerX = analysis.columnLayout.verticalDividerX {
            let pixelX = Int(dividerX * analysis.imageSize.width)
            text += "✅ Vertical divider found\n"
            text += "   Position: \(String(format: "%.3f", dividerX)) (\(pixelX)px)\n"
        } else {
            text += "⚠️  No vertical divider detected\n"
            text += "   Using heuristic column split\n"
        }
        text += "\n"
        
        // Sections
        text += "📑 SECTIONS DETECTED: \(analysis.sections.count)\n"
        for section in analysis.sections {
            let emoji = sectionEmoji(for: section.type)
            text += "\(emoji) \(section.type)\n"
            text += "   Text blocks: \(section.textObservations.count)\n"
            text += "   Y-range: \(String(format: "%.3f", section.boundingBox.minY))"
            text += " to \(String(format: "%.3f", section.boundingBox.maxY))\n"
        }
        text += "\n"
        
        // Ingredient rows
        text += "🥘 INGREDIENT ROWS: \(analysis.ingredientRows.count)\n"
        text += String(repeating: "-", count: 50) + "\n"
        
        if analysis.ingredientRows.isEmpty {
            text += "⚠️  No ingredient rows detected\n"
            text += "This may indicate an issue with section detection.\n"
        } else {
            // Statistics
            let withBoth = analysis.ingredientRows.filter { 
                !$0.leftColumnBlocks.isEmpty && !$0.rightColumnBlocks.isEmpty 
            }.count
            let leftOnly = analysis.ingredientRows.filter { 
                !$0.leftColumnBlocks.isEmpty && $0.rightColumnBlocks.isEmpty 
            }.count
            let rightOnly = analysis.ingredientRows.filter { 
                $0.leftColumnBlocks.isEmpty && !$0.rightColumnBlocks.isEmpty 
            }.count
            
            text += "Statistics:\n"
            text += "  • Both columns: \(withBoth)\n"
            text += "  • Left only: \(leftOnly)\n"
            text += "  • Right only: \(rightOnly)\n\n"
            
            // Show first 8 rows in detail
            let showCount = min(8, analysis.ingredientRows.count)
            text += "First \(showCount) rows:\n"
            text += String(repeating: "-", count: 50) + "\n"
            
            for (index, row) in analysis.ingredientRows.prefix(showCount).enumerated() {
                text += "\nRow \(index + 1):\n"
                text += "  Position: y=\(String(format: "%.3f", row.yPosition))\n"
                text += "  Height: \(String(format: "%.4f", row.height))\n"
                
                // Left column
                text += "  📗 Left (\(row.leftColumnBlocks.count) blocks):\n"
                let leftTexts = row.leftColumnBlocks.compactMap { 
                    $0.topCandidates(1).first?.string 
                }
                if leftTexts.isEmpty {
                    text += "     (empty)\n"
                } else {
                    text += "     \(leftTexts.joined(separator: " "))\n"
                }
                
                // Right column
                text += "  📘 Right (\(row.rightColumnBlocks.count) blocks):\n"
                let rightTexts = row.rightColumnBlocks.compactMap { 
                    $0.topCandidates(1).first?.string 
                }
                if rightTexts.isEmpty {
                    text += "     (empty)\n"
                } else {
                    text += "     \(rightTexts.joined(separator: " "))\n"
                }
            }
            
            if analysis.ingredientRows.count > showCount {
                text += "\n... and \(analysis.ingredientRows.count - showCount) more rows\n"
            }
        }
        
        // Validation warnings
        text += "\n" + String(repeating: "=", count: 50) + "\n"
        text += "🔍 VALIDATION:\n"
        
        var warnings: [String] = []
        
        if analysis.columnLayout.verticalDividerX == nil {
            warnings.append("No vertical divider detected")
        }
        
        if analysis.ingredientRows.count < 3 {
            warnings.append("Few rows detected (expected 5+)")
        }
        
        let withBoth = analysis.ingredientRows.filter { 
            !$0.leftColumnBlocks.isEmpty && !$0.rightColumnBlocks.isEmpty 
        }.count
        if Double(withBoth) < Double(analysis.ingredientRows.count) * 0.5 {
            warnings.append("Less than half of rows have both columns")
        }
        
        if warnings.isEmpty {
            text += "✅ No issues detected\n"
        } else {
            text += "⚠️  Warnings:\n"
            for warning in warnings {
                text += "   • \(warning)\n"
            }
        }
        
        return text
    }
    
    private func sectionEmoji(for type: RecipeSection.SectionType) -> String {
        switch type {
        case .title: return "📌"
        case .metadata: return "ℹ️"
        case .ingredients: return "🥕"
        case .instructions: return "📝"
        case .variations: return "🔄"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct RecipeDetectorTestApp_Previews: PreviewProvider {
    static var previews: some View {
        RecipeDetectorTestApp()
    }
}
#endif

// MARK: - Quick Test Function
// Use this in your existing view controller if you prefer UIKit

func quickTest_RecipeDetector() {
    guard let testImage = UIImage(named: "AmNC") else {
        print("❌ Test image not found")
        return
    }
    
    print("\n🧪 Running quick test...")
    
    let detector = RecipeColumnDetector()
    detector.analyzeRecipeCard(image: testImage) { result in
        DispatchQueue.main.async {
            switch result {
            case .success(let analysis):
                print("\n✅ Analysis successful!")
                print("Found \(analysis.ingredientRows.count) ingredient rows")
                
                if let dividerX = analysis.columnLayout.verticalDividerX {
                    print("Divider at x=\(String(format: "%.3f", dividerX))")
                }
                
                // Print first 3 rows
                for (index, row) in analysis.ingredientRows.prefix(3).enumerated() {
                    print("\nRow \(index + 1):")
                    
                    let leftTexts = row.leftColumnBlocks.compactMap { 
                        $0.topCandidates(1).first?.string 
                    }
                    print("  Left: \(leftTexts.joined(separator: " "))")
                    
                    let rightTexts = row.rightColumnBlocks.compactMap { 
                        $0.topCandidates(1).first?.string 
                    }
                    print("  Right: \(rightTexts.joined(separator: " "))")
                }
                
            case .failure(let error):
                print("❌ Error: \(error)")
            }
        }
    }
}
