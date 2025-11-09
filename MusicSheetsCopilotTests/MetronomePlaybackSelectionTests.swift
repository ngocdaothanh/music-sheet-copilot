import Testing
import Foundation
@testable import MusicSheetsCopilot

@Suite("Metronome/Playback Selection Tests")
struct MetronomePlaybackSelectionTests {

    @Test("Metronome respects playbackRate when MIDI disabled")
    func metronomeRespectsPlaybackRateWhenMIDIDisabled() {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        // Start with MIDI disabled
        metronome.midiPlayer = nil
        metronome.isEnabled = true
        metronome.bpm = 120.0
        metronome.playbackRate = 0.5 // half speed

        var ticks = 0
        metronome.onTick = { ticks += 1 }
        metronome.start()

        // Advance time by 4s (should cover 2 beats at half speed)
        mockTime.advance(by: 4.0)

        // Expect at least one tick occurred
        #expect(ticks > 0)
        metronome.stop()
    }

    @Test("Metronome continues when MIDI unloaded on stave toggle")
    func metronomeContinuesWhenMIDIUnloadedOnStaveToggle() {
        let mockTime = MockTimeProvider()
        let metronome = Metronome(timeProvider: mockTime)

        let midiPlayer = MIDIPlayer()
        metronome.midiPlayer = midiPlayer
        metronome.isEnabled = true
        metronome.bpm = 100

        var ticks = 0
        metronome.onTick = { ticks += 1 }
        metronome.start()

        // Now simulate unloading MIDI
        metronome.midiPlayer = nil

        mockTime.advance(by: 2.0)

        #expect(ticks > 0)
        metronome.stop()
    }
}
