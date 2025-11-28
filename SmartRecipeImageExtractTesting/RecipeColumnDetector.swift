import Vision
import UIKit
import CoreImage

// MARK: - Data Models

struct RecipeSection {
    let type: SectionType
    let boundingBox: CGRect
    let textObservations: [VNRecognizedTextObservation]
    
    enum SectionType {
        case title
        case metadata // yield, serving info
        case ingredients
        case instructions
        case variations
    }
}

struct ColumnLayout {
    let verticalDividerX: CGFloat?
    let leftColumnBounds: CGRect
    let rightColumnBounds: CGRect?
    let imageSize: CGSize
    
    // Helper to determine which column a text block belongs to
    func columnForTextBlock(_ observation: VNRecognizedTextObservation) -> Column {
        let normalizedX = observation.boundingBox.midX
        
        if let dividerX = verticalDividerX {
            return normalizedX < dividerX ? .left : .right
        } else {
            // Fallback: if no divider detected, use positional heuristic
            return normalizedX < 0.6 ? .left : .right
        }
    }
    
    enum Column {
        case left
        case right
    }
}

struct IngredientRow: Sendable {
    let yPosition: CGFloat
    let height: CGFloat
    let leftColumnBlocks: [VNRecognizedTextObservation]
    let rightColumnBlocks: [VNRecognizedTextObservation]
    
    var boundingBox: CGRect {
        CGRect(x: 0, y: yPosition, width: 1.0, height: height)
    }
}

// MARK: - Main Detector Class

class RecipeColumnDetector {
    
    // MARK: - Public Interface
    
    func analyzeRecipeCard(image: UIImage) async throws -> RecipeAnalysis {
        guard image.cgImage != nil else {
            throw RecipeError.invalidImage
        }
        
        // Check image size and potentially upscale if too small
        let processedImage = preprocessImageIfNeeded(image)
        guard let processedCGImage = processedImage.cgImage else {
            throw RecipeError.invalidImage
        }
        
        // Step 1: Detect text
        let textObservations = try await detectText(in: processedCGImage)
        
        // Step 2: Detect horizontal lines (section dividers)
        let horizontalLines = (try? await detectHorizontalLines(in: processedCGImage)) ?? []
        
        // Step 3: Detect vertical divider
        let verticalDivider = try? await detectVerticalDivider(in: processedCGImage)
        
        // Step 4: Analyze and segment
        let analysis = analyzeLayout(
            textObservations: textObservations,
            horizontalLines: horizontalLines,
            verticalDivider: verticalDivider,
            imageSize: processedImage.size,
            originalImageSize: image.size
        )
        
        return analysis
    }
    
    // Legacy callback-based API for backwards compatibility
    func analyzeRecipeCard(image: UIImage, completion: @escaping @Sendable (Result<RecipeAnalysis, Error>) -> Void) {
        Task {
            do {
                let analysis = try await analyzeRecipeCard(image: image)
                completion(.success(analysis))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Image Preprocessing
    
    /// Preprocesses image to improve detection quality for small images
    private func preprocessImageIfNeeded(_ image: UIImage) -> UIImage {
        let minRecommendedSize: CGFloat = 1000 // Minimum recommended dimension
        let maxDimension = max(image.size.width, image.size.height)
        
        // If image is too small, upscale it
        if maxDimension < minRecommendedSize {
            let scale = minRecommendedSize / maxDimension
            let newSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            
            print("⚠️ Image too small (\(Int(maxDimension))px). Upscaling to \(Int(max(newSize.width, newSize.height)))px for better detection.")
            
            return upscaleImage(image, to: newSize) ?? image
        }
        
        return image
    }
    
    /// Upscales an image using high-quality interpolation
    private func upscaleImage(_ image: UIImage, to newSize: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        // Use high quality interpolation
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.interpolationQuality = .high
        
        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    // MARK: - Text Detection
    
    private func detectText(in cgImage: CGImage) async throws -> [VNRecognizedTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                
                // Configure for high accuracy
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US"]
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                
                do {
                    try handler.perform([request])
                    
                    guard let observations = request.results else {
                        continuation.resume(throwing: RecipeError.noTextDetected)
                        return
                    }
                    
                    continuation.resume(returning: observations)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Line Detection
    
    private func detectHorizontalLines(in cgImage: CGImage) async throws -> [DetectedLine] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectRectanglesRequest()
                request.minimumAspectRatio = 0.01
                request.maximumAspectRatio = 1.0
                request.minimumSize = 0.05 // Reduced from 0.1 to catch shorter lines
                request.minimumConfidence = 0.2 // Reduced from 0.3 for better detection
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                
                do {
                    try handler.perform([request])
                    
                    guard let observations = request.results else {
                        continuation.resume(returning: [])
                        return
                    }
                    
                    // Filter for horizontal lines (rectangles with high aspect ratio)
                    let horizontalLines = observations.compactMap { observation -> DetectedLine? in
                        let box = observation.boundingBox
                        let aspectRatio = box.width / box.height
                        
                        // Horizontal line: width >> height
                        // Relaxed criteria: aspect ratio > 8.0 and width > 0.4
                        if aspectRatio > 8.0 && box.width > 0.4 {
                            return DetectedLine(
                                startPoint: CGPoint(x: box.minX, y: box.midY),
                                endPoint: CGPoint(x: box.maxX, y: box.midY),
                                orientation: .horizontal,
                                confidence: observation.confidence
                            )
                        }
                        return nil
                    }
                    
                    print("🔍 Detected \(horizontalLines.count) horizontal lines")
                    for (i, line) in horizontalLines.enumerated() {
                        print("  Line \(i+1): y=\(String(format: "%.3f", line.startPoint.y)), width=\(String(format: "%.3f", line.endPoint.x - line.startPoint.x)), confidence=\(String(format: "%.2f", line.confidence))")
                    }
                    
                    continuation.resume(returning: horizontalLines)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func detectVerticalDivider(in cgImage: CGImage) async throws -> DetectedLine? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Use edge detection to find the vertical divider
                let request = VNDetectRectanglesRequest()
                request.minimumAspectRatio = 0.01
                request.maximumAspectRatio = 1.0
                request.minimumSize = 0.05 // Reduced from 0.1
                request.minimumConfidence = 0.15 // Reduced from 0.2
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                
                do {
                    try handler.perform([request])
                    
                    guard let observations = request.results else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Filter for vertical lines (rectangles with low aspect ratio)
                    let verticalLines = observations.compactMap { observation -> DetectedLine? in
                        let box = observation.boundingBox
                        let aspectRatio = box.width / box.height
                        
                        // Vertical line: height >> width, and positioned in middle region
                        // Relaxed height requirement from 0.3 to 0.2
                        if aspectRatio < 0.15 && box.height > 0.2 && box.midX > 0.25 && box.midX < 0.75 {
                            return DetectedLine(
                                startPoint: CGPoint(x: box.midX, y: box.minY),
                                endPoint: CGPoint(x: box.midX, y: box.maxY),
                                orientation: .vertical,
                                confidence: observation.confidence
                            )
                        }
                        return nil
                    }
                    
                    print("🔍 Found \(verticalLines.count) vertical line candidates")
                    for (i, line) in verticalLines.enumerated() {
                        print("  Candidate \(i+1): x=\(String(format: "%.3f", line.startPoint.x)), height=\(String(format: "%.3f", line.endPoint.y - line.startPoint.y)), confidence=\(String(format: "%.2f", line.confidence))")
                    }
                    
                    // Return the most confident vertical line
                    let bestLine = verticalLines.max { $0.confidence < $1.confidence }
                    if let best = bestLine {
                        print("✅ Selected vertical divider at x=\(String(format: "%.3f", best.startPoint.x))")
                    } else {
                        print("⚠️ No vertical divider detected")
                    }
                    
                    continuation.resume(returning: bestLine)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Alternative Vertical Divider Detection using Edge Detection
    
    private func detectVerticalDividerUsingEdges(in cgImage: CGImage) async throws -> DetectedLine? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Create CIImage for edge detection
                let ciImage = CIImage(cgImage: cgImage)
                
                guard let edgeFilter = CIFilter(name: "CIEdges") else {
                    continuation.resume(returning: nil)
                    return
                }
                
                edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
                edgeFilter.setValue(2.0, forKey: kCIInputIntensityKey)
                
                guard let edgeOutput = edgeFilter.outputImage else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let context = CIContext()
                guard let edgeCGImage = context.createCGImage(edgeOutput, from: edgeOutput.extent) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Now use line detection on edge image
                let request = VNDetectContoursRequest()
                let handler = VNImageRequestHandler(cgImage: edgeCGImage, options: [:])
                
                do {
                    try handler.perform([request])
                    
                    // Process contours to find vertical lines
                    guard let observations = request.results else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Analyze contours for vertical line candidates
                    let verticalLine = self.findVerticalLineInContours(observations, imageSize: ciImage.extent.size)
                    continuation.resume(returning: verticalLine)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    nonisolated private func findVerticalLineInContours(_ observations: [VNContoursObservation], imageSize: CGSize) -> DetectedLine? {
        // Analyze contours to find strong vertical line in middle region
        var verticalCandidates: [(x: CGFloat, strength: Float)] = []
        
        for observation in observations {
            let normalizedPath = observation.normalizedPath
            
            // Check if contour is predominantly vertical
            let bounds = normalizedPath.boundingBox
            if bounds.height > 0.3 && bounds.width < 0.05 && bounds.midX > 0.3 && bounds.midX < 0.7 {
                verticalCandidates.append((x: bounds.midX, strength: observation.confidence))
            }
        }
        
        // Find the strongest candidate
        guard let best = verticalCandidates.max(by: { $0.strength < $1.strength }) else {
            return nil
        }
        
        return DetectedLine(
            startPoint: CGPoint(x: best.x, y: 0.2),
            endPoint: CGPoint(x: best.x, y: 0.8),
            orientation: .vertical,
            confidence: best.strength
        )
    }
    
    // MARK: - Heuristic Vertical Divider Detection
    
    private func detectVerticalDividerHeuristic(textObservations: [VNRecognizedTextObservation]) -> CGFloat? {
        // Analyze the X-positions of text blocks to find a gap
        let xPositions = textObservations.map { $0.boundingBox.midX }.sorted()
        
        guard xPositions.count > 5 else { return nil }
        
        // Look for the largest gap in the middle region (0.3 to 0.7)
        var maxGap: CGFloat = 0
        var dividerPosition: CGFloat?
        
        for i in 0..<(xPositions.count - 1) {
            let gap = xPositions[i + 1] - xPositions[i]
            let midPoint = (xPositions[i] + xPositions[i + 1]) / 2
            
            if midPoint > 0.3 && midPoint < 0.7 && gap > maxGap {
                maxGap = gap
                dividerPosition = midPoint
            }
        }
        
        // Only accept if gap is significant (> 5% of image width)
        return maxGap > 0.05 ? dividerPosition : nil
    }
    
    // MARK: - Layout Analysis
    
    private func analyzeLayout(
        textObservations: [VNRecognizedTextObservation],
        horizontalLines: [DetectedLine],
        verticalDivider: DetectedLine?,
        imageSize: CGSize,
        originalImageSize: CGSize? = nil
    ) -> RecipeAnalysis {
        
        // Step 1: Segment sections using horizontal lines
        let sections = segmentSections(textObservations: textObservations, horizontalLines: horizontalLines)
        
        // Step 2: Determine vertical divider position (use detected line or heuristic)
        let dividerX = verticalDivider?.startPoint.x ?? detectVerticalDividerHeuristic(textObservations: textObservations)
        
        // Step 3: Create column layout
        let columnLayout = createColumnLayout(dividerX: dividerX, imageSize: imageSize)
        
        // Step 4: Extract ingredient section
        var ingredientTextObservations: [VNRecognizedTextObservation]
        
        if let ingredientSection = sections.first(where: { $0.type == .ingredients }) {
            ingredientTextObservations = ingredientSection.textObservations
        } else {
            // FALLBACK: If no ingredient section detected, use heuristic to find ingredient-like text
            ingredientTextObservations = detectIngredientSectionHeuristic(
                textObservations: textObservations,
                verticalDivider: dividerX
            )
        }
        
        // Step 5: Group ingredient text blocks into rows
        let ingredientRows = groupIntoRows(
            textObservations: ingredientTextObservations,
            columnLayout: columnLayout
        )
        
        return RecipeAnalysis(
            sections: sections,
            columnLayout: columnLayout,
            ingredientRows: ingredientRows,
            imageSize: imageSize,
            originalImageSize: originalImageSize
        )
    }
    
    // MARK: - Heuristic Ingredient Detection
    
    private func detectIngredientSectionHeuristic(
        textObservations: [VNRecognizedTextObservation],
        verticalDivider: CGFloat?
    ) -> [VNRecognizedTextObservation] {
        
        // Strategy: Look for text blocks that appear to be ingredients
        // Characteristics:
        // 1. In the upper-middle portion of the image (Y: 0.3 to 0.9 in Vision coordinates)
        // 2. Contains numbers, fractions, or measurement units
        // 3. Distributed across columns (if divider detected)
        // 4. EXCLUDE metadata/summary lines (like "Makes 1 to 1½ cups")
        
        let ingredientPatterns = [
            "tsp", "tbsp", "cup", "ml", "mL", "oz", "lb", "kg", "g",
            "½", "¼", "⅓", "⅔", "¾", "⅛",
            "medium", "large", "small", "chopped", "sliced", "diced"
        ]
        
        // Patterns that indicate metadata/summary lines (not ingredients)
        let metadataPatterns = [
            "makes", "yield", "serves", "serving", "preparation time", "prep time",
            "cook time", "total time", "difficulty"
        ]
        
        var candidateObservations: [VNRecognizedTextObservation] = []
        
        // First pass: identify metadata lines (typically single lines spanning across or near top)
        var metadataObservations: [VNRecognizedTextObservation] = []
        
        for observation in textObservations {
            if let text = observation.topCandidates(1).first?.string.lowercased() {
                // Check if this is a metadata line
                let isMetadata = metadataPatterns.contains { pattern in
                    text.contains(pattern.lowercased())
                }
                
                if isMetadata {
                    metadataObservations.append(observation)
                }
            }
        }
        
        // Find the lowest Y position of metadata (below which ingredients start)
        let metadataMinY = metadataObservations.map { $0.boundingBox.minY }.min()
        
        // Second pass: identify ingredient observations
        for observation in textObservations {
            let y = observation.boundingBox.midY
            
            // Skip if this is a metadata observation
            if metadataObservations.contains(where: { $0 === observation }) {
                continue
            }
            
            // If we found metadata, ingredients must be below it
            if let metadataY = metadataMinY, observation.boundingBox.maxY >= metadataY {
                continue
            }
            
            // Filter by position (ingredients typically in middle-upper region)
            // Vision uses bottom-left origin, so higher Y = higher on page
            guard y >= 0.3 && y <= 0.9 else { continue }
            
            // Check if text contains ingredient-like patterns
            if let text = observation.topCandidates(1).first?.string.lowercased() {
                // Check for numbers
                let containsNumber = text.rangeOfCharacter(from: .decimalDigits) != nil
                
                // Check for measurement units or ingredient keywords
                let containsIngredientKeyword = ingredientPatterns.contains { pattern in
                    text.contains(pattern.lowercased())
                }
                
                // Check if text is short (ingredients are typically concise)
                let isShort = text.count < 30
                
                // If it matches criteria, add it
                if (containsNumber || containsIngredientKeyword) && isShort {
                    candidateObservations.append(observation)
                }
            }
        }
        
        // If we found some candidates but not many, expand the search
        if candidateObservations.count < 5 {
            // Include all text in the typical ingredient region with two-column layout
            for observation in textObservations {
                let y = observation.boundingBox.midY
                
                // Skip metadata observations
                if metadataObservations.contains(where: { $0 === observation }) {
                    continue
                }
                
                // If we found metadata, skip anything at or above it
                if let metadataY = metadataMinY, observation.boundingBox.maxY >= metadataY {
                    continue
                }
                
                guard y >= 0.4 && y <= 0.85 else { continue }
                
                if !candidateObservations.contains(where: { $0 === observation }) {
                    candidateObservations.append(observation)
                }
            }
        }
        
        return candidateObservations
    }
    
    private func segmentSections(
        textObservations: [VNRecognizedTextObservation],
        horizontalLines: [DetectedLine]
    ) -> [RecipeSection] {
        
        // Sort lines by Y position (top to bottom in normalized coordinates)
        let sortedLines = horizontalLines.sorted { $0.startPoint.y > $1.startPoint.y }
        
        // Vision framework uses bottom-left origin, so Y=1.0 is top of image
        var sections: [RecipeSection] = []
        
        // Patterns that indicate metadata/summary lines
        let metadataPatterns = [
            "makes", "yield", "serves", "serving", "preparation time", "prep time",
            "cook time", "total time", "difficulty"
        ]
        
        // If we have horizontal lines, use them to segment
        if !sortedLines.isEmpty {
            // Title section (everything above first horizontal line)
            if let firstLine = sortedLines.first {
                let titleObservations = textObservations.filter { $0.boundingBox.minY > firstLine.startPoint.y }
                if !titleObservations.isEmpty {
                    sections.append(RecipeSection(
                        type: .title,
                        boundingBox: combinedBoundingBox(titleObservations),
                        textObservations: titleObservations
                    ))
                }
            }
            
            // Ingredient section (between first and second horizontal lines, or first line to bottom if only one line)
            if sortedLines.count >= 2 {
                let topY = sortedLines[0].startPoint.y
                let bottomY = sortedLines[1].startPoint.y
                
                var ingredientCandidates = textObservations.filter { obs in
                    obs.boundingBox.midY < topY && obs.boundingBox.midY > bottomY
                }
                
                // Separate metadata from actual ingredients
                // Look for the first line after the top horizontal line - if it contains metadata keywords,
                // it's a summary/metadata line, not an ingredient
                if !ingredientCandidates.isEmpty {
                    let sortedCandidates = ingredientCandidates.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                    
                    // Check the topmost text block(s) for metadata patterns
                    var metadataObservations: [VNRecognizedTextObservation] = []
                    if let firstCandidate = sortedCandidates.first,
                       let text = firstCandidate.topCandidates(1).first?.string.lowercased() {
                        
                        let isMetadata = metadataPatterns.contains { pattern in
                            text.contains(pattern.lowercased())
                        }
                        
                        if isMetadata {
                            // This is metadata - collect all text blocks at similar Y level
                            let metadataY = firstCandidate.boundingBox.midY
                            let threshold: CGFloat = 0.015 // Same Y-level threshold
                            
                            for candidate in sortedCandidates {
                                if abs(candidate.boundingBox.midY - metadataY) < threshold {
                                    metadataObservations.append(candidate)
                                }
                            }
                            
                            // Add metadata section
                            sections.append(RecipeSection(
                                type: .metadata,
                                boundingBox: combinedBoundingBox(metadataObservations),
                                textObservations: metadataObservations
                            ))
                            
                            // Remove metadata from ingredient candidates
                            ingredientCandidates = ingredientCandidates.filter { candidate in
                                !metadataObservations.contains(where: { $0 === candidate })
                            }
                        }
                    }
                }
                
                // Add ingredient section (without metadata)
                if !ingredientCandidates.isEmpty {
                    sections.append(RecipeSection(
                        type: .ingredients,
                        boundingBox: combinedBoundingBox(ingredientCandidates),
                        textObservations: ingredientCandidates
                    ))
                }
                
                // Instructions and variations (below second line)
                let remainingObservations = textObservations.filter { $0.boundingBox.maxY < bottomY }
                if !remainingObservations.isEmpty {
                    sections.append(RecipeSection(
                        type: .instructions,
                        boundingBox: combinedBoundingBox(remainingObservations),
                        textObservations: remainingObservations
                    ))
                }
            } else if let firstLine = sortedLines.first {
                // Only one line found - everything below is ingredients (but check for metadata first)
                var ingredientCandidates = textObservations.filter { $0.boundingBox.maxY < firstLine.startPoint.y }
                
                // Check for metadata at the top
                if !ingredientCandidates.isEmpty {
                    let sortedCandidates = ingredientCandidates.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                    var metadataObservations: [VNRecognizedTextObservation] = []
                    
                    if let firstCandidate = sortedCandidates.first,
                       let text = firstCandidate.topCandidates(1).first?.string.lowercased() {
                        
                        let isMetadata = metadataPatterns.contains { pattern in
                            text.contains(pattern.lowercased())
                        }
                        
                        if isMetadata {
                            let metadataY = firstCandidate.boundingBox.midY
                            let threshold: CGFloat = 0.015
                            
                            for candidate in sortedCandidates {
                                if abs(candidate.boundingBox.midY - metadataY) < threshold {
                                    metadataObservations.append(candidate)
                                }
                            }
                            
                            sections.append(RecipeSection(
                                type: .metadata,
                                boundingBox: combinedBoundingBox(metadataObservations),
                                textObservations: metadataObservations
                            ))
                            
                            ingredientCandidates = ingredientCandidates.filter { candidate in
                                !metadataObservations.contains(where: { $0 === candidate })
                            }
                        }
                    }
                }
                
                if !ingredientCandidates.isEmpty {
                    sections.append(RecipeSection(
                        type: .ingredients,
                        boundingBox: combinedBoundingBox(ingredientCandidates),
                        textObservations: ingredientCandidates
                    ))
                }
            }
        } else {
            // No horizontal lines detected - use heuristics to segment
            // This is a fallback that attempts to identify sections by content and position
            
            // Sort observations by Y position (top to bottom)
            let sortedObs = textObservations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            
            // Try to find title (typically at the top, Y > 0.85)
            let titleObservations = sortedObs.filter { $0.boundingBox.midY > 0.85 }
            if !titleObservations.isEmpty {
                sections.append(RecipeSection(
                    type: .title,
                    boundingBox: combinedBoundingBox(titleObservations),
                    textObservations: titleObservations
                ))
            }
            
            // Try to find ingredients (typically in middle region, Y: 0.3 to 0.85)
            let ingredientObservations = sortedObs.filter { obs in
                obs.boundingBox.midY >= 0.3 && obs.boundingBox.midY <= 0.85
            }
            if !ingredientObservations.isEmpty {
                sections.append(RecipeSection(
                    type: .ingredients,
                    boundingBox: combinedBoundingBox(ingredientObservations),
                    textObservations: ingredientObservations
                ))
            }
            
            // Instructions at bottom (Y < 0.3)
            let instructionObservations = sortedObs.filter { $0.boundingBox.midY < 0.3 }
            if !instructionObservations.isEmpty {
                sections.append(RecipeSection(
                    type: .instructions,
                    boundingBox: combinedBoundingBox(instructionObservations),
                    textObservations: instructionObservations
                ))
            }
        }
        
        return sections
    }
    
    private func createColumnLayout(dividerX: CGFloat?, imageSize: CGSize) -> ColumnLayout {
        if let dividerX = dividerX {
            return ColumnLayout(
                verticalDividerX: dividerX,
                leftColumnBounds: CGRect(x: 0, y: 0, width: dividerX, height: 1.0),
                rightColumnBounds: CGRect(x: dividerX, y: 0, width: 1.0 - dividerX, height: 1.0),
                imageSize: imageSize
            )
        } else {
            // No divider detected - assume single wide column or use default split
            return ColumnLayout(
                verticalDividerX: nil,
                leftColumnBounds: CGRect(x: 0, y: 0, width: 0.6, height: 1.0),
                rightColumnBounds: CGRect(x: 0.6, y: 0, width: 0.4, height: 1.0),
                imageSize: imageSize
            )
        }
    }
    
    private func groupIntoRows(
        textObservations: [VNRecognizedTextObservation],
        columnLayout: ColumnLayout
    ) -> [IngredientRow] {
        
        guard !textObservations.isEmpty else { return [] }
        
        // Sort by Y position (top to bottom in Vision coordinates, which is bottom-left origin)
        let sorted = textObservations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        
        // For two-column layouts, we need to collect ALL blocks at similar Y positions
        // across both columns before creating a row
        
        var rows: [IngredientRow] = []
        var processedIndices = Set<Int>()
        
        // Adaptive threshold based on typical text height
        let textHeights = sorted.map { $0.boundingBox.height }
        let avgTextHeight = textHeights.reduce(0, +) / CGFloat(textHeights.count)
        let rowHeightThreshold = max(avgTextHeight * 1.5, 0.015) // Use 1.5x avg text height or 1.5% minimum
        
        for (index, observation) in sorted.enumerated() {
            // Skip if already processed
            guard !processedIndices.contains(index) else { continue }
            
            let referenceY = observation.boundingBox.midY
            var rowBlocks: [VNRecognizedTextObservation] = [observation]
            processedIndices.insert(index)
            
            // Find all other blocks at the same Y level (within threshold)
            for (otherIndex, otherObservation) in sorted.enumerated() {
                guard !processedIndices.contains(otherIndex) else { continue }
                
                let otherY = otherObservation.boundingBox.midY
                
                if abs(otherY - referenceY) < rowHeightThreshold {
                    rowBlocks.append(otherObservation)
                    processedIndices.insert(otherIndex)
                }
            }
            
            // Create row from collected blocks
            if !rowBlocks.isEmpty {
                rows.append(createIngredientRow(from: rowBlocks, columnLayout: columnLayout))
            }
        }
        
        // Sort rows by position (top to bottom)
        rows.sort { $0.yPosition > $1.yPosition }
        
        return rows
    }
    
    private func createIngredientRow(
        from observations: [VNRecognizedTextObservation],
        columnLayout: ColumnLayout
    ) -> IngredientRow {
        
        let leftBlocks = observations.filter { columnLayout.columnForTextBlock($0) == .left }
        let rightBlocks = observations.filter { columnLayout.columnForTextBlock($0) == .right }
        
        let allYs = observations.flatMap { [$0.boundingBox.minY, $0.boundingBox.maxY] }
        let minY = allYs.min() ?? 0
        let maxY = allYs.max() ?? 0
        
        return IngredientRow(
            yPosition: minY,
            height: maxY - minY,
            leftColumnBlocks: leftBlocks.sorted { $0.boundingBox.minX < $1.boundingBox.minX },
            rightColumnBlocks: rightBlocks.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        )
    }
    
    private func combinedBoundingBox(_ observations: [VNRecognizedTextObservation]) -> CGRect {
        guard !observations.isEmpty else { return .zero }
        
        let minX = observations.map { $0.boundingBox.minX }.min() ?? 0
        let maxX = observations.map { $0.boundingBox.maxX }.max() ?? 0
        let minY = observations.map { $0.boundingBox.minY }.min() ?? 0
        let maxY = observations.map { $0.boundingBox.maxY }.max() ?? 0
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Supporting Types

struct DetectedLine {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let orientation: Orientation
    let confidence: Float
    
    enum Orientation {
        case horizontal
        case vertical
    }
}

struct RecipeAnalysis {
    let sections: [RecipeSection]
    let columnLayout: ColumnLayout
    let ingredientRows: [IngredientRow]
    let imageSize: CGSize
    let originalImageSize: CGSize?
    let wasUpscaled: Bool
    
    init(
        sections: [RecipeSection],
        columnLayout: ColumnLayout,
        ingredientRows: [IngredientRow],
        imageSize: CGSize,
        originalImageSize: CGSize? = nil
    ) {
        self.sections = sections
        self.columnLayout = columnLayout
        self.ingredientRows = ingredientRows
        self.imageSize = imageSize
        self.originalImageSize = originalImageSize
        self.wasUpscaled = originalImageSize != nil && originalImageSize != imageSize
    }
}

enum RecipeError: Error {
    case invalidImage
    case noTextDetected
    case noIngredientsFound
}

// MARK: - Usage Example

/*
 let detector = RecipeColumnDetector()
 
 // Modern async/await API
 Task {
     do {
         let analysis = try await detector.analyzeRecipeCard(image: recipeImage)
         print("Found \(analysis.ingredientRows.count) ingredient rows")
         
         if let dividerX = analysis.columnLayout.verticalDividerX {
             print("Vertical divider at x: \(dividerX)")
         }
         
         for (index, row) in analysis.ingredientRows.enumerated() {
             print("\nRow \(index + 1):")
             print("  Left column blocks: \(row.leftColumnBlocks.count)")
             print("  Right column blocks: \(row.rightColumnBlocks.count)")
             
             // Extract text from blocks
             for block in row.leftColumnBlocks {
                 if let text = block.topCandidates(1).first?.string {
                     print("    Left: \(text)")
                 }
             }
             
             for block in row.rightColumnBlocks {
                 if let text = block.topCandidates(1).first?.string {
                     print("    Right: \(text)")
                 }
             }
         }
     } catch {
         print("Error: \(error)")
     }
 }
 
 // Or using the legacy callback-based API
 detector.analyzeRecipeCard(image: recipeImage) { result in
     switch result {
     case .success(let analysis):
         print("Found \(analysis.ingredientRows.count) ingredient rows")
         
         if let dividerX = analysis.columnLayout.verticalDividerX {
             print("Vertical divider at x: \(dividerX)")
         }
         
         for (index, row) in analysis.ingredientRows.enumerated() {
             print("\nRow \(index + 1):")
             print("  Left column blocks: \(row.leftColumnBlocks.count)")
             print("  Right column blocks: \(row.rightColumnBlocks.count)")
             
             // Extract text from blocks
             for block in row.leftColumnBlocks {
                 if let text = block.topCandidates(1).first?.string {
                     print("    Left: \(text)")
                 }
             }
             
             for block in row.rightColumnBlocks {
                 if let text = block.topCandidates(1).first?.string {
                     print("    Right: \(text)")
                 }
             }
         }
         
     case .failure(let error):
         print("Error: \(error)")
     }
 }
 */
