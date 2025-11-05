# MusicSheetsCopilot Tests

This directory contains automated tests for the MusicSheetsCopilot app using **Swift Testing** (requires Xcode 16+).

## Setup Instructions

### 1. Add Test Target in Xcode

1. Open `MusicSheetsCopilot.xcodeproj` in Xcode
2. Go to **File → New → Target...**
3. Choose **Unit Testing Bundle**
4. Name it `MusicSheetsCopilotTests`
5. Make sure **Testing Framework** is set to **Swift Testing** (not XCTest)
6. Click **Finish**

### 2. Add Test Files to Target

1. In Xcode's Project Navigator, select `MetronomeTests.swift`
2. In the File Inspector (right panel), check the box for `MusicSheetsCopilotTests` target
3. Make sure the main app target `MusicSheetsCopilot` is also checked

### 3. Configure Test Target

1. Select the project in Project Navigator
2. Select `MusicSheetsCopilotTests` target
3. Under **Build Settings**, search for "Enable Testability"
4. Make sure **Enable Testability** is set to **Yes**

## Running Tests

### Run All Tests
- Press **Cmd + U** in Xcode
- Or click the ▶️ button next to `@Suite("Metronome Tests")` in the source code

### Run Individual Test
- Click the ◇ diamond icon next to any `@Test` function
- The diamond turns green ✅ on success, red ❌ on failure

### Run Tests from Command Line
```bash
xcodebuild test -scheme MusicSheetsCopilot -destination 'platform=macOS'
```

### 📋 Future Tests (Optional)

**Metronome.swift (requires mocking):**
- ⏳ Time-based beat progression (needs `TimeProvider` protocol)
- ⏳ Auto-stop at end of piece (needs `TimeProvider` protocol)
- ⏳ Start/stop behavior (needs timer mocking)

**MIDIPlayer.swift (requires real MIDI files):**
- ⏳ Full MIDI parsing from base64 with fixture files
- ⏳ Complete note event extraction with real data

## Tips

1. **Run tests frequently** - After every code change
2. **Tests should be fast** - Each test runs in milliseconds
3. **Test one thing** - Each test should verify one specific behavior
4. **Use descriptive names** - Test names should explain what they verify
5. **Fix failing tests immediately** - Don't let them accumulate

## Resources

- [Swift Testing Documentation](https://developer.apple.com/documentation/testing)
- [WWDC 2024: Meet Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10179/)
