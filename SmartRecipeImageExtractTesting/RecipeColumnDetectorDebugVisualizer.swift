import UIKit
import Vision

// MARK: - Visual Debug Overlay Generator

extension RecipeColumnDetector {
    
    /// Generates a debug image with visual overlays showing detection results
    func generateDebugVisualization(
        originalImage: UIImage,
        analysis: RecipeAnalysis,
        options: DebugVisualizationOptions = .default
    ) -> UIImage? {
        
        guard originalImage.cgImage != nil else { return nil }
        
        let imageSize = originalImage.size
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        
        return renderer.image { context in
            // Draw original image
            originalImage.draw(at: .zero)
            
            let ctx = context.cgContext
            let height = imageSize.height
            
            // Helper to convert Vision coordinates (bottom-left origin) to UIKit (top-left origin)
            func convertY(_ normalizedY: CGFloat) -> CGFloat {
                return height * (1.0 - normalizedY)
            }
            
            func convertRect(_ normalizedRect: CGRect) -> CGRect {
                return CGRect(
                    x: normalizedRect.minX * imageSize.width,
                    y: convertY(normalizedRect.maxY),
                    width: normalizedRect.width * imageSize.width,
                    height: normalizedRect.height * imageSize.height
                )
            }
            
            // 1. Draw vertical divider line
            if options.showVerticalDivider, let dividerX = analysis.columnLayout.verticalDividerX {
                ctx.setStrokeColor(UIColor.red.cgColor)
                ctx.setLineWidth(3.0)
                ctx.setLineDash(phase: 0, lengths: [10, 5]) // Dashed line
                
                let x = dividerX * imageSize.width
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: height))
                ctx.strokePath()
                
                // Add label
                if options.showLabels {
                    let label = "Divider: \(String(format: "%.3f", dividerX))"
                    drawLabel(label, at: CGPoint(x: x + 5, y: 20), color: .red, ctx: ctx)
                }
            }
            
            // 2. Draw section boundaries
            if options.showSections {
                for section in analysis.sections {
                    let color: UIColor
                    let label: String
                    
                    switch section.type {
                    case .title:
                        color = .systemPurple
                        label = "TITLE"
                    case .metadata:
                        color = .systemBlue
                        label = "METADATA"
                    case .ingredients:
                        color = .systemGreen
                        label = "INGREDIENTS"
                    case .instructions:
                        color = .systemOrange
                        label = "INSTRUCTIONS"
                    case .variations:
                        color = .systemYellow
                        label = "VARIATIONS"
                    }
                    
                    let rect = convertRect(section.boundingBox)
                    
                    ctx.setStrokeColor(color.withAlphaComponent(0.6).cgColor)
                    ctx.setLineWidth(2.0)
                    ctx.stroke(rect)
                    
                    if options.showLabels {
                        drawLabel(label, at: CGPoint(x: rect.minX + 5, y: rect.minY + 5), color: color, ctx: ctx)
                    }
                }
            }
            
            // 3. Draw ingredient rows
            if options.showIngredientRows {
                for (index, row) in analysis.ingredientRows.enumerated() {
                    let rowColor = index % 2 == 0 ? UIColor.systemTeal : UIColor.systemCyan
                    let alpha: CGFloat = 0.15
                    
                    // Draw row background
                    let rowY = convertY(row.yPosition + row.height)
                    let rowHeight = row.height * height
                    let rowRect = CGRect(x: 0, y: rowY, width: imageSize.width, height: rowHeight)
                    
                    ctx.setFillColor(rowColor.withAlphaComponent(alpha).cgColor)
                    ctx.fill(rowRect)
                    
                    // Draw row border
                    ctx.setStrokeColor(rowColor.withAlphaComponent(0.5).cgColor)
                    ctx.setLineWidth(1.0)
                    ctx.stroke(rowRect)
                    
                    // Draw row number
                    let numberLabel = "\(index + 1)"
                    let numberPoint = CGPoint(x: 8, y: rowY + rowHeight / 2 - 10)
                    drawRowNumber(numberLabel, at: numberPoint, color: rowColor, ctx: ctx)
                }
            }
            
            // 4. Draw text blocks with column highlighting
            if options.showTextBlocks {
                for (_, row) in analysis.ingredientRows.enumerated() {
                    // Left column blocks (green)
                    for block in row.leftColumnBlocks {
                        let rect = convertRect(block.boundingBox)
                        
                        ctx.setStrokeColor(UIColor.systemGreen.cgColor)
                        ctx.setLineWidth(2.0)
                        ctx.stroke(rect)
                        
                        if options.showTextContent {
                            if let text = block.topCandidates(1).first?.string {
                                drawTextLabel(text, in: rect, color: .systemGreen, ctx: ctx)
                            }
                        }
                    }
                    
                    // Right column blocks (blue)
                    for block in row.rightColumnBlocks {
                        let rect = convertRect(block.boundingBox)
                        
                        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
                        ctx.setLineWidth(2.0)
                        ctx.stroke(rect)
                        
                        if options.showTextContent {
                            if let text = block.topCandidates(1).first?.string {
                                drawTextLabel(text, in: rect, color: .systemBlue, ctx: ctx)
                            }
                        }
                    }
                }
            }
            
            // 5. Draw legend
            if options.showLegend {
                drawLegend(at: CGPoint(x: 10, y: height - 120), ctx: ctx)
            }
            
            // Helper functions
            func drawLabel(_ text: String, at point: CGPoint, color: UIColor, ctx: CGContext) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: UIColor.white,
                    .backgroundColor: color.withAlphaComponent(0.8)
                ]
                
                let nsString = text as NSString
                let size = nsString.size(withAttributes: attrs)
                let rect = CGRect(origin: point, size: size).insetBy(dx: -4, dy: -2)
                
                ctx.setFillColor(color.withAlphaComponent(0.8).cgColor)
                ctx.fill(rect)
                
                nsString.draw(at: CGPoint(x: point.x, y: point.y), withAttributes: attrs)
            }
            
            func drawRowNumber(_ text: String, at point: CGPoint, color: UIColor, ctx: CGContext) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 16),
                    .foregroundColor: UIColor.white
                ]
                
                let size = CGSize(width: 24, height: 24)
                let rect = CGRect(origin: point, size: size)
                
                // Circle background
                ctx.setFillColor(color.cgColor)
                ctx.fillEllipse(in: rect)
                
                ctx.setStrokeColor(UIColor.white.cgColor)
                ctx.setLineWidth(2.0)
                ctx.strokeEllipse(in: rect)
                
                // Center text
                let nsString = text as NSString
                let textSize = nsString.size(withAttributes: attrs)
                let textPoint = CGPoint(
                    x: rect.midX - textSize.width / 2,
                    y: rect.midY - textSize.height / 2
                )
                
                nsString.draw(at: textPoint, withAttributes: attrs)
            }
            
            func drawTextLabel(_ text: String, in rect: CGRect, color: UIColor, ctx: CGContext) {
                let truncated = text.count > 20 ? String(text.prefix(20)) + "..." : text
                
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor.white,
                    .backgroundColor: color.withAlphaComponent(0.9)
                ]
                
                let nsString = truncated as NSString
                let labelRect = CGRect(x: rect.minX, y: rect.maxY + 2, width: rect.width, height: 12)
                
                nsString.draw(in: labelRect, withAttributes: attrs)
            }
            
            func drawLegend(at origin: CGPoint, ctx: CGContext) {
                let legendItems: [(String, UIColor)] = [
                    ("Vertical Divider", .red),
                    ("Left Column", .systemGreen),
                    ("Right Column", .systemBlue),
                    ("Ingredient Rows", .systemTeal)
                ]
                
                var y = origin.y
                
                // Background
                let legendHeight = CGFloat(legendItems.count * 20 + 10)
                let legendRect = CGRect(x: origin.x, y: origin.y, width: 150, height: legendHeight)
                ctx.setFillColor(UIColor.black.withAlphaComponent(0.7).cgColor)
                ctx.fill(legendRect)
                
                for (label, color) in legendItems {
                    // Color box
                    let boxRect = CGRect(x: origin.x + 5, y: y + 5, width: 15, height: 15)
                    ctx.setFillColor(color.cgColor)
                    ctx.fill(boxRect)
                    
                    // Label text
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 12),
                        .foregroundColor: UIColor.white
                    ]
                    
                    let nsString = label as NSString
                    nsString.draw(at: CGPoint(x: origin.x + 25, y: y + 5), withAttributes: attrs)
                    
                    y += 20
                }
            }
        }
    }
}

// MARK: - Visualization Options

struct DebugVisualizationOptions {
    var showVerticalDivider: Bool = true
    var showSections: Bool = true
    var showIngredientRows: Bool = true
    var showTextBlocks: Bool = true
    var showTextContent: Bool = false // Can be noisy
    var showLabels: Bool = true
    var showLegend: Bool = true
    
    static let `default` = DebugVisualizationOptions()
    
    static let minimal = DebugVisualizationOptions(
        showVerticalDivider: true,
        showSections: false,
        showIngredientRows: true,
        showTextBlocks: false,
        showTextContent: false,
        showLabels: false,
        showLegend: false
    )
    
    static let detailed = DebugVisualizationOptions(
        showVerticalDivider: true,
        showSections: true,
        showIngredientRows: true,
        showTextBlocks: true,
        showTextContent: true,
        showLabels: true,
        showLegend: true
    )
}

// MARK: - Usage Examples

/*
 // Example 1: Basic visualization
 detector.analyzeRecipeCard(image: recipeImage) { result in
     switch result {
     case .success(let analysis):
         if let debugImage = detector.generateDebugVisualization(
             originalImage: recipeImage,
             analysis: analysis
         ) {
             imageView.image = debugImage
         }
         
     case .failure(let error):
         print("Error: \(error)")
     }
 }
 
 // Example 2: Minimal visualization (just rows and divider)
 if let debugImage = detector.generateDebugVisualization(
     originalImage: recipeImage,
     analysis: analysis,
     options: .minimal
 ) {
     imageView.image = debugImage
 }
 
 // Example 3: Detailed visualization (everything)
 if let debugImage = detector.generateDebugVisualization(
     originalImage: recipeImage,
     analysis: analysis,
     options: .detailed
 ) {
     imageView.image = debugImage
 }
 
 // Example 4: Custom options
 var customOptions = DebugVisualizationOptions()
 customOptions.showTextContent = true
 customOptions.showSections = false
 
 if let debugImage = detector.generateDebugVisualization(
     originalImage: recipeImage,
     analysis: analysis,
     options: customOptions
 ) {
     imageView.image = debugImage
 }
 */
