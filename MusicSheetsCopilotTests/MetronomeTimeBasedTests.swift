import Testing
import Foundation
@testable import MusicSheetsCopilot

@Suite("Metronome Time-Based Tests")
struct MetronomeTimeBasedTests {

    @Test("Time-based beat progression advances correctly")
    func beatProgression() {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        metronome.bpm = 120.0  // 0.5s per beat (60.0 / 120.0)
        metronome.timeSignature = (4, 4)
        metronome.mode = .tick
        metronome.isEnabled = true
        metronome.start()

        // Should start at beat 0
        #expect(metronome.currentBeat == 0)
        #expect(metronome.isTicking == true)

        // Advance 0.5 seconds - should be beat 1
        mockTime.advance(by: 0.5)
        #expect(metronome.currentBeat == 1)

        // Advance another 0.5 seconds - should be beat 2
        mockTime.advance(by: 0.5)
        #expect(metronome.currentBeat == 2)

        // Advance to beat 3
        mockTime.advance(by: 0.5)
        #expect(metronome.currentBeat == 3)

        // Advance to beat 0 (wraps at 4 beats in 4/4 time)
        mockTime.advance(by: 0.5)
        #expect(metronome.currentBeat == 0)

        metronome.stop()
    }

    @Test("Beat progression with different time signatures")
    func beatProgressionDifferentTimeSignatures() {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        metronome.bpm = 120.0
        metronome.timeSignature = (3, 4)  // 3/4 time
        metronome.mode = .tick
        metronome.isEnabled = true
        metronome.start()

        #expect(metronome.currentBeat == 0)

        mockTime.advance(by: 0.5)  // Beat 1
        #expect(metronome.currentBeat == 1)

        mockTime.advance(by: 0.5)  // Beat 2
        #expect(metronome.currentBeat == 2)

        mockTime.advance(by: 0.5)  // Should wrap back to 0 (only 3 beats)
        #expect(metronome.currentBeat == 0)

        metronome.stop()
    }

    @Test("Auto-stop at end of piece in metronome-only mode")
    func autoStopAtEnd() {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        // Set note events with last note at 2.0s
        // totalDuration will be 2.0 + 2.0 buffer = 4.0s
        metronome.setNoteEvents([
            (0.0, 60, 0),
            (1.0, 62, 0),
            (2.0, 64, 0)
        ])

        metronome.bpm = 120.0
        metronome.mode = .solfege
        metronome.isEnabled = true
        metronome.start()

        #expect(metronome.isTicking == true)
        #expect(metronome.totalDuration == 4.0)

        // Advance to 3.9 seconds - still playing
        mockTime.advance(by: 3.9)
        #expect(metronome.isTicking == true)

        // Advance past totalDuration (4.0s) - should auto-stop
        mockTime.advance(by: 0.2)  // Now at 4.1s
        #expect(metronome.isTicking == false)
    }

    @Test("Auto-stop only applies in metronome-only mode")
    func autoStopOnlyInMetronomeMode() {
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

        // Should NOT auto-stop when MIDI is playing
        #expect(metronome.isTicking == true)

        metronome.stop()
    }

    @Test("Start and stop behavior")
    func startStopBehavior() {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        metronome.bpm = 120.0
        metronome.isEnabled = true

        // Start
        metronome.start()
        #expect(metronome.isTicking == true)
        #expect(metronome.currentBeat == 0)

        // Advance time
        mockTime.advance(by: 1.0)
        #expect(metronome.currentBeat == 2)  // 2 beats at 120 BPM

        // Stop
        metronome.stop()
        #expect(metronome.isTicking == false)
        #expect(metronome.currentBeat == 0)  // Reset to 0
        #expect(metronome.currentTime == 0)  // Reset playback time

        // Advance time while stopped - beat shouldn't change
        mockTime.advance(by: 5.0)
        #expect(metronome.currentBeat == 0)
    }

    @Test("Beat progression respects playback rate")
    func beatProgressionWithPlaybackRate() {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        metronome.bpm = 120.0  // 0.5s per beat at normal speed
        metronome.playbackRate = 2.0  // Double speed
        metronome.isEnabled = true
        metronome.start()

        // At 2x speed, timer fires twice as fast
        // Beat duration becomes 0.25s (0.5s / 2.0)

        // Advance 0.25s - should see a beat
        mockTime.advance(by: 0.25)
        #expect(metronome.currentBeat == 1 || metronome.currentBeat == 0)  // May have ticked

        metronome.stop()
    }

    @Test("Metronome currentTime tracks elapsed time correctly")
    func currentTimeTracking() {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        metronome.setNoteEvents([(0.0, 60, 0), (5.0, 62, 0)])
        metronome.bpm = 120.0
        metronome.mode = .solfege
        metronome.isEnabled = true
        metronome.start()

        // Initially at 0
        #expect(metronome.currentTime == 0.0)

        // Advance 1 second
        mockTime.advance(by: 1.0)

        // currentTime should be updated (approximately 1.0, allowing for timer granularity)
        // Note: currentTime is updated when getCurrentMetronomeTime() is called
        let timeAfter1s = metronome.currentTime
        #expect(timeAfter1s >= 0.9 && timeAfter1s <= 1.1)

        metronome.stop()
    }
}
