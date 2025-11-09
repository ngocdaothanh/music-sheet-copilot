import Testing
import Foundation
@testable import MusicSheetsCopilot

@Suite("Metronome Time-Based Tests")
struct MetronomeTimeBasedTests {

    @Test("Beat progression over time")
    func beatProgression() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        metronome.bpm = 120.0  // 2 beats per second
        metronome.mode = .tick
        metronome.isEnabled = true
        metronome.start()

        #expect(metronome.currentBeat == 0)

        // Advance 0.5 seconds - should be beat 1 (at 120 BPM, one beat = 0.5s)
        mockTime.advance(by: 0.5)
        // Small delay to allow timer callback to complete
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        #expect(metronome.currentBeat == 1)

        // Advance another 0.5 seconds - should be beat 2
        mockTime.advance(by: 0.5)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 2)

        // Advance to beat 3
        mockTime.advance(by: 0.5)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 3)

        // Advance to beat 0 (wraps at 4 beats in 4/4 time)
        mockTime.advance(by: 0.5)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 0)

        metronome.stop()
    }

    @Test("Beat progression with different time signatures")
    func beatProgressionDifferentTimeSignatures() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        metronome.bpm = 120.0
        metronome.timeSignature = (3, 4)  // 3/4 time
        metronome.mode = .tick
        metronome.isEnabled = true
        metronome.start()

        #expect(metronome.currentBeat == 0)

        mockTime.advance(by: 0.5)  // Beat 1
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 1)

        mockTime.advance(by: 0.5)  // Beat 2
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 2)

        mockTime.advance(by: 0.5)  // Should wrap back to 0 (only 3 beats)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 0)

        metronome.stop()
    }

    @Test("Auto-stop at end of piece in metronome-only mode")
    func autoStopAtEnd() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        // Set note events with explicit duration
        metronome.setNoteEvents([
            (0.0, 60, 0),
            (1.0, 62, 0),
            (2.0, 64, 0),
            (3.0, 65, 0)  // Last note at 3.0 seconds
        ])

        metronome.bpm = 120.0
        metronome.mode = .tick
        metronome.isEnabled = true
        metronome.start()

        #expect(metronome.isTicking == true)

        // Total duration should be around 3.0 seconds
        // Advance well past the end
        mockTime.advance(by: 5.0)
        // Wait long enough for multiple timer cycles to ensure check happens
        // Timer fires every 0.5s at 120 BPM, so wait 1 second to be safe
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Should have auto-stopped
        #expect(metronome.isTicking == false)
    }

    @Test("Auto-stop only happens in metronome-only mode, not when MIDI is playing")
    func autoStopOnlyInMetronomeMode() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)
        let midiPlayer = MIDIPlayer()

        metronome.midiPlayer = midiPlayer
        metronome.setNoteEvents([
            (0.0, 60, 0),
            (1.0, 62, 0)
        ])

        // Simulate MIDI playing
        midiPlayer.isPlaying = true

        metronome.bpm = 120.0
        metronome.mode = .solfege
        metronome.isEnabled = true
        metronome.start()

        // Advance past totalDuration
        mockTime.advance(by: 10.0)
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Should NOT auto-stop when MIDI is playing
        #expect(metronome.isTicking == true)

        metronome.stop()
    }

    @Test("Start and stop behavior")
    func startStopBehavior() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        metronome.bpm = 120.0
        metronome.isEnabled = true

        #expect(metronome.isTicking == false)

        metronome.start()
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.isTicking == true)

        metronome.stop()
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.isTicking == false)
        #expect(metronome.currentBeat == 0)
        #expect(metronome.currentTime == 0)
    }

    @Test("Beat progression with playback rate")
    func beatProgressionWithPlaybackRate() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        metronome.bpm = 120.0
        metronome.playbackRate = 2.0  // Double speed
        metronome.mode = .tick
        metronome.isEnabled = true
        metronome.start()

        // At 2x speed, effective BPM is 240 (4 beats per second, 0.25s per beat)
        mockTime.advance(by: 0.25)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 1)

        metronome.stop()
    }

    @Test("Metronome respects playbackRate when MIDI audio is disabled")
    func metronomeRespectsPlaybackRateWhenMIDIDisabled() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)
        let midiPlayer = MIDIPlayer()

        // Simulate MIDI audio being unloaded/disabled (no AVMIDIPlayer inside)
        midiPlayer.unload()

        // Provide some note events so metronome has a duration
        metronome.setNoteEvents([
            (0.0, 60, 0),
            (1.0, 62, 0)
        ])

        // Attach the (unloaded) midiPlayer to metronome to simulate the app wiring
        metronome.midiPlayer = midiPlayer

        // Set BPM and half-speed playback rate
        metronome.bpm = 120.0  // 0.5s per beat at normal speed
        metronome.playbackRate = 0.5  // half speed => 1.0s per beat
        metronome.mode = .tick
        metronome.isEnabled = true

        metronome.start()

        // Initially at beat 0
        #expect(metronome.currentBeat == 0)

        // Advance by 1.0s -> should move to beat 1 because playbackRate halves speed
        mockTime.advance(by: 1.0)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 1)

        metronome.stop()
    }

    @Test("Metronome currentTime tracks elapsed time correctly")
    func currentTimeTracking() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        metronome.setNoteEvents([(0.0, 60, 0), (5.0, 62, 0)])
        metronome.bpm = 120.0
        metronome.mode = .solfege
        metronome.isEnabled = true
        metronome.start()

        // Wait for metronome to fully start
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Access currentTime on MainActor to avoid priority inversion
        let initialTime = await MainActor.run { metronome.currentTime }
        #expect(initialTime == 0.0)

        // Advance 1 second
        mockTime.advance(by: 1.0)
        // In solfege mode, timer fires every 0.05s, wait longer for updates
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // currentTime should be updated (approximately 1.0, allowing for timer granularity)
        // Note: currentTime is updated when getCurrentMetronomeTime() is called
        let timeAfter1s = await MainActor.run { metronome.currentTime }
        #expect(timeAfter1s >= 0.9 && timeAfter1s <= 1.1)

        metronome.stop()
    }

    @Test("Metronome syncs to MIDI position when started during MIDI playback")
    func metronomeStartsSyncedToMIDIPosition() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)
        let midiPlayer = MIDIPlayer()

        // Setup MIDI player as if it's playing at a specific position
        // At 120 BPM in 4/4 time, each beat is 0.5 seconds
        // Position 1.5 seconds = 3rd beat (beat index 2 in 0-based counting)
        midiPlayer.isPlaying = true
        // Note: We can't directly set currentTime without loading MIDI,
        // so we'll mock the behavior by setting it after "loading"

        metronome.midiPlayer = midiPlayer
        metronome.bpm = 120.0  // 2 beats per second
        metronome.timeSignature = (4, 4)
        metronome.mode = .tick
        metronome.isEnabled = true

        // Simulate MIDI at 1.5 seconds (which should be beat 3, index 2)
        // We need to manually set this since we're not using a real MIDI file
        midiPlayer.currentTime = 1.5

        // Start metronome while MIDI is playing
        metronome.start()

        // Wait for initialization
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // The metronome should start at beat 3 (index 3)
        // At 1.5s with 120 BPM: beat = floor(1.5 / 0.5) % 4 = 3 % 4 = 3
        // After immediate tick, it advances to beat 0
        let currentBeat = await MainActor.run { metronome.currentBeat }
        #expect(currentBeat == 3)  // Should be at beat 3 after immediate tick

        metronome.stop()
    }

    @Test("Metronome syncs to different MIDI positions correctly")
    func metronomeStartsSyncedToDifferentPositions() async {
        let mockTime = MockTimeProvider()

        // Test different starting positions
        let testCases: [(midiTime: TimeInterval, expectedBeat: Int, description: String)] = [
            (0.0, 0, "Start of piece"),
            (0.5, 1, "After 1 beat"),
            (1.0, 2, "After 2 beats"),
            (1.5, 3, "After 3 beats"),
            (2.0, 0, "After 4 beats (wraps to 0)"),
            (2.5, 1, "After 5 beats (wraps to 1)"),
            (3.7, 3, "Mid-beat rounds down to beat 3"),
        ]

        for testCase in testCases {
            let metronome = Metronome(timeProvider: mockTime)
            let midiPlayer = MIDIPlayer()

            midiPlayer.isPlaying = true
            midiPlayer.currentTime = testCase.midiTime

            metronome.midiPlayer = midiPlayer
            metronome.bpm = 120.0  // 2 beats per second, 0.5s per beat
            metronome.timeSignature = (4, 4)
            metronome.mode = .tick
            metronome.isEnabled = true

            metronome.start()

            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

            let currentBeat = await MainActor.run { metronome.currentBeat }
            #expect(currentBeat == testCase.expectedBeat,
                   "\(testCase.description): Expected beat \(testCase.expectedBeat), got \(currentBeat)")

            metronome.stop()
        }
    }

    @Test("Metronome in counting mode syncs to MIDI position")
    func countingModeStartsSyncedToMIDIPosition() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)
        let midiPlayer = MIDIPlayer()

        midiPlayer.isPlaying = true
        midiPlayer.currentTime = 1.0  // 2 beats in (0.5s per beat at 120 BPM)

        metronome.midiPlayer = midiPlayer
        metronome.bpm = 120.0
        metronome.timeSignature = (4, 4)
        metronome.mode = .counting
        metronome.isEnabled = true

        metronome.start()

        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Should start at beat 2 (index 2), then after immediate count it advances to beat 3
        let currentBeat = await MainActor.run { metronome.currentBeat }
        #expect(currentBeat == 3)

        metronome.stop()
    }

    @Test("Metronome in solfege mode syncs to MIDI position")
    func solfegeModeStartsSyncedToMIDIPosition() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)
        let midiPlayer = MIDIPlayer()

        midiPlayer.isPlaying = true
        midiPlayer.currentTime = 0.75  // 1.5 beats in

        metronome.midiPlayer = midiPlayer
        metronome.bpm = 120.0
        metronome.timeSignature = (4, 4)
        metronome.mode = .solfege
        metronome.isEnabled = true

        metronome.start()

        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Should start at beat 1 (floor(0.75 / 0.5) = 1)
        let currentBeat = await MainActor.run { metronome.currentBeat }
        #expect(currentBeat == 1)

        metronome.stop()
    }

    @Test("Metronome starts from beat 0 when MIDI is not playing")
    func metronomeStartsFromZeroWhenMIDINotPlaying() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)
        let midiPlayer = MIDIPlayer()

        // MIDI is NOT playing
        midiPlayer.isPlaying = false
        midiPlayer.currentTime = 5.0  // Even though there's a position, it shouldn't be used

        metronome.midiPlayer = midiPlayer
        metronome.bpm = 120.0
        metronome.timeSignature = (4, 4)
        metronome.mode = .tick
        metronome.isEnabled = true

        metronome.start()

        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Should start from beat 0 since MIDI is not playing
        // After immediate tick for beat 0, currentBeat stays at 0 (showing the beat that was just played)
        let currentBeat = await MainActor.run { metronome.currentBeat }
        #expect(currentBeat == 0)

        metronome.stop()
    }

    @Test("Subdivision counting - eighth notes in metronome-only mode")
    func subdivisionCountingEighthNotes() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        metronome.bpm = 120.0  // 2 beats per second, 0.5s per beat
        metronome.subdivisions = 2  // Eighth notes
        metronome.timeSignature = (4, 4)
        metronome.mode = .counting
        metronome.isEnabled = true
        metronome.start()

        // Initial state: should be at beat 0, subdivision 0
        #expect(metronome.currentBeat == 0)

        // Advance 0.25 seconds (half a beat) - should be at beat 0, subdivision 1
        mockTime.advance(by: 0.25)
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        #expect(metronome.currentBeat == 0)

        // Advance another 0.25 seconds (full beat) - should be at beat 1, subdivision 0
        mockTime.advance(by: 0.25)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 1)

        // Advance 0.25 seconds - should be at beat 1, subdivision 1
        mockTime.advance(by: 0.25)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 1)

        metronome.stop()
    }

    @Test("Subdivision counting - sixteenth notes in metronome-only mode")
    func subdivisionCountingSixteenthNotes() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        metronome.bpm = 120.0  // 2 beats per second, 0.5s per beat
        metronome.subdivisions = 4  // Sixteenth notes
        metronome.timeSignature = (4, 4)
        metronome.mode = .counting
        metronome.isEnabled = true
        metronome.start()

        #expect(metronome.currentBeat == 0)

        // Advance 0.125 seconds (1/4 of a beat) - subdivision 1
        mockTime.advance(by: 0.125)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 0)

        // Advance 0.125 seconds - subdivision 2
        mockTime.advance(by: 0.125)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 0)

        // Advance 0.125 seconds - subdivision 3
        mockTime.advance(by: 0.125)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 0)

        // Advance 0.125 seconds - should wrap to beat 1, subdivision 0
        mockTime.advance(by: 0.125)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 1)

        metronome.stop()
    }

    @Test("Subdivision counting syncs to MIDI position - eighth notes")
    func subdivisionCountingSyncsToMIDIEighthNotes() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)
        let midiPlayer = MIDIPlayer()

        // MIDI is playing at 0.65 seconds = 1.3 beats
        // At subdivisions=2: 2.6 subdivisions (beat 1, subdivision 0 with some progress)
        midiPlayer.isPlaying = true
        midiPlayer.currentTime = 0.65

        metronome.midiPlayer = midiPlayer
        metronome.bpm = 120.0  // 0.5s per beat
        metronome.subdivisions = 2
        metronome.timeSignature = (4, 4)
        metronome.mode = .counting
        metronome.isEnabled = true

        metronome.start()

        // Give more time for the metronome to initialize
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Should be at beat 1 (floor(0.65 / 0.5) = 1)
        let currentBeat = await MainActor.run { metronome.currentBeat }
        #expect(currentBeat == 1)

        metronome.stop()
    }

    @Test("Subdivision counting syncs to MIDI position - sixteenth notes")
    func subdivisionCountingSyncsToMIDISixteenthNotes() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)
        let midiPlayer = MIDIPlayer()

        // MIDI is playing at 0.625 seconds = 1.25 beats
        // At subdivisions=4: 5 subdivisions (beat 1, subdivision 1)
        midiPlayer.isPlaying = true
        midiPlayer.currentTime = 0.625

        metronome.midiPlayer = midiPlayer
        metronome.bpm = 120.0  // 0.5s per beat
        metronome.subdivisions = 4
        metronome.timeSignature = (4, 4)
        metronome.mode = .counting
        metronome.isEnabled = true

        metronome.start()

        try? await Task.sleep(nanoseconds: 10_000_000)

        // Should be at beat 1 (floor(0.625 / 0.5) = 1)
        let currentBeat = await MainActor.run { metronome.currentBeat }
        #expect(currentBeat == 1)

        metronome.stop()
    }

    @Test("Subdivision counting wraps correctly at measure boundary")
    func subdivisionCountingWrapsAtMeasureBoundary() async {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        metronome.bpm = 120.0  // 0.5s per beat
        metronome.subdivisions = 2  // Eighth notes
        metronome.timeSignature = (3, 4)  // 3/4 time
        metronome.mode = .counting
        metronome.isEnabled = true
        metronome.start()

        #expect(metronome.currentBeat == 0)

        // Advance through all beats in 3/4 time with eighth notes
        // Beat 0, subdivision 0 (start)

        // Beat 0, subdivision 1
        mockTime.advance(by: 0.25)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 0)

        // Beat 1, subdivision 0
        mockTime.advance(by: 0.25)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 1)

        // Beat 1, subdivision 1
        mockTime.advance(by: 0.25)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 1)

        // Beat 2, subdivision 0
        mockTime.advance(by: 0.25)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 2)

        // Beat 2, subdivision 1
        mockTime.advance(by: 0.25)
        try? await Task.sleep(nanoseconds: 10_000_000)
                #expect(metronome.currentBeat == 2)

        // Should wrap back to beat 0 (3/4 time has only 3 beats)
        mockTime.advance(by: 0.25)
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(metronome.currentBeat == 0)

        metronome.stop()
    }
}
