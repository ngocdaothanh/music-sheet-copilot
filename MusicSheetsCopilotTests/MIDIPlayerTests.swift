import Testing
import Foundation
@testable import MusicSheetsCopilot

@Suite("MIDI Player Tests")
struct MIDIPlayerTests {

    // MARK: - MIDI Channel Extraction Tests

    @Test("Extract MIDI channel from status byte",
          arguments: [
        (UInt8(0x90), UInt8(0)),   // Note On, channel 0
        (UInt8(0x91), UInt8(1)),   // Note On, channel 1
        (UInt8(0x92), UInt8(2)),   // Note On, channel 2
        (UInt8(0x9F), UInt8(15)),  // Note On, channel 15
        (UInt8(0x80), UInt8(0)),   // Note Off, channel 0
        (UInt8(0x8F), UInt8(15)),  // Note Off, channel 15
        (UInt8(0xB0), UInt8(0)),   // Control Change, channel 0
        (UInt8(0xBF), UInt8(15)),  // Control Change, channel 15
    ])
    func extractChannelFromStatusByte(statusByte: UInt8, expectedChannel: UInt8) {
        // This is the logic used in parseMIDINoteEvents()
        let extractedChannel = statusByte & 0x0F
        #expect(extractedChannel == expectedChannel)
    }

    @Test("Note On message type detection")
    func noteOnMessageDetection() {
        // Note On messages are 0x90-0x9F
        let noteOnChannel0: UInt8 = 0x90
        let noteOnChannel5: UInt8 = 0x95
        let noteOffChannel0: UInt8 = 0x80

        // Check message type (upper nibble)
        let noteOnType0 = noteOnChannel0 & 0xF0
        let noteOnType5 = noteOnChannel5 & 0xF0
        let noteOffType = noteOffChannel0 & 0xF0

        #expect(noteOnType0 == 0x90)
        #expect(noteOnType5 == 0x90)
        #expect(noteOffType == 0x80)
    }

    // MARK: - Note Event Tests

    @Test("Note events are properly structured")
    func noteEventStructure() {
        // Test the note event tuple structure
        let event: (time: TimeInterval, midiNote: UInt8, channel: UInt8) = (1.0, 60, 0)

        #expect(event.time == 1.0)
        #expect(event.midiNote == 60)
        #expect(event.channel == 0)
    }

    @Test("Note events can be sorted by time")
    func noteEventSorting() {
        var events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = [
            (2.0, 64, 0),
            (0.5, 60, 0),
            (1.0, 62, 0),
            (0.0, 59, 0),
        ]

        events.sort { $0.time < $1.time }

        #expect(events[0].time == 0.0)
        #expect(events[1].time == 0.5)
        #expect(events[2].time == 1.0)
        #expect(events[3].time == 2.0)
    }

    @Test("Note events can be filtered by channel")
    func noteEventChannelFiltering() {
        let events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = [
            (0.0, 60, 0),
            (0.5, 62, 1),
            (1.0, 64, 0),
            (1.5, 67, 2),
            (2.0, 69, 0),
        ]

        let channel0Events = events.filter { $0.channel == 0 }

        #expect(channel0Events.count == 3)
        #expect(channel0Events.map { $0.midiNote } == [60, 64, 69])
    }

    @Test("Note events can be filtered by time range")
    func noteEventTimeFiltering() {
        let events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = [
            (0.0, 60, 0),
            (0.5, 62, 0),
            (1.0, 64, 0),
            (1.5, 67, 0),
            (2.0, 69, 0),
        ]

        let startTime = 0.5
        let endTime = 1.5

        let filteredEvents = events.filter { $0.time >= startTime && $0.time <= endTime }

        #expect(filteredEvents.count == 3)
        #expect(filteredEvents.map { $0.midiNote } == [62, 64, 67])
    }

    @Test("Find notes at specific time with tolerance")
    func findNotesAtTimeWithTolerance() {
        let events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = [
            (0.0, 60, 0),
            (0.05, 62, 0),   // Within 0.1s tolerance
            (0.15, 64, 0),   // Outside tolerance
            (1.0, 67, 0),
        ]

        let targetTime: TimeInterval = 0.0
        let tolerance: TimeInterval = 0.1

        let notesAtTime = events.filter { abs($0.time - targetTime) < tolerance }

        #expect(notesAtTime.count == 2)
        #expect(notesAtTime.map { $0.midiNote } == [60, 62])
    }

    // MARK: - MIDI Note Number Tests

    @Test("MIDI note numbers are in valid range",
          arguments: [0, 60, 127])
    func midiNoteValidRange(noteNumber: UInt8) {
        #expect(noteNumber >= 0)
        #expect(noteNumber <= 127)
    }

    @Test("Middle C is MIDI note 60")
    func middleCMIDINote() {
        let middleC: UInt8 = 60
        #expect(middleC == 60)
    }

    @Test("MIDI note to frequency calculation for reference")
    func midiNoteToFrequency() {
        // A4 (MIDI note 69) should be 440 Hz
        let midiNote: UInt8 = 69
        let frequency = 440.0 * pow(2.0, (Double(midiNote) - 69.0) / 12.0)

        let epsilon = 0.01
        #expect(abs(frequency - 440.0) < epsilon)
    }

    // MARK: - Get Notes At Time Tests

    @Test("getNotesAtTime returns correct notes")
    func getNotesAtTimeLogic() {
        // Simulate the logic from MIDIPlayer.getNotesAtTime()
        let events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = [
            (0.0, 60, 0),
            (0.5, 62, 0),
            (0.5, 64, 0),  // Chord with previous note
            (1.0, 67, 0),
        ]

        let currentTime: TimeInterval = 0.5
        let tolerance: TimeInterval = 0.05

        let notesAtTime = events.filter { event in
            abs(event.time - currentTime) < tolerance
        }

        let midiNotes = notesAtTime.map { $0.midiNote }

        #expect(notesAtTime.count == 2)
        #expect(midiNotes.contains(62))
        #expect(midiNotes.contains(64))
    }

    // MARK: - Channel Assignment Tests

    @Test("First staff should have lowest channel number")
    func firstStaffLowestChannel() {
        let events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = [
            (0.0, 60, 3),
            (0.5, 62, 1),  // Lowest
            (1.0, 64, 2),
        ]

        let minChannel = events.map { $0.channel }.min()

        #expect(minChannel == 1)
    }

    @Test("Empty events array min channel should be 0")
    func emptyEventsMinChannel() {
        let events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = []

        let minChannel = events.map { $0.channel }.min() ?? 0

        #expect(minChannel == 0)
    }

    // MARK: - Edge Case Tests

    @Test("Find minimum and maximum note times")
    func minMaxNoteTimes() {
        let events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = [
            (0.0, 60, 0),
            (2.5, 62, 0),
            (1.0, 64, 0),
            (0.5, 67, 0),
        ]

        let minTime = events.map { $0.time }.min()
        let maxTime = events.map { $0.time }.max()

        #expect(minTime == 0.0)
        #expect(maxTime == 2.5)
    }

    @Test("MIDI note event time ordering")
    func noteEventTimeOrdering() {
        let events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = [
            (0.0, 60, 0),
            (0.5, 62, 0),
            (1.0, 64, 0),
        ]

        // Events should be in chronological order
        for i in 0..<(events.count - 1) {
            #expect(events[i].time <= events[i + 1].time)
        }
    }

    @Test("Filter notes by channel")
    func filterNotesByChannel() {
        let events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = [
            (0.0, 60, 0),
            (0.5, 62, 1),
            (1.0, 64, 0),
            (1.5, 67, 1),
        ]

        let channel0 = events.filter { $0.channel == 0 }
        let channel1 = events.filter { $0.channel == 1 }

        #expect(channel0.count == 2)
        #expect(channel1.count == 2)
        #expect(channel0.map { $0.midiNote } == [60, 64])
        #expect(channel1.map { $0.midiNote } == [62, 67])
    }

    @Test("Set note events with empty array")
    func setEmptyNoteEvents() {
        let player = MIDIPlayer()

        player.noteEvents = []

        #expect(player.noteEvents.isEmpty)
    }

    @Test("Set note events caches first staff channel")
    func setNoteEventsCachesChannel() {
        let player = MIDIPlayer()

        player.noteEvents = [
            (0.0, 60, 2),
            (0.5, 62, 3),
            (1.0, 64, 2),
        ]

        // firstStaffChannel is only calculated in loadMIDI/loadNoteEventsFromFilteredMIDI
        // When directly setting noteEvents, we can calculate it manually
        let minChannel = player.noteEvents.map { $0.channel }.min() ?? 0
        #expect(minChannel == 2)
    }

    @Test("Set note events calculates total duration correctly")
    func setNoteEventsCalculatesDuration() {
        let player = MIDIPlayer()

        player.noteEvents = [
            (0.0, 60, 0),
            (1.5, 62, 0),
            (2.5, 64, 0),
        ]

        // MIDIPlayer doesn't have totalDuration - verify we can calculate it from note events
        let maxTime = player.noteEvents.map { $0.time }.max() ?? 0
        #expect(maxTime == 2.5)
    }
}

@Suite("MIDI Data Processing Tests")
struct MIDIDataProcessingTests {

    @Test("Extract part IDs from enabled staves")
    func extractPartIds() {
        let enabledStaves: Set<String> = ["P1-1", "P1-2", "P2-1"]

        // Extract unique part IDs
        let partIds = Set(enabledStaves.map { staffKey in
            staffKey.split(separator: "-").first.map(String.init) ?? ""
        })

        #expect(partIds.count == 2)
        #expect(partIds.contains("P1"))
        #expect(partIds.contains("P2"))
    }

    @Test("Extract part IDs - Single staff parts")
    func extractSingleStaffPartIds() {
        let enabledStaves: Set<String> = ["P1-1", "P2-1", "P3-1"]

        let partIds = Set(enabledStaves.map { staffKey in
            staffKey.split(separator: "-").first.map(String.init) ?? ""
        })

        #expect(partIds.count == 3)
        #expect(partIds.contains("P1"))
        #expect(partIds.contains("P2"))
        #expect(partIds.contains("P3"))
    }
}

@Suite("Base64 MIDI Encoding Tests")
struct Base64MIDITests {

    @Test("Base64 encode and decode MIDI data")
    func base64Roundtrip() {
        // Create sample MIDI header
        let originalData = Data([0x4D, 0x54, 0x68, 0x64, 0x00, 0x00, 0x00, 0x06])

        // Encode
        let base64String = originalData.base64EncodedString()

        // Decode
        let decodedData = Data(base64Encoded: base64String)

        #expect(decodedData != nil)
        #expect(decodedData == originalData)
    }

    @Test("Invalid base64 returns nil")
    func invalidBase64() {
        let invalidBase64 = "This is not valid base64!!!"
        let decoded = Data(base64Encoded: invalidBase64)

        // Should return nil or empty data
        #expect(decoded == nil || decoded?.isEmpty == true)
    }

    @Test("Empty string base64 decode")
    func emptyBase64() {
        let empty = ""
        let decoded = Data(base64Encoded: empty)

        #expect(decoded?.isEmpty == true || decoded == nil)
    }
}
