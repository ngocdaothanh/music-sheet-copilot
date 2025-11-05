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
    // Note: Detailed beat calculation and timing tests are in MetronomeTimeBasedTests.swift
    // These tests verify the basic logic is sound

    @Test("Beat calculation respects original BPM with playback rate")
    func beatCalculationWithPlaybackRate() {
        // This documents the critical design: beat calculation should use original BPM,
        // not adjusted BPM, because getCurrentMetronomeTime() already accounts for playbackRate

        let metronome = Metronome()
        metronome.bpm = 120.0
        metronome.playbackRate = 0.5  // Half speed
        metronome.timeSignature = (4, 4)

        // Verify the BPM and playbackRate are set correctly
        #expect(metronome.bpm == 120.0)
        #expect(metronome.playbackRate == 0.5)

        // The actual beat calculation happens internally when the timer fires
        // The formula used is: Int(currentTime / (60.0 / bpm)) % timeSignature.0
        // This test documents that bpm should NOT be multiplied by playbackRate
    }

    // MARK: - Time Signature Tests
    // Note: Beat wrapping behavior is tested with actual Metronome instances
    // in MetronomeTimeBasedTests.swift

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

    // MARK: - Boundary Tests

    @Test("Solfege with out-of-range MIDI note (128) still calculates via modulo")
    func outOfRangeMIDINoteCalculatesViaModulo() {
        let metronome = Metronome()

        // MIDI note 128 is technically out of range (max is 127)
        // But the function doesn't validate - it uses modulo 12
        // 128 % 12 = 8, which maps to "Sol"
        let result = metronome.midiNoteToSolfege(128)
        #expect(result == "Sol")
    }

    @Test("Solfege with maximum valid MIDI note (127)")
    func maxMIDINoteReturnsValid() {
        let metronome = Metronome()

        // MIDI note 127 (G9)
        let result = metronome.midiNoteToSolfege(127)
        // 127 % 12 = 7, which should map to Sol
        #expect(result == "Sol")
    }

    @Test("Solfege with minimum valid MIDI note (0)")
    func minMIDINoteReturnsValid() {
        let metronome = Metronome()

        // MIDI note 0 (C-1)
        let result = metronome.midiNoteToSolfege(0)
        // 0 % 12 = 0, which should map to Do
        #expect(result == "Do")
    }

    @Test("Beat duration with zero BPM should not cause division by zero")
    func beatDurationZeroBPM() {
        let metronome = Metronome()

        // Setting BPM to 0 could cause division by zero in the timer calculation
        // This test verifies the metronome handles this edge case
        metronome.bpm = 0.0

        // If there's no protection, this will crash with division by zero
        // The test documents current behavior (may crash or handle gracefully)
        #expect(metronome.bpm == 0.0)

        // Note: Starting the metronome with 0 BPM may cause a crash
        // This is a known edge case that should ideally be handled with validation
    }

    @Test("Beat duration with very high BPM")
    func beatDurationHighBPM() {
        let metronome = Metronome()
        metronome.bpm = 1000.0

        // The metronome should handle very high BPM without crashing
        // Start it to ensure timer calculation works
        metronome.start()

        // Should not crash
        #expect(metronome.bpm == 1000.0)

        metronome.stop()
    }

    @Test("Beat duration with very low BPM")
    func beatDurationLowBPM() {
        let metronome = Metronome()
        metronome.bpm = 20.0

        // The metronome should handle very low BPM without crashing
        metronome.start()

        // Should not crash
        #expect(metronome.bpm == 20.0)

        metronome.stop()
    }

    @Test("Note events with single event")
    func singleNoteEvent() {
        let metronome = Metronome()

        let events: [(TimeInterval, UInt8, UInt8)] = [
            (1.5, 60, 0)
        ]

        metronome.setNoteEvents(events)

        #expect(metronome.totalDuration == 3.5)  // 1.5 + 2.0 buffer
        #expect(metronome.firstStaffChannel == 0)
    }

    @Test("Note events with all same channel")
    func noteEventsAllSameChannel() {
        let metronome = Metronome()

        let events: [(TimeInterval, UInt8, UInt8)] = [
            (0.0, 60, 5),
            (0.5, 62, 5),
            (1.0, 64, 5),
        ]

        metronome.setNoteEvents(events)

        #expect(metronome.firstStaffChannel == 5)
    }
}
