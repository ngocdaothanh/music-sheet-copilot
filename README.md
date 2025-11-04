# Music Sheets Copilot

A universal iOS and macOS app for viewing MusicXML sheet music files.

## Features

- 📱 Universal app: Works on iPhone, iPad, and macOS
- 🎵 Load and parse MusicXML files
- 📄 Visual music sheet rendering
- 🎹 Demo file included (Twinkle Twinkle Little Star)
- 🔍 Zoom controls for better viewing

## Getting Started

### Prerequisites

- Xcode 15.0 or later
- macOS 14.0+ / iOS 17.0+ or later
- Swift 5.0+

### Opening the Project

1. Open `MusicSheetsCopilot.xcodeproj` in Xcode
2. Select your target device (Mac, iPhone, or iPad simulator)
3. Press `Cmd + R` to build and run

### Swift Package Manager

This project is configured to use Swift Package Manager for dependencies. To add a new package:

1. In Xcode, go to **File → Add Package Dependencies...**
2. Enter the package URL
3. Select version requirements
4. Add to the MusicSheetsCopilot target

#### Recommended Packages for Future Development:

- **[AudioKit](https://github.com/AudioKit/AudioKit)** - For audio playback of sheet music
- **[SwiftUI-Introspect](https://github.com/siteline/swiftui-introspect)** - Advanced SwiftUI view customization
- Standard Apple frameworks (MusicKit, CoreMIDI) are built-in, no SPM needed

### Using the App

1. **Load Demo**: Click "Load Demo" to view the included Twinkle Twinkle Little Star example
2. **Open File**: Click "Open File..." to load your own MusicXML files
3. **Zoom**: Use the toolbar buttons to zoom in/out or reset to 100%

## Project Structure

```
MusicSheetsCopilot/
├── MusicSheetsCopilot.xcodeproj/    # Xcode project file
└── MusicSheetsCopilot/              # Source code
    ├── MusicSheetsCopilotApp.swift  # App entry point
    ├── ContentView.swift             # Main view with file loading
    ├── Models/                       # Data models
    │   ├── MusicScore.swift         # Music score data structures
    │   └── MusicXMLParser.swift     # XML parsing logic
    ├── Views/                        # UI components
    │   └── MusicSheetView.swift     # Sheet music rendering
    ├── Resources/                    # App resources
    │   └── twinkle_twinkle.xml      # Demo MusicXML file
    ├── Assets.xcassets/             # App icons and assets
    └── Info.plist                   # App configuration
```

## Supported MusicXML Features

Currently supports:
- Basic note rendering (whole, half, quarter notes)
- Rests
- Treble and bass clefs
- Key signatures (sharps and flats)
- Time signatures
- Multiple measures and systems
- Pitch notation (C4-C6 range optimized for treble clef)

## Future Enhancements

Planned features:
- More complete MusicXML element support
- Playback functionality
- Sheet music annotation
- Export to PDF
- Multiple parts/staves
- Dynamic performance markings
- Compressed MusicXML (.mxl) support

## MusicXML Format

This app uses the MusicXML format, an open standard for digital sheet music. Learn more at [MusicXML.com](https://www.musicxml.com/).

## License

This project is created for educational purposes.

## Acknowledgments

- Demo piece: "Twinkle Twinkle Little Star" (Traditional)
- MusicXML format by MakeMusic
