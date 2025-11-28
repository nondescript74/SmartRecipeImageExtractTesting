//
//  RecipeImagePicker.swift
//  SmartRecipeImageExtractTesting
//
//  Image picker wrapper for SwiftUI
//

import SwiftUI
import PhotosUI

// MARK: - Modern PHPicker Implementation (iOS 14+)

struct RecipeImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: SourceType
    @Environment(\.dismiss) private var dismiss
    
    enum SourceType {
        case camera
        case photoLibrary
    }
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No update needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: RecipeImagePicker
        
        init(_ parent: RecipeImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, error in
                    DispatchQueue.main.async {
                        self.parent.image = image as? UIImage
                    }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @State private var image: UIImage?
        @State private var showPicker = false
        
        var body: some View {
            VStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 300)
                }
                
                Button("Pick Image") {
                    showPicker = true
                }
                .sheet(isPresented: $showPicker) {
                    RecipeImagePicker(image: $image, sourceType: .photoLibrary)
                }
            }
        }
    }
    
    return PreviewWrapper()
}
