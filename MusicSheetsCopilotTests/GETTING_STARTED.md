# Getting Started with Testing

## 🚀 Quick Start (5 minutes)

### Step 1: Add Test Target in Xcode

1. Open `MusicSheetsCopilot.xcodeproj`
2. **File → New → Target...**
3. Choose **Unit Testing Bundle**
4. **Important:** Select **Swift Testing** framework (not XCTest)
5. Name: `MusicSheetsCopilotTests`
6. Click **Finish**

### Step 2: Link Test Files

The test files are already created in `MusicSheetsCopilotTests/`:
- `MetronomeTests.swift` - 18 tests for Metronome class
- `VerovioServiceTests.swift` - 15 tests for data processing
- `README.md` - Full documentation

**In Xcode:**
1. Drag `MusicSheetsCopilotTests` folder into your project
2. When prompted, check **"Create groups"** (not "Create folder references")
3. Select `MusicSheetsCopilotTests` as the target
4. Click **Add**

### Step 3: Run Your First Test! 🎉

Press **Cmd + U** to run all tests.

You should see:
```
✅ Test Suite 'MetronomeTests' passed
   ✅ MIDI note to solfege - Basic notes
   ✅ MIDI note to solfege - Chromatic notes
   ... (18 tests total)
   
✅ Test Suite 'VerovioServiceTests' passed
   ... (15 tests total)

Total: 33 tests passed in 0.05s
```

## 📊 What Gets Tested

### Already Covered (33 tests)

**Critical Bug Fix Verification:**
- ✅ Beat calculation at different playback rates (0.5x, 1.0x, 2.0x)
- ✅ Verifies the recent fix: beat uses original BPM, not adjusted BPM

**Metronome Logic:**
- ✅ Solfege conversion for all notes (including sharps/flats, octaves)
- ✅ Note event duration calculation
- ✅ Beat calculation at various BPMs (60, 120, 240)
- ✅ Beat wrapping at time signature boundaries
- ✅ Initial state validation

**Data Processing:**
- ✅ Staff key formatting
- ✅ Enabled staves filtering logic
- ✅ MIDI channel extraction
- ✅ Base64 encoding/decoding
- ✅ Note event sorting and filtering
- ✅ Time-based note lookup

## 🔧 How to Use Tests

### Run All Tests
```
Cmd + U
```

### Run One Suite
Click ◇ next to `@Suite("Metronome Tests")`

### Run One Test
Click ◇ next to `@Test("test name")`

### See Test Results
- Green ✅ = Passed
- Red ❌ = Failed (click to see details)
- Click test name to jump to code

## 💡 Example: Catching a Bug

**Imagine this scenario:**

You change beat calculation logic:
```swift
// Wrong: Uses adjusted BPM
let beatDuration = 60.0 / (bpm * Double(playbackRate))
```

Run tests (**Cmd + U**):
```
❌ Test 'Beat calculation respects original BPM with playback rate' failed
   Expected: 1
   Actual: 2
   
   The beat calculation is incorrect when using playback rate.
```

The test **immediately** tells you the bug! You can fix it before it reaches users.

## 📈 Next Steps

### Add More Tests (When Needed)

1. **Time-based tests** - Need to add `TimeProvider` protocol first
2. **Integration tests** - Load actual XML files and verify output
3. **UI tests** - Test button clicks and interactions

### Run Tests Automatically

**In CI/CD:**
```bash
xcodebuild test -scheme MusicSheetsCopilot -destination 'platform=macOS'
```

**Before each commit:**
```bash
# Add to .git/hooks/pre-commit
xcodebuild test -scheme MusicSheetsCopilot -destination 'platform=macOS' -quiet
```

## 🎯 Benefits You'll See

1. **Catch bugs immediately** - No more manual testing cycles
2. **Refactor with confidence** - Tests verify nothing breaks
3. **Document behavior** - Tests show how code should work
4. **Save time** - 33 tests run in < 0.1 seconds vs. minutes of manual testing
5. **Sleep better** - Know your code works before deploying

## 📚 Resources

- See `README.md` for detailed documentation
- [Swift Testing Documentation](https://developer.apple.com/documentation/testing)
- [WWDC 2024 Video](https://developer.apple.com/videos/play/wwdc2024/10179/)

---

**Ready?** Open Xcode and press **Cmd + U**! 🚀
