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
}
