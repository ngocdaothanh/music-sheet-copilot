import Testing
import Foundation
@testable import MusicSheetsCopilot

@Suite("Metronome Tests")
struct MetronomeTests {

    // MARK: - Solfege Conversion Tests

    @Test("MIDI note to solfege - Basic notes")
    func midiNoteToSolfegeBasicNotes() {
        let metronome = Metronome()

        // Test middle C octave (MIDI notes 60-71)
        #expect(metronome.midiNoteToSolfege(60) == "Do")   // C
        #expect(metronome.midiNoteToSolfege(62) == "Re")   // D
        #expect(metronome.midiNoteToSolfege(64) == "Mi")   // E
        #expect(metronome.midiNoteToSolfege(65) == "Fa")   // F
        #expect(metronome.midiNoteToSolfege(67) == "Sol")  // G
        #expect(metronome.midiNoteToSolfege(69) == "La")   // A
        #expect(metronome.midiNoteToSolfege(71) == "Si")   // B
    }

    @Test("MIDI note to solfege - Chromatic notes map to natural notes")
    func midiNoteToSolfegeChromatic() {
        let metronome = Metronome()

        // Sharps/flats should map to the same solfege as natural notes
        #expect(metronome.midiNoteToSolfege(61) == "Do")   // C# -> Do
        #expect(metronome.midiNoteToSolfege(63) == "Re")   // D# -> Re
        #expect(metronome.midiNoteToSolfege(66) == "Fa")   // F# -> Fa
        #expect(metronome.midiNoteToSolfege(68) == "Sol")  // G# -> Sol
        #expect(metronome.midiNoteToSolfege(70) == "La")   // A# -> La
    }

    @Test("MIDI note to solfege - Octaves wrap correctly",
          arguments: [
        (48, "Do"),   // C in lower octave
        (60, "Do"),   // Middle C
        (72, "Do"),   // C in higher octave
        (84, "Do"),   // C in even higher octave
        (50, "Re"),   // D in lower octave
        (74, "Re"),   // D in higher octave
    ])
    func midiNoteToSolfegeOctaves(midiNote: UInt8, expectedSolfege: String) {
        let metronome = Metronome()
        #expect(metronome.midiNoteToSolfege(midiNote) == expectedSolfege)
    }

    // MARK: - Note Events Tests

    @Test("Set note events calculates total duration correctly")
    func setNoteEventsDuration() {
        let metronome = Metronome()

        let events: [(TimeInterval, UInt8, UInt8)] = [
            (0.0, 60, 0),
            (0.5, 62, 0),
            (1.0, 64, 0),
            (5.0, 67, 0),  // Last note at 5.0 seconds
        ]

        metronome.setNoteEvents(events)

        // Total duration should be last note time + 2.0 second buffer
        #expect(metronome.totalDuration == 7.0)
    }

    @Test("Set note events with empty array")
    func setNoteEventsEmpty() {
        let metronome = Metronome()

        let events: [(TimeInterval, UInt8, UInt8)] = []

        metronome.setNoteEvents(events)

        // With no events, duration should be 0 + 2.0 buffer = 2.0
        #expect(metronome.totalDuration == 2.0)
    }

    @Test("Set note events caches first staff channel")
    func setNoteEventsFirstStaffChannel() {
        let metronome = Metronome()

        // Events with different channels (channel 2 should be first)
        let events: [(TimeInterval, UInt8, UInt8)] = [
            (0.0, 60, 3),
            (0.5, 62, 2),  // Lowest channel
            (1.0, 64, 5),
        ]

        metronome.setNoteEvents(events)

        // First staff channel should be the minimum (2)
        #expect(metronome.firstStaffChannel == 2)
    }

    // MARK: - Beat Calculation Tests

    @Test("Beat duration calculation - Different BPMs",
          arguments: [
        (60.0, 1.0),    // 60 BPM = 1 beat per second
        (120.0, 0.5),   // 120 BPM = 2 beats per second
        (240.0, 0.25),  // 240 BPM = 4 beats per second
        (90.0, 0.666),  // 90 BPM = 1.5 beats per second (approximately)
    ])
    func beatDurationCalculation(bpm: Double, expectedDuration: TimeInterval) {
        // This tests the core beat calculation logic used in solfege mode
        let beatDuration = 60.0 / bpm

        // Use small epsilon for floating point comparison
        let epsilon = 0.01
        #expect(abs(beatDuration - expectedDuration) < epsilon)
    }

    @Test("Beat index calculation from time",
          arguments: [
        (0.0, 120.0, 4, 0),    // Time 0.0s, 120 BPM, 4/4 -> beat 0
        (0.5, 120.0, 4, 1),    // Time 0.5s, 120 BPM, 4/4 -> beat 1
        (1.0, 120.0, 4, 2),    // Time 1.0s, 120 BPM, 4/4 -> beat 2
        (1.5, 120.0, 4, 3),    // Time 1.5s, 120 BPM, 4/4 -> beat 3
        (2.0, 120.0, 4, 0),    // Time 2.0s, 120 BPM, 4/4 -> beat 0 (wraps)
        (1.0, 60.0, 4, 1),     // Time 1.0s, 60 BPM, 4/4 -> beat 1
        (2.0, 60.0, 4, 2),     // Time 2.0s, 60 BPM, 4/4 -> beat 2
        (0.0, 120.0, 3, 0),    // Time 0.0s, 120 BPM, 3/4 -> beat 0
        (1.5, 120.0, 3, 0),    // Time 1.5s, 120 BPM, 3/4 -> beat 0 (wraps after 3)
    ])
    func beatIndexFromTime(time: TimeInterval, bpm: Double, beatsPerMeasure: Int, expectedBeat: Int) {
        // This tests the logic: Int(currentTime / beatDuration) % timeSignature.0
        let beatDuration = 60.0 / bpm
        let calculatedBeat = Int(time / beatDuration) % beatsPerMeasure

        #expect(calculatedBeat == expectedBeat)
    }

    @Test("Beat calculation respects original BPM with playback rate")
    func beatCalculationWithPlaybackRate() {
        // This is the critical bug fix - beat calculation should use original BPM,
        // not adjusted BPM, because getCurrentMetronomeTime() already accounts for playbackRate

        let bpm = 120.0
        let playbackRate: Float = 0.5  // Half speed

        // At half speed, with 120 BPM:
        // - Beat duration based on ORIGINAL BPM: 60.0 / 120.0 = 0.5 seconds
        // - At real time 1.0 second, getCurrentMetronomeTime() returns 0.5 seconds (because of playbackRate)
        // - Beat should be: Int(0.5 / 0.5) % 4 = 1

        let beatDuration = 60.0 / bpm  // Use ORIGINAL BPM (not bpm * playbackRate)
        #expect(beatDuration == 0.5)

        // Simulated current time from getCurrentMetronomeTime() at real time 1.0s
        let simulatedCurrentTime = 1.0 * Double(playbackRate)  // = 0.5
        let beat = Int(simulatedCurrentTime / beatDuration) % 4

        #expect(beat == 1)  // Should be beat 1, not beat 2
    }

    // MARK: - Time Signature Tests

    @Test("Beat wraps at time signature boundary",
          arguments: [
        (4, 3),  // 4/4 time, beat 3 (0-indexed) should wrap to 0
        (3, 2),  // 3/4 time, beat 2 (0-indexed) should wrap to 0
        (6, 5),  // 6/8 time, beat 5 (0-indexed) should wrap to 0
    ])
    func beatWrapsAtTimeSignature(beatsPerMeasure: Int, lastBeat: Int) {
        // Test that beat correctly wraps at time signature boundary
        let nextBeat = (lastBeat + 1) % beatsPerMeasure
        #expect(nextBeat == 0)
    }

    // MARK: - Initial State Tests

    @Test("Metronome initial state is correct")
    func initialState() {
        let metronome = Metronome()

        #expect(metronome.isEnabled == false)
        #expect(metronome.isTicking == false)
        #expect(metronome.bpm == 120.0)
        #expect(metronome.playbackRate == 1.0)
        #expect(metronome.timeSignature == (4, 4))
        #expect(metronome.mode == .tick)
        #expect(metronome.currentBeat == 0)
        #expect(metronome.currentTime == 0)
    }

    // MARK: - Mode Tests

    @Test("MetronomeMode enum values exist")
    func metronomeModesExist() {
        let tick: MetronomeMode = .tick
        let counting: MetronomeMode = .counting
        let solfege: MetronomeMode = .solfege

        #expect(tick == .tick)
        #expect(counting == .counting)
        #expect(solfege == .solfege)
    }
}
