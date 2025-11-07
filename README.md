# Music Sheets Copilot

A universal Apple app for viewing MusicXML sheet music files, powered by Verovio.

## Features

- 📱 Universal app: Works on iPhone, iPad, and macOS
- 🎵 Load and parse MusicXML files with **Verovio**
- 📦 **Compressed MusicXML (.mxl) support** on macOS
-  Professional music sheet rendering (SVG-based)
- 🎹 Demo files included:
  - Twinkle Twinkle Little Star (Traditional)
  - Für Elise - Easy Piano (Beethoven)
- 🔍 Zoom controls for better viewing
- 🎼 **MIDI playback** with play/pause controls
- 🎯 **Interactive note highlighting** during playback
- 👆 **Click-to-play**: Click any note to start playback from that point
- 🎹 **Staff toggling**: For piano pieces, toggle between treble and bass staves for practice
- 🥁 **Metronome** with three modes:
  - 🔊 Tick mode: Traditional metronome sound
  - 🔢 Count mode: Speaks beat numbers (1, 2, 3, 4)
  - 🎵 Solfege mode: Speaks note names (Do, Re, Mi)
- ⚙️ **Tempo adjustment**: Slow down (0.5x) or speed up (2.0x) playback for practice
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

### Opening the Project

1. Open `MusicSheetsCopilot.xcodeproj` in Xcode
2. Wait for Swift Package Manager to download Verovio (first time only)
3. **Add Verovio data resources** (see below)

### Adding Verovio Data Resources

The Verovio library requires font data files (Bravura, Leipzig, etc.) to render music notation.

**Verovio Swift Package** is downloaded by Xcode's Swift Package Manager to `~/Library/Developer/Xcode/DerivedData/MusicSheetsCopilot-.../SourcePackages/checkouts/verovio/data`.

Run:

```bash
./Scripts/setup-verovio-symlink.sh
```

This creates a symlink at `MusicSheetsCopilot/Resources/verovio-data` pointing to the Verovio data folder in DerivedData.

This symlink is ignored in `.gitignore`.

**Advantages:**
- ✅ No large data files committed to your repository
- ✅ Data stays in sync with the Verovio package version
- ✅ Simple standard Xcode build phase (no custom scripts needed)
- ✅ Works with Xcode's sandbox enabled
- ✅ Each developer runs the setup script once

## Recommended Packages for Future Development

- **[AudioKit](https://github.com/AudioKit/AudioKit)** - For audio playback of sheet music
- **[SwiftUI-Introspect](https://github.com/siteline/swiftui-introspect)** - Advanced SwiftUI view customization
