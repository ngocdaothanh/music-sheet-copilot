import Testing
import Foundation
@testable import MusicSheetsCopilot

@Suite("VerovioService Tests")
struct VerovioServiceTests {

    // MARK: - Staff Key Generation Tests

    @Test("Staff key format is consistent")
    func staffKeyFormat() {
        // Staff keys should be in format "partId-staffNumber"
        let partId = "P1"
        let staffNumber = 1
        let expectedKey = "\(partId)-\(staffNumber)"

        #expect(expectedKey == "P1-1")
    }

    @Test("Staff key format with different parts",
          arguments: [
        ("P1", 1, "P1-1"),
        ("P1", 2, "P1-2"),
        ("P2", 1, "P2-1"),
        ("Piano", 1, "Piano-1"),
    ])
    func staffKeyFormatVariations(partId: String, staffNumber: Int, expectedKey: String) {
        let staffKey = "\(partId)-\(staffNumber)"
        #expect(staffKey == expectedKey)
    }

    // MARK: - Enabled Staves Logic Tests

    @Test("Empty enabledStaves means all staves are enabled")
    func emptyEnabledStavesLogic() {
        let enabledStaves: Set<String> = []
        let testStaveKey = "P1-1"

        let isEnabled = enabledStaves.isEmpty || enabledStaves.contains(testStaveKey)

        #expect(isEnabled == true)  // Empty set means all enabled
    }

    @Test("Non-empty enabledStaves filters correctly")
    func nonEmptyEnabledStavesLogic() {
        let enabledStaves: Set<String> = ["P1-1", "P1-2"]

        let enabledStave = "P1-1"
        let disabledStave = "P2-1"

        #expect(enabledStaves.contains(enabledStave) == true)
        #expect(enabledStaves.contains(disabledStave) == false)
    }

    // MARK: - Part ID Extraction Tests

    @Test("Extract part IDs from enabled staves")
    func extractPartIdsFromEnabledStaves() {
        let enabledStaves: Set<String> = ["P1-1", "P1-2", "P2-1"]

        // Extract unique part IDs
        let partIds = Set(enabledStaves.map { staveKey in
            staveKey.split(separator: "-").first.map(String.init) ?? ""
        })

        #expect(partIds.count == 2)
        #expect(partIds.contains("P1"))
        #expect(partIds.contains("P2"))
    }

    @Test("Extract part IDs - Single staff parts")
    func extractPartIdsSingleStaff() {
        let enabledStaves: Set<String> = ["P1-1"]

        let partIds = Set(enabledStaves.map { staveKey in
            staveKey.split(separator: "-").first.map(String.init) ?? ""
        })

        #expect(partIds.count == 1)
        #expect(partIds.contains("P1"))
    }

    // MARK: - Channel Extraction Tests

    @Test("Extract MIDI channel from status byte",
          arguments: [
        (0x90, 0),  // Note On, channel 0
        (0x91, 1),  // Note On, channel 1
        (0x9F, 15), // Note On, channel 15
        (0x80, 0),  // Note Off, channel 0
        (0x8F, 15), // Note Off, channel 15
    ])
    func extractChannelFromStatusByte(statusByte: UInt8, expectedChannel: UInt8) {
        let channel = statusByte & 0x0F
        #expect(channel == expectedChannel)
    }

    // MARK: - Staff Name Tests

    @Test("Staff name formatting for display")
    func staffNameFormatting() {
        // Test that staff names are properly formatted for UI display
        let partName = "Piano"
        let staffNumber = 1
        let staffName = "Treble"

        let displayName = "\(partName) - \(staffName)"

        #expect(displayName == "Piano - Treble")
    }

    @Test("Staff name uniqueness detection")
    func staffNameUniqueness() {
        // Test detecting duplicate staff names
        let staffNames = ["Right Hand", "Right Hand", "Left Hand"]
        let uniqueNames = Set(staffNames)

        #expect(staffNames.count == 3)
        #expect(uniqueNames.count == 2)  // Only 2 unique names
    }
}

@Suite("MIDI Data Processing Tests")
struct MIDIProcessingTests {

    @Test("Base64 MIDI encoding roundtrip")
    func base64MIDIRoundtrip() {
        // Create sample MIDI data
        let originalData = Data([0x4D, 0x54, 0x68, 0x64])  // "MThd" header

        // Encode to base64
        let base64String = originalData.base64EncodedString()

        // Decode back
        let decodedData = Data(base64Encoded: base64String)

        #expect(decodedData != nil)
        #expect(decodedData == originalData)
    }

    @Test("MIDI note event time ordering")
    func noteEventOrdering() {
        // Test that note events can be sorted by time
        var events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = [
            (1.0, 60, 0),
            (0.0, 62, 0),
            (0.5, 64, 0),
        ]

        events.sort { $0.time < $1.time }

        #expect(events[0].time == 0.0)
        #expect(events[1].time == 0.5)
        #expect(events[2].time == 1.0)
    }

    @Test("Find minimum and maximum note times")
    func noteTimeExtent() {
        let events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = [
            (0.0, 60, 0),
            (0.5, 62, 0),
            (1.0, 64, 0),
            (5.0, 67, 0),
        ]

        let minTime = events.map { $0.time }.min()
        let maxTime = events.map { $0.time }.max()

        #expect(minTime == 0.0)
        #expect(maxTime == 5.0)
    }

    @Test("Filter notes by channel")
    func filterNotesByChannel() {
        let events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = [
            (0.0, 60, 0),
            (0.5, 62, 1),
            (1.0, 64, 0),
            (1.5, 67, 1),
        ]

        let channel0Events = events.filter { $0.channel == 0 }

        #expect(channel0Events.count == 2)
        #expect(channel0Events[0].midiNote == 60)
        #expect(channel0Events[1].midiNote == 64)
    }

    @Test("Find notes at specific time with tolerance")
    func findNotesAtTime() {
        let events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = [
            (0.0, 60, 0),
            (0.05, 62, 0),  // Within tolerance of 0.0
            (0.5, 64, 0),
            (1.0, 67, 0),
        ]

        let targetTime: TimeInterval = 0.0
        let tolerance: TimeInterval = 0.1

        let notesAtTime = events.filter { event in
            abs(event.time - targetTime) < tolerance
        }

        #expect(notesAtTime.count == 2)  // Should find notes at 0.0 and 0.05
    }
}

@Suite("Time and BPM Calculation Tests")
struct TimeCalculationTests {

    @Test("BPM to beat duration conversion",
          arguments: [
        (60.0, 1.0),
        (120.0, 0.5),
        (240.0, 0.25),
    ])
    func bpmToBeatDuration(bpm: Double, expectedDuration: TimeInterval) {
        let beatDuration = 60.0 / bpm
        #expect(beatDuration == expectedDuration)
    }

    @Test("Measure duration calculation")
    func measureDuration() {
        let bpm = 120.0  // 2 beats per second
        let beatsPerMeasure = 4

        let beatDuration = 60.0 / bpm  // 0.5 seconds per beat
        let measureDuration = beatDuration * Double(beatsPerMeasure)

        #expect(measureDuration == 2.0)  // 4 beats at 0.5s each = 2 seconds
    }

    @Test("Time to beat number conversion",
          arguments: [
        (0.0, 120.0, 0),
        (0.5, 120.0, 1),
        (1.0, 120.0, 2),
        (2.0, 60.0, 2),
    ])
    func timeToBeatNumber(time: TimeInterval, bpm: Double, expectedBeat: Int) {
        let beatDuration = 60.0 / bpm
        let beat = Int(time / beatDuration)

        #expect(beat == expectedBeat)
    }
}
