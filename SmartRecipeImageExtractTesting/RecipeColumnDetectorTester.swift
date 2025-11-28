import UIKit
import Vision

// MARK: - Test Harness for RecipeColumnDetector

class RecipeColumnDetectorTester {
    
    let detector = RecipeColumnDetector()
    
    // MARK: - Test with Image
    
    func testWithImage(_ image: UIImage, imageName: String) {
        print("\n" + String(repeating: "=", count: 80))
        print("Testing: \(imageName)")
        print(String(repeating: "=", count: 80))
        
        detector.analyzeRecipeCard(image: image) { result in
            switch result {
            case .success(let analysis):
                Task { @MainActor in
                    self.printAnalysisReport(analysis, imageName: imageName)
                }
                
            case .failure(let error):
                print("❌ Error analyzing \(imageName): \(error)")
            }
        }
    }
    
    // MARK: - Detailed Report
    
    private func printAnalysisReport(_ analysis: RecipeAnalysis, imageName: String) {
        print("\n📊 Analysis Report for \(imageName)")
        print(String(repeating: "-", count: 80))
        
        // Image info
        print("\n📐 Image Size: \(analysis.imageSize.width) x \(analysis.imageSize.height)")
        
        // Vertical divider info
        if let dividerX = analysis.columnLayout.verticalDividerX {
            let pixelX = dividerX * analysis.imageSize.width
            print("📍 Vertical Divider Found: x = \(String(format: "%.3f", dividerX)) (\(Int(pixelX))px)")
        } else {
            print("⚠️  No vertical divider detected - using heuristic split")
        }
        
        // Sections info
        print("\n📑 Sections Detected: \(analysis.sections.count)")
        for section in analysis.sections {
            let typeEmoji: String
            switch section.type {
            case .title: typeEmoji = "📌"
            case .metadata: typeEmoji = "ℹ️"
            case .ingredients: typeEmoji = "🥕"
            case .instructions: typeEmoji = "📝"
            case .variations: typeEmoji = "🔄"
            }
            
            print("  \(typeEmoji) \(section.type): \(section.textObservations.count) text blocks")
            print("     Bounds: y=\(String(format: "%.3f", section.boundingBox.minY)) to \(String(format: "%.3f", section.boundingBox.maxY))")
        }
        
        // Ingredient rows
        print("\n🥘 Ingredient Rows: \(analysis.ingredientRows.count)")
        
        if analysis.ingredientRows.isEmpty {
            print("  ⚠️  No ingredient rows detected!")
            return
        }
        
        for (index, row) in analysis.ingredientRows.enumerated() {
            print("\n  Row \(index + 1):")
            print("    Position: y=\(String(format: "%.3f", row.yPosition)), height=\(String(format: "%.3f", row.height))")
            print("    Left column: \(row.leftColumnBlocks.count) blocks")
            print("    Right column: \(row.rightColumnBlocks.count) blocks")
            
            // Extract and print text from left column
            let leftTexts = row.leftColumnBlocks.compactMap { block -> String? in
                block.topCandidates(1).first?.string
            }
            if !leftTexts.isEmpty {
                print("    📝 Left text: \(leftTexts.joined(separator: " "))")
            }
            
            // Extract and print text from right column
            let rightTexts = row.rightColumnBlocks.compactMap { block -> String? in
                block.topCandidates(1).first?.string
            }
            if !rightTexts.isEmpty {
                print("    📝 Right text: \(rightTexts.joined(separator: " "))")
            }
            
            // Show bounding box details
            if !row.leftColumnBlocks.isEmpty {
                let leftMostX = row.leftColumnBlocks.map { $0.boundingBox.minX }.min() ?? 0
                let rightMostX = row.leftColumnBlocks.map { $0.boundingBox.maxX }.max() ?? 0
                print("    📏 Left column span: x=\(String(format: "%.3f", leftMostX)) to \(String(format: "%.3f", rightMostX))")
            }
            
            if !row.rightColumnBlocks.isEmpty {
                let leftMostX = row.rightColumnBlocks.map { $0.boundingBox.minX }.min() ?? 0
                let rightMostX = row.rightColumnBlocks.map { $0.boundingBox.maxX }.max() ?? 0
                print("    📏 Right column span: x=\(String(format: "%.3f", leftMostX)) to \(String(format: "%.3f", rightMostX))")
            }
        }
        
        // Summary statistics
        print("\n📈 Summary Statistics:")
        let rowsWithBothColumns = analysis.ingredientRows.filter { !$0.leftColumnBlocks.isEmpty && !$0.rightColumnBlocks.isEmpty }.count
        let rowsWithLeftOnly = analysis.ingredientRows.filter { !$0.leftColumnBlocks.isEmpty && $0.rightColumnBlocks.isEmpty }.count
        let rowsWithRightOnly = analysis.ingredientRows.filter { $0.leftColumnBlocks.isEmpty && !$0.rightColumnBlocks.isEmpty }.count
        
        print("  ✅ Rows with both columns: \(rowsWithBothColumns)")
        print("  ⚠️  Rows with left only: \(rowsWithLeftOnly)")
        print("  ⚠️  Rows with right only: \(rowsWithRightOnly)")
        
        // Validation checks
        print("\n🔍 Validation:")
        if analysis.columnLayout.verticalDividerX == nil {
            print("  ⚠️  Warning: No vertical divider detected")
        }
        
        if analysis.ingredientRows.count < 3 {
            print("  ⚠️  Warning: Few ingredient rows detected (expected more for typical recipe)")
        }
        
        if rowsWithBothColumns < analysis.ingredientRows.count / 2 {
            print("  ⚠️  Warning: Less than half of rows have both columns populated")
        }
        
        let avgBlocksPerRow = Double(analysis.ingredientRows.reduce(0) { $0 + $1.leftColumnBlocks.count + $1.rightColumnBlocks.count }) / Double(analysis.ingredientRows.count)
        print("  📊 Average text blocks per row: \(String(format: "%.1f", avgBlocksPerRow))")
    }
    
    // MARK: - Visual Debug Output
    
    func generateDebugImage(_ image: UIImage, analysis: RecipeAnalysis) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        
        return renderer.image { context in
            // Draw original image
            image.draw(at: .zero)
            
            let ctx = context.cgContext
            let imageHeight = image.size.height
            
            // Helper to convert normalized Vision coordinates to UIKit coordinates
            func convertY(_ normalizedY: CGFloat) -> CGFloat {
                return imageHeight * (1.0 - normalizedY)
            }
            
            func convertRect(_ normalizedRect: CGRect) -> CGRect {
                return CGRect(
                    x: normalizedRect.minX * image.size.width,
                    y: convertY(normalizedRect.maxY),
                    width: normalizedRect.width * image.size.width,
                    height: normalizedRect.height * image.size.height
                )
            }
            
            // Draw vertical divider
            if let dividerX = analysis.columnLayout.verticalDividerX {
                ctx.setStrokeColor(UIColor.red.cgColor)
                ctx.setLineWidth(3.0)
                let x = dividerX * image.size.width
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: image.size.height))
                ctx.strokePath()
            }
            
            // Draw ingredient rows
            for (index, row) in analysis.ingredientRows.enumerated() {
                // Alternate colors for rows
                let color = index % 2 == 0 ? UIColor.green.withAlphaComponent(0.2) : UIColor.blue.withAlphaComponent(0.2)
                
                // Draw left column blocks
                for block in row.leftColumnBlocks {
                    let rect = convertRect(block.boundingBox)
                    ctx.setFillColor(color.cgColor)
                    ctx.fill(rect)
                    ctx.setStrokeColor(UIColor.green.cgColor)
                    ctx.setLineWidth(2.0)
                    ctx.stroke(rect)
                }
                
                // Draw right column blocks
                for block in row.rightColumnBlocks {
                    let rect = convertRect(block.boundingBox)
                    ctx.setFillColor(color.cgColor)
                    ctx.fill(rect)
                    ctx.setStrokeColor(UIColor.blue.cgColor)
                    ctx.setLineWidth(2.0)
                    ctx.stroke(rect)
                }
                
                // Draw row number
                let rowY = convertY(row.yPosition + row.height / 2)
                let numberRect = CGRect(x: 5, y: rowY - 15, width: 30, height: 30)
                
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(numberRect)
                ctx.setStrokeColor(UIColor.black.cgColor)
                ctx.setLineWidth(1.0)
                ctx.stroke(numberRect)
                
                let text = "\(index + 1)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 16),
                    .foregroundColor: UIColor.black
                ]
                text.draw(in: numberRect, withAttributes: attrs)
            }
        }
    }
    
    // MARK: - Batch Testing
    
    func testAllImages(_ images: [(image: UIImage, name: String)]) {
        print("\n🧪 Testing \(images.count) recipe images...")
        print(String(repeating: "=", count: 80))
        
        let group = DispatchGroup()
        
        for (image, name) in images {
            group.enter()
            testWithImage(image, imageName: name)
            
            // Wait a bit to let async processing complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            print("\n✅ Testing complete!")
        }
    }
}

// MARK: - Example Usage in View Controller

extension RecipeColumnDetectorTester {
    
    static func runTests(with testImages: [UIImage], names: [String]) {
        let tester = RecipeColumnDetectorTester()
        
        let imagesWithNames = zip(testImages, names).map { (image: $0, name: $1) }
        tester.testAllImages(imagesWithNames)
    }
    
    static func runSingleTest(with image: UIImage, name: String, completion: @escaping @Sendable (RecipeAnalysis?, UIImage?) -> Void) {
        let tester = RecipeColumnDetectorTester()
        
        tester.detector.analyzeRecipeCard(image: image) { result in
            switch result {
            case .success(let analysis):
                // Both printAnalysisReport and generateDebugImage need to be on main actor
                Task { @MainActor in
                    tester.printAnalysisReport(analysis, imageName: name)
                    let debugImage = tester.generateDebugImage(image, analysis: analysis)
                    completion(analysis, debugImage)
                }
                
            case .failure(let error):
                print("❌ Error: \(error)")
                completion(nil, nil)
            }
        }
    }
}

// MARK: - SwiftUI Preview Helper

#if DEBUG
import SwiftUI

struct RecipeDetectorTestView: View {
    @State private var testImage: UIImage?
    @State private var debugImage: UIImage?
    @State private var analysisResult: RecipeAnalysis?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Recipe Column Detector Test")
                    .font(.title)
                    .bold()
                
                if let image = testImage {
                    VStack {
                        Text("Original Image")
                            .font(.headline)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                    }
                }
                
                Button("Test with Sample Image") {
                    testSampleImage()
                }
                .buttonStyle(.borderedProminent)
                
                if let debugImage = debugImage {
                    VStack {
                        Text("Debug Visualization")
                            .font(.headline)
                        Text("Green = Left Column, Blue = Right Column, Red = Divider")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(uiImage: debugImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 400)
                    }
                }
                
                if let analysis = analysisResult {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Results")
                            .font(.headline)
                        
                        Text("Ingredient Rows: \(analysis.ingredientRows.count)")
                        
                        if let dividerX = analysis.columnLayout.verticalDividerX {
                            Text("Divider at: \(String(format: "%.3f", dividerX))")
                        } else {
                            Text("No divider detected")
                                .foregroundColor(.orange)
                        }
                        
                        ForEach(0..<min(5, analysis.ingredientRows.count), id: \.self) { index in
                            let row = analysis.ingredientRows[index]
                            VStack(alignment: .leading) {
                                Text("Row \(index + 1)")
                                    .font(.subheadline)
                                    .bold()
                                Text("Left: \(row.leftColumnBlocks.count) blocks, Right: \(row.rightColumnBlocks.count) blocks")
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }
    
    private func testSampleImage() {
        // Replace with your actual test image
        guard let image = UIImage(named: "AmNC") else {
            print("⚠️ Test image not found")
            return
        }
        
        testImage = image
        
        RecipeColumnDetectorTester.runSingleTest(with: image, name: "AmNC") { analysis, debug in
            DispatchQueue.main.async {
                self.analysisResult = analysis
                self.debugImage = debug
            }
        }
    }
}

struct RecipeDetectorTestView_Previews: PreviewProvider {
    static var previews: some View {
        RecipeDetectorTestView()
    }
}
#endif
