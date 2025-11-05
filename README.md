# Music Sheets Copilot

A universal iOS and macOS app for viewing MusicXML sheet music files, powered by Verovio.

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

### Prerequisites

- Xcode 15.0 or later
- macOS 14.0+ / iOS 17.0+ or later
- Swift 5.0+

### Opening the Project

1. Open `MusicSheetsCopilot.xcodeproj` in Xcode
2. Wait for Swift Package Manager to download Verovio (first time only)
3. **Add Verovio data resources** (required for iOS, see below)
4. Select your target device (Mac, iPhone, or iPad simulator)
5. Press `Cmd + R` to build and run

### Adding Verovio Data Resources

The Verovio library requires font data files (Bravura, Leipzig, etc.) to render music notation. On macOS, these are found automatically during development, but on iOS you need to add them to your app bundle.

#### Setup Instructions (One-time setup)

**Step 1: Create Symlink to Verovio Data**

After opening the project in Xcode and letting Swift Package Manager download Verovio, run:

```bash
./Scripts/setup-verovio-symlink.sh
```

This creates a symlink at `MusicSheetsCopilot/Resources/verovio-data` pointing to the Verovio data folder in DerivedData.

**Step 2: Add the symlink to .gitignore**

The symlink is machine-specific, so add it to `.gitignore`:

```bash
echo "MusicSheetsCopilot/Resources/verovio-data" >> .gitignore
```

**Step 3: Add to Copy Bundle Resources**

1. In Xcode, click on the **MusicSheetsCopilot** project (blue icon)
2. Select the **MusicSheetsCopilot** target
3. Go to the **Build Phases** tab
4. Expand **"Copy Bundle Resources"**
5. Click the **"+"** button
6. Click **"Add Other..."** → **"Add Files..."**
7. Navigate to your project folder and select: `MusicSheetsCopilot/Resources/verovio-data`
8. Click **"Add"**
9. The `verovio-data` folder should now appear in the Copy Bundle Resources list

### How It Works

1. **Verovio Swift Package** is downloaded by Xcode's Swift Package Manager to:
   ```
   ~/Library/Developer/Xcode/DerivedData/MusicSheetsCopilot-.../SourcePackages/checkouts/verovio/data
   ```

2. **Setup script** creates a symlink in your repo:
   ```
   MusicSheetsCopilot/Resources/verovio-data → DerivedData/.../verovio/data
   ```

3. **Xcode Copy Bundle Resources** follows the symlink and copies the actual data files into your app bundle at build time

**Advantages:**
- ✅ No large data files committed to your repository
- ✅ Data stays in sync with the Verovio package version
- ✅ Simple standard Xcode build phase (no custom scripts needed)
- ✅ Works with Xcode's sandbox enabled
- ✅ Each developer runs the setup script once

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
- Transposition tools
- Jump to specific measure by number
- Practice mode with loop sections

## Acknowledgments

- Music notation rendering: [Verovio](https://www.verovio.org/) by RISM Digital
- Demo pieces:
  - "Twinkle Twinkle Little Star" (Traditional)
  - "Für Elise" by Ludwig van Beethoven (Simplified arrangement)
