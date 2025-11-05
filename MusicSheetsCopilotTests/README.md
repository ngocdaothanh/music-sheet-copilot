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

## Test Coverage

### ✅ Currently Tested

**Metronome.swift:**
- ✅ `midiNoteToSolfege()` - All note conversions including sharps/flats and octaves
- ✅ `setNoteEvents()` - Duration calculation and channel caching
- ✅ Beat calculation logic - Different BPMs and time signatures
- ✅ **Critical bug fix verification** - Beat calculation with playback rate
- ✅ Initial state validation
- ✅ Mode enum existence

### 📋 To Be Added

**Metronome.swift (requires mocking):**
- ⏳ Time-based beat progression (needs `TimeProvider` protocol)
- ⏳ Auto-stop at end of piece (needs `TimeProvider` protocol)
- ⏳ Start/stop behavior (needs timer mocking)

**VerovioService.swift:**
- ⏳ `hideDisabledStaves()` regex correctness
- ⏳ `hideDisabledParts()` regex correctness
- ⏳ `extractAvailableParts()` parsing
- ⏳ Staff count extraction

**MIDIPlayer.swift:**
- ⏳ MIDI parsing from base64
- ⏳ Note event extraction
- ⏳ Channel extraction from status bytes

**Integration Tests:**
- ⏳ Load MusicXML file → Verovio rendering → MIDI generation
- ⏳ Staff filtering produces correct MIDI
- ⏳ First staff filtering (solfege mode)

## Test Results Interpretation

### Green Diamond ✅
Test passed! The code behaves as expected.

### Red Diamond ❌
Test failed. Click on the test to see:
- **Expected value** (what should happen)
- **Actual value** (what actually happened)
- **File and line number** where the assertion failed

### Example Output
```
Test "Beat calculation respects original BPM with playback rate" passed
✅ Expected: 1
✅ Actual: 1
```

## Writing New Tests

### Basic Test Structure
```swift
@Test("Description of what you're testing")
func testName() {
    // Arrange - Set up test data
    let metronome = Metronome()

    // Act - Perform the action
    let result = metronome.midiNoteToSolfege(60)

    // Assert - Verify the result
    #expect(result == "Do")
}
```

### Parameterized Tests (Test Multiple Cases)
```swift
@Test("Test name", arguments: [
    (input1, expected1),
    (input2, expected2),
])
func testWithParameters(input: Int, expected: String) {
    let result = someFunction(input)
    #expect(result == expected)
}
```

## Tips

1. **Run tests frequently** - After every code change
2. **Tests should be fast** - Each test runs in milliseconds
3. **Test one thing** - Each test should verify one specific behavior
4. **Use descriptive names** - Test names should explain what they verify
5. **Fix failing tests immediately** - Don't let them accumulate

## Next Steps

1. **Add tests for VerovioService** - Test XML parsing and filtering
2. **Add integration tests** - Test file loading end-to-end
3. **Add TimeProvider protocol** - Enable time-based testing
4. **Set up CI/CD** - Run tests automatically on every commit

## Resources

- [Swift Testing Documentation](https://developer.apple.com/documentation/testing)
- [WWDC 2024: Meet Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10179/)
