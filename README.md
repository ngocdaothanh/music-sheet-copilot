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

## Future Enhancements

Planned features:
- Sheet music annotation and markup
- Export to PDF
- Compressed MusicXML (.mxl) support
- Transposition tools
- Tempo and playback controls

## Acknowledgments

- Music notation rendering: [Verovio](https://www.verovio.org/) by RISM Digital
- Demo piece: "Twinkle Twinkle Little Star" (Traditional)
- MusicXML format by MakeMusic/Steinberg
