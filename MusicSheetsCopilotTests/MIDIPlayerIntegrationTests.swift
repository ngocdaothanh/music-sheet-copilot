import Testing
import Foundation
import AVFoundation
@testable import MusicSheetsCopilot

/// Integration tests for MIDIPlayer with real MIDI data
@Suite("MIDI Player Integration Tests")
struct MIDIPlayerIntegrationTests {

    // MARK: - Full Workflow Tests

    @Test("Load MIDI from VerovioService and extract note events")
    func fullMIDIWorkflow() throws {
        let service = VerovioService()
        let player = MIDIPlayer()

        // Load a demo file
        guard let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml") else {
            Issue.record("Demo file not found")
            return
        }

        let data = try Data(contentsOf: url)
        _ = try service.renderAllPages(data: data)

        // Get MIDI
        let midiString = service.getMIDI()
        guard let midiData = Data(base64Encoded: midiString) else {
            Issue.record("Failed to decode MIDI")
            return
        }

        // Load into player
        try player.loadMIDI(data: midiData)

        // Verify results
        #expect(player.duration > 0)
        #expect(player.noteEvents.count > 0)
        #expect(player.timeSignature.0 > 0)
        #expect(player.timeSignature.1 > 0)
    }

    @Test("Playback rate affects MIDI playback speed")
    func playbackRateAffectsMIDI() throws {
        let service = VerovioService()
        let player = MIDIPlayer()

        guard let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml") else {
            Issue.record("Demo file not found")
            return
        }

        let data = try Data(contentsOf: url)
        _ = try service.renderAllPages(data: data)

        let midiString = service.getMIDI()
        guard let midiData = Data(base64Encoded: midiString) else {
            Issue.record("Failed to decode MIDI")
            return
        }

        try player.loadMIDI(data: midiData)

        // Set different playback rates
        player.playbackRate = 2.0
        #expect(player.playbackRate == 2.0)

        player.playbackRate = 0.5
        #expect(player.playbackRate == 0.5)
    }

    // MARK: - Note Event Filtering Tests

    @Test("Filtered MIDI has fewer or equal notes than full MIDI")
    func filteredMIDINoteCounts() throws {
        let service = VerovioService()
        let fullPlayer = MIDIPlayer()
        let filteredPlayer = MIDIPlayer()

        guard let url = Bundle.main.url(forResource: "fur_elise", withExtension: "xml") else {
            Issue.record("Demo file not found")
            return
        }

        let data = try Data(contentsOf: url)
        _ = try service.renderAllPages(data: data)

        // Full MIDI
        let fullMIDI = service.getMIDI()
        guard let fullData = Data(base64Encoded: fullMIDI) else {
            Issue.record("Failed to decode full MIDI")
            return
        }
        try fullPlayer.loadMIDI(data: fullData)

        // Filtered MIDI (first staff only)
        guard let filteredMIDI = service.getMIDIForFirstStaff() else {
            Issue.record("Failed to get filtered MIDI")
            return
        }
        guard let filteredData = Data(base64Encoded: filteredMIDI) else {
            Issue.record("Failed to decode filtered MIDI")
            return
        }
        try filteredPlayer.loadMIDI(data: filteredData)

        #expect(filteredPlayer.noteEvents.count <= fullPlayer.noteEvents.count)
        #expect(filteredPlayer.noteEvents.count > 0)
    }

    // MARK: - Channel Tests

    @Test("First staff channel is identified correctly")
    func firstStaffChannel() throws {
        let service = VerovioService()
        let player = MIDIPlayer()

        guard let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml") else {
            Issue.record("Demo file not found")
            return
        }

        let data = try Data(contentsOf: url)
        _ = try service.renderAllPages(data: data)

        let midiString = service.getMIDI()
        guard let midiData = Data(base64Encoded: midiString) else {
            Issue.record("Failed to decode MIDI")
            return
        }

        try player.loadMIDI(data: midiData)

        // First staff channel should be 0 or the minimum channel found
        if !player.noteEvents.isEmpty {
            let minChannel = player.noteEvents.map { $0.channel }.min() ?? 0
            #expect(player.firstStaffChannel == minChannel)
        }
    }

    // MARK: - Seek and Position Tests

    @Test("Seek clamps time to valid range")
    func seekClamping() throws {
        let service = VerovioService()
        let player = MIDIPlayer()

        guard let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml") else {
            Issue.record("Demo file not found")
            return
        }

        let data = try Data(contentsOf: url)
        _ = try service.renderAllPages(data: data)

        let midiString = service.getMIDI()
        guard let midiData = Data(base64Encoded: midiString) else {
            Issue.record("Failed to decode MIDI")
            return
        }

        try player.loadMIDI(data: midiData)

        // Test seeking to negative time (should clamp to 0)
        player.seek(to: -5.0)
        #expect(player.currentTime >= 0)

        // Test seeking beyond duration (should clamp to duration)
        player.seek(to: player.duration + 100)
        #expect(player.currentTime <= player.duration)
    }

    @Test("Get notes at specific time returns correct notes")
    func getNotesAtTime() throws {
        let player = MIDIPlayer()

        // Manually create note events for testing
        player.noteEvents = [
            (0.0, 60, 0),   // C at 0s
            (0.5, 62, 0),   // D at 0.5s
            (1.0, 64, 0),   // E at 1s
            (1.5, 65, 0),   // F at 1.5s
        ]

        // Test exact time
        let notesAt0 = player.getNotesAtTime(0.0)
        #expect(notesAt0.contains(60))

        // Test time within tolerance (0.1s)
        let notesNear0 = player.getNotesAtTime(0.05)
        #expect(notesNear0.contains(60))

        // Test time at 1 second
        let notesAt1 = player.getNotesAtTime(1.0)
        #expect(notesAt1.contains(64))
    }

    // MARK: - Time Signature Parsing Tests

    @Test("Time signature is extracted from MIDI")
    func timeSignatureExtraction() throws {
        let service = VerovioService()
        let player = MIDIPlayer()

        guard let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml") else {
            Issue.record("Demo file not found")
            return
        }

        let data = try Data(contentsOf: url)
        _ = try service.renderAllPages(data: data)

        let midiString = service.getMIDI()
        guard let midiData = Data(base64Encoded: midiString) else {
            Issue.record("Failed to decode MIDI")
            return
        }

        try player.loadMIDI(data: midiData)

        // Twinkle Twinkle is in 4/4 time
        #expect(player.timeSignature.0 > 0)
        #expect(player.timeSignature.1 > 0)
    }

    // MARK: - State Management Tests

    @Test("Stop resets player to beginning")
    func stopResetsPosition() throws {
        let service = VerovioService()
        let player = MIDIPlayer()

        guard let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml") else {
            Issue.record("Demo file not found")
            return
        }

        let data = try Data(contentsOf: url)
        _ = try service.renderAllPages(data: data)

        let midiString = service.getMIDI()
        guard let midiData = Data(base64Encoded: midiString) else {
            Issue.record("Failed to decode MIDI")
            return
        }

        try player.loadMIDI(data: midiData)

        // Seek to middle
        player.seek(to: player.duration / 2)

        // Stop should reset
        player.stop()

        #expect(player.currentTime == 0)
        #expect(player.isPlaying == false)
    }

    @Test("Loading new MIDI stops current playback")
    func loadingStopsPlayback() throws {
        let service = VerovioService()
        let player = MIDIPlayer()

        guard let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml") else {
            Issue.record("Demo file not found")
            return
        }

        let data = try Data(contentsOf: url)
        _ = try service.renderAllPages(data: data)

        let midiString = service.getMIDI()
        guard let midiData = Data(base64Encoded: midiString) else {
            Issue.record("Failed to decode MIDI")
            return
        }

        try player.loadMIDI(data: midiData)

        // Load again (should stop any playback first)
        try player.loadMIDI(data: midiData)

        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
    }
}
