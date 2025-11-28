# SwiftData Image Metadata Architecture

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    App Launch                                    │
│  SmartRecipeImageExtractTestingApp.swift                        │
│                                                                   │
│  • Creates ModelContainer with Schema                            │
│  • Registers: ImageMetadata, TransformationSnapshot             │
│  • Injects into Environment via .modelContainer()               │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              ImageCollectionView                                 │
│                                                                   │
│  @Environment(\.modelContext)                                   │
│  @Query private var allMetadata: [ImageMetadata]                │
│                                                                   │
│  • Displays grid of image thumbnails                            │
│  • Queries all metadata to show modification badges            │
│  • Passes metadata status to ImageThumbnail                     │
└────────────────────────┬────────────────────────────────────────┘
                         │ User taps image
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              ImageDetailView                                     │
│                                                                   │
│  @Environment(\.modelContext)                                   │
│  @State private var imageMetadata: ImageMetadata?              │
│                                                                   │
│  ┌──────────────┐                                               │
│  │  .onAppear   │──────> loadMetadata()                        │
│  └──────────────┘                                               │
│         │                                                        │
│         └──> FetchDescriptor<ImageMetadata>                    │
│              predicate: imageName == current                    │
│              │                                                   │
│              ├──> Found: Load scale & rotation                  │
│              └──> Not Found: Create new with defaults           │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  User Interactions                                         │  │
│  │  • Pinch Gesture ──> onEnded ──> saveMetadata()          │  │
│  │  • Rotate Gesture ──> onEnded ──> saveMetadata()         │  │
│  │  • Slider Change                                           │  │
│  │  • Tap Save Button ──> saveMetadata()                    │  │
│  │  • Tap Undo Button ──> undoLastChange()                  │  │
│  │  • Tap Reset Button ──> resetTransformations()           │  │
│  │  • Tap Done Button ──> saveMetadata() then dismiss()     │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                  SwiftData Persistence                           │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  ImageMetadata (@Model)                                    │  │
│  │  ├── imageName: String (@Attribute(.unique))             │  │
│  │  ├── scale: Double                                         │  │
│  │  ├── rotationDegrees: Double                              │  │
│  │  ├── lastModified: Date                                    │  │
│  │  └── history: [TransformationSnapshot]? (@Relationship)   │  │
│  │                                                             │  │
│  │  Methods:                                                   │  │
│  │  • updateTransformation(scale:rotationDegrees:)           │  │
│  │    ├── Saves current state to history                     │  │
│  │    ├── Updates to new values                              │  │
│  │    └── Prunes history to 20 items                         │  │
│  │                                                             │  │
│  │  • undo() -> Bool                                          │  │
│  │    ├── Pops last snapshot from history                    │  │
│  │    ├── Restores previous scale & rotation                 │  │
│  │    └── Returns false if no history                        │  │
│  │                                                             │  │
│  │  • reset()                                                 │  │
│  │    └── Calls updateTransformation(1.0, 0.0)              │  │
│  └───────────────────────────────────────────────────────────┘  │
│                           │                                      │
│                           │ @Relationship                        │
│                           │ (cascade delete)                     │
│                           ▼                                      │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  TransformationSnapshot (@Model)                          │  │
│  │  ├── scale: Double                                         │  │
│  │  ├── rotationDegrees: Double                              │  │
│  │  └── timestamp: Date                                       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  Stored in: App Documents Directory                             │
│  File: default.store (SQLite database)                          │
└─────────────────────────────────────────────────────────────────┘
```

## State Management Flow

```
User Opens Image Detail View
         │
         ▼
   loadMetadata()
         │
         ├──> Fetch from SwiftData
         │    • Found? ──> Load saved values
         │    • Not found? ──> Create new (1.0, 0°)
         │
         ▼
   Update UI State
   • scale = metadata.scale
   • rotation = metadata.rotationDegrees
   • canUndo = !history.isEmpty
         │
         ▼
   User Makes Changes
   (pinch, rotate, sliders)
         │
         ▼
   Gesture/Slider Ends
         │
         ▼
   saveMetadata()
         │
         ├──> Check if changed (threshold: 0.01 scale, 0.1°)
         │    • No change? ──> Skip save
         │    • Changed? ──> Continue
         │
         ├──> metadata.updateTransformation()
         │         │
         │         ├──> Create snapshot of OLD state
         │         ├──> Append to history[]
         │         ├──> Prune if > 20 snapshots
         │         └──> Update to NEW state
         │
         ├──> modelContext.save()
         │
         └──> Update canUndo state
         │
         ▼
   UI reflects saved state
```

## Undo Flow

```
User Taps Undo Button
         │
         ▼
   undoLastChange()
         │
         ├──> Check if history exists
         │    • Empty? ──> Return false, disable button
         │    • Has items? ──> Continue
         │
         ├──> metadata.undo()
         │         │
         │         ├──> Pop last snapshot from history[]
         │         └──> Restore scale & rotation from snapshot
         │
         ├──> Update local state from metadata
         │    • scale = metadata.scale
         │    • rotation = metadata.rotationDegrees
         │
         ├──> modelContext.save()
         │
         └──> Update canUndo based on remaining history
         │
         ▼
   UI animates to restored state
```

## Visual Indicators

```
┌─────────────────────────────────────────────┐
│     ImageCollectionView Grid                │
│                                             │
│  ┌──────┐  ┌──────┐  ┌──────┐              │
│  │      │  │  📝  │  │      │              │
│  │ Img1 │  │ Img2 │  │ Img3 │              │
│  │ Gray │  │ Blue │  │ Gray │              │
│  └──────┘  └──────┘  └──────┘              │
│      ▲          ▲         ▲                 │
│      │          │         │                 │
│  Default    Modified   Default              │
│  (1.0, 0°)  (1.5, 45°) (1.0, 0°)           │
└─────────────────────────────────────────────┘

Detail View Controls:
┌─────────────────────────────────────────────┐
│  [Undo] [Reset] [Save]                      │
│   🟧      🔵      🟩                         │
│                                             │
│  Undo:  Orange when available               │
│         Gray when disabled (no history)     │
│  Reset: Always blue (returns to 1.0, 0°)   │
│  Save:  Green (explicit save)               │
└─────────────────────────────────────────────┘
```

## Performance Optimizations

1. **Change Detection Threshold**
   - Scale: Changes < 0.01 ignored
   - Rotation: Changes < 0.1° ignored
   - Prevents excessive saves from floating-point drift

2. **History Pruning**
   - Automatically limits to 20 snapshots
   - Prevents unbounded memory growth
   - Oldest snapshots removed first (FIFO)

3. **Lazy Loading**
   - @Query only fetches when needed
   - Predicates filter at database level
   - Efficient for large image collections

4. **Cascade Delete**
   - Deleting ImageMetadata auto-deletes snapshots
   - Prevents orphaned records
   - Maintains database integrity

## Testing Strategy

```
Unit Tests (Swift Testing)
├── Metadata Creation
│   └── Default values (1.0, 0°)
├── Transformation Updates
│   ├── Single update
│   ├── Multiple updates
│   └── History accumulation
├── Undo Operations
│   ├── Successful undo
│   ├── Failed undo (empty history)
│   └── Multiple undos
├── History Management
│   ├── 20-item limit
│   └── FIFO pruning
├── Reset Functionality
│   └── Saves to history before reset
└── Persistence
    ├── Unique constraints
    ├── Fetch operations
    └── Save/Load cycle
```

## Future Extensions

Possible enhancements:
- **Redo Stack**: Implement forward navigation through changes
- **Batch Operations**: Apply transformations to multiple images
- **Export**: Save transformed images to Photos
- **CloudKit Sync**: Share metadata across devices
- **Smart Snapshots**: Only save significant changes
- **Comparison View**: Show before/after side by side
- **Presets**: Save and apply transformation presets
