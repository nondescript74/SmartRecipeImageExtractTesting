# Image Metadata Persistence with SwiftData

This implementation adds persistent metadata storage for image transformations using SwiftData, with support for undo/redo functionality.

## Overview

The system persists the following metadata for each image:
- **Scale factor** (zoom level)
- **Rotation angle** (in degrees)
- **Modification timestamp**
- **Transformation history** (for undo support)

## Key Features

### 1. **Non-Destructive Editing**
- Original images in your asset catalog remain untouched
- All transformations are stored as metadata
- Images can be reset to their original state at any time

### 2. **Undo Support**
- Up to 20 previous transformations are stored in history
- Tap the "Undo" button to revert to the previous state
- History is automatically managed and pruned

### 3. **Automatic Persistence**
- Metadata is saved automatically when gestures end
- Manual save option available via the "Save" button
- Data persists between app launches

### 4. **Visual Indicators**
- Modified images display a blue border and pencil badge
- Undo button is disabled when no history is available
- Real-time feedback for scale and rotation values

## Files Created/Modified

### New Files

#### `ImageMetadata.swift`
SwiftData models for persisting transformation data:
- **ImageMetadata**: Main model storing current transformation state
- **TransformationSnapshot**: Snapshot of a transformation for undo history

Key methods:
```swift
updateTransformation(scale:rotationDegrees:) // Saves current state and updates
undo() -> Bool // Restores previous state
reset() // Resets to defaults (1.0 scale, 0° rotation)
```

#### `ImageMetadataTests.swift`
Comprehensive test suite using Swift Testing framework covering:
- Metadata creation and updates
- Undo functionality
- History management
- Persistence verification

### Modified Files

#### `SmartRecipeImageExtractTestingApp.swift`
- Added SwiftData ModelContainer configuration
- Registered ImageMetadata and TransformationSnapshot models
- Applied modelContainer to WindowGroup

#### `ImageCollectionView.swift`
Enhanced with SwiftData integration:

**ImageCollectionView**:
- Added @Query to fetch all metadata
- Shows visual indicators for modified images
- Passes modification state to thumbnails

**ImageThumbnail**:
- Displays blue border for modified images
- Shows pencil badge on modified images

**ImageDetailView**:
- Loads saved metadata on appear
- Automatically saves after gesture transformations
- Three action buttons:
  - **Undo**: Reverts to previous state (orange, disabled when unavailable)
  - **Reset**: Resets to original state (blue)
  - **Save**: Manually saves current state (green)
- Displays image name in navigation bar

## Usage

### Basic Workflow

1. **View Images**: Open the app to see your image collection
2. **Select Image**: Tap an image to open the detail view
3. **Transform Image**: 
   - Pinch to zoom (or use scale slider)
   - Rotate with two fingers (or use rotation slider)
4. **Save Changes**: Changes auto-save after gestures, or tap "Save"
5. **Undo Changes**: Tap "Undo" to revert to previous state
6. **Reset Image**: Tap "Reset" to return to original state
7. **Close**: Tap "Done" to return to collection (auto-saves)

### Visual Cues

- **Gray border**: Unmodified image
- **Blue border + badge**: Image has saved modifications
- **Orange undo button**: Undo is available
- **Gray undo button**: No undo history

## Data Model

### ImageMetadata
```swift
@Model
final class ImageMetadata {
    @Attribute(.unique) var imageName: String
    var scale: Double
    var rotationDegrees: Double
    var lastModified: Date
    @Relationship(deleteRule: .cascade) var history: [TransformationSnapshot]?
}
```

### TransformationSnapshot
```swift
@Model
final class TransformationSnapshot {
    var scale: Double
    var rotationDegrees: Double
    var timestamp: Date
}
```

## Implementation Details

### Metadata Loading
When an image detail view opens:
1. Fetches existing metadata using `FetchDescriptor` with predicate
2. If found, loads saved scale and rotation values
3. If not found, creates new metadata with default values (1.0 scale, 0° rotation)
4. Updates undo button state based on history

### Metadata Saving
Transformations are saved:
1. Automatically after pinch/rotate gesture ends
2. After slider value changes via manual save
3. When "Done" button is tapped
4. Only if values have changed (to avoid unnecessary writes)

### History Management
- Each transformation update saves the previous state to history
- History is automatically limited to 20 snapshots
- Oldest snapshots are removed when limit is exceeded
- Cascade delete ensures snapshots are removed with their parent metadata

### Undo Operation
1. Retrieves the last snapshot from history
2. Restores scale and rotation from snapshot
3. Removes snapshot from history
4. Updates UI to reflect restored state
5. Saves changes to SwiftData

## Performance Considerations

- **Lazy Loading**: Uses `@Query` for efficient data fetching
- **Change Detection**: Only saves when values actually change (0.01 threshold for scale, 0.1° for rotation)
- **History Limit**: Prevents unbounded growth with 20-snapshot cap
- **In-Memory Images**: Original images remain in asset catalog (no file system operations)

## Testing

Run the included test suite `ImageMetadataTests.swift` to verify:
- Metadata creation and persistence
- Transformation updates
- Undo functionality
- History management
- Unique constraints

All tests use in-memory storage for fast, isolated testing.

## Future Enhancements

Potential additions:
- Redo functionality (requires separate redo stack)
- Export transformed images
- Batch operations on multiple images
- Additional transformations (brightness, contrast, filters)
- Cloud sync via CloudKit
- Sharing metadata between devices

## Requirements

- iOS 17.0+ (SwiftData availability)
- Xcode 15.0+
- Swift 6.0+

## Notes

- Metadata is stored in the default SwiftData persistent store
- Original assets are never modified
- Database location: App's document directory (default SwiftData location)
- Each image maintains its own independent metadata and history
