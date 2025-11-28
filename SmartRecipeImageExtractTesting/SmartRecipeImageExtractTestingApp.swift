//
//  SmartRecipeImageExtractTestingApp.swift
//  SmartRecipeImageExtractTesting
//
//  Created by Zahirudeen Premji on 11/25/25.
//

import SwiftUI
import SwiftData

@main
struct SmartRecipeImageExtractTestingApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ImageMetadata.self,
            TransformationSnapshot.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            RecipeDetectorTestApp()
        }
        .modelContainer(sharedModelContainer)
    }
}
