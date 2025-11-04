# Music Sheets Copilot

A universal iOS and macOS app for viewing MusicXML sheet music files, powered by Verovio.

## Features

- 📱 Universal app: Works on iPhone, iPad, and macOS
- 🎵 Load and parse MusicXML files with **Verovio**
- 📄 Professional music sheet rendering (SVG-based)
- 🎹 Demo file included (Twinkle Twinkle Little Star)
- 🔍 Zoom controls for better viewing
- ⚡ High-quality output used by academic institutions worldwide

## Technology Stack

- **SwiftUI** - Modern UI framework
- **Verovio** - Industry-standard music notation engraving library
  - C++ library with Swift bindings
  - Supports MusicXML, MEI, and Humdrum formats
  - Renders to beautiful SVG output
  - Used by RISM and major music libraries
- **WebKit** - For SVG display

## Getting Started

### Prerequisites

- Xcode 15.0 or later
- macOS 14.0+ / iOS 17.0+ or later
- Swift 5.0+

### Opening the Project

1. Open `MusicSheetsCopilot.xcodeproj` in Xcode
2. Wait for Swift Package Manager to download Verovio (first time only)
3. Select your target device (Mac, iPhone, or iPad simulator)
4. Press `Cmd + R` to build and run

### Swift Package Manager

This project uses Swift Package Manager for dependencies.

#### Current Dependencies:

- **[Verovio](https://github.com/rism-digital/verovio)** (v4.0+) - MusicXML parsing and rendering

#### To add more packages:

1. In Xcode, go to **File → Add Package Dependencies...**
2. Enter the package URL
3. Select version requirements
4. Add to the MusicSheetsCopilot target

#### Recommended Packages for Future Development:

- **[AudioKit](https://github.com/AudioKit/AudioKit)** - For audio playback of sheet music
- **[SwiftUI-Introspect](https://github.com/siteline/swiftui-introspect)** - Advanced SwiftUI view customization

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
    │   ├── MusicScore.swift         # Music score data structures (legacy)
    │   ├── MusicXMLParser.swift     # XML parsing logic (legacy)
    │   └── VerovioService.swift     # Verovio wrapper for Swift
    ├── Views/                        # UI components
    │   ├── MusicSheetView.swift     # Custom sheet music rendering (legacy)
    │   └── SVGMusicSheetView.swift  # Verovio SVG display view
    ├── Resources/                    # App resources
    │   └── twinkle_twinkle.xml      # Demo MusicXML file
    ├── Assets.xcassets/             # App icons and assets
    └── Info.plist                   # App configuration
```

## Supported MusicXML Features

Thanks to Verovio, this app supports the **complete MusicXML specification**, including:
- All note types, rests, and rhythms
- Treble, bass, alto, tenor clefs
- Key signatures and time signatures
- Beaming, stems, and flags
- Slurs, ties, and articulations
- Dynamics and expression marks
- Multiple staves and parts
- Lyrics and text annotations
- And much more!

## How It Works

1. **User selects MusicXML file** via file picker or demo button
2. **VerovioService** loads the MusicXML data
3. **Verovio C++ library** parses and renders to SVG
4. **SVGMusicSheetView** displays the SVG in a WKWebView
5. **User can zoom and scroll** through the beautiful rendered notation

## Future Enhancements

Planned features:
- MIDI playback (Verovio can export MIDI!)
- Sheet music annotation and markup
- Export to PDF
- Multi-page navigation
- Print support
- Compressed MusicXML (.mxl) support
- Transposition tools
- Tempo and playback controls

## MusicXML Format

This app uses the MusicXML format, an open standard for digital sheet music. Learn more at [MusicXML.com](https://www.musicxml.com/).

## License

This project is created for educational purposes.

## Acknowledgments

- Music notation rendering: [Verovio](https://www.verovio.org/) by RISM Digital
- Demo piece: "Twinkle Twinkle Little Star" (Traditional)
- MusicXML format by MakeMusic/Steinberg
