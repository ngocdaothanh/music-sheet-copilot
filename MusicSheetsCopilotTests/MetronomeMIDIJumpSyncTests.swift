import Testing
import Foundation
@testable import MusicSheetsCopilot

@Suite("Metronome/MIDI Jump Sync Tests")
struct MetronomeMIDIJumpSyncTests {

    @Test("Metronome continues after MIDI note jump")
    func metronomeContinuesAfterMIDINoteJump() async {
        let midiPlayer = MIDIPlayer()
        let metronome = Metronome()
        metronome.midiPlayer = midiPlayer
        metronome.isEnabled = true
        metronome.bpm = 120.0

        // Simulate MIDI is playing
        midiPlayer.duration = 10.0
        midiPlayer.currentTime = 1.0
        midiPlayer.isPlaying = true
        metronome.start()
        #expect(metronome.isTicking)

        // Simulate user clicks a note to jump to measure at 5.0s
        let jumpTime: TimeInterval = 5.0
        let wasMIDIPlaying = midiPlayer.isPlaying
        midiPlayer.seek(to: jumpTime)
        if wasMIDIPlaying { midiPlayer.play() }
        metronome.seek(to: jumpTime)
        if wasMIDIPlaying && metronome.isEnabled { metronome.start() }

        // Wait for main queue to process async update
        await Task.yield()

        // Metronome should still be ticking
        #expect(metronome.isTicking)
    }

    @Test("Metronome stops when MIDI ends")
    func metronomeStopsWhenMIDIEnds() {
        let midiPlayer = MIDIPlayer()
        let metronome = Metronome()
        metronome.midiPlayer = midiPlayer
        metronome.isEnabled = true
        metronome.bpm = 120.0

        midiPlayer.duration = 10.0
        midiPlayer.currentTime = 10.0
        midiPlayer.isPlaying = false
        metronome.start()
        // Simulate .onChange handler logic
        let atEnd = midiPlayer.duration > 0 && abs(midiPlayer.currentTime - midiPlayer.duration) < 0.1
        if !midiPlayer.isPlaying && metronome.isTicking && atEnd {
            metronome.stop()
        }
        #expect(!metronome.isTicking)
    }
}
