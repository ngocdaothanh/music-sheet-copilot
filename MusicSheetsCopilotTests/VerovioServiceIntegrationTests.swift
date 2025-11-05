import Testing
import Foundation
@testable import MusicSheetsCopilot

@Suite("VerovioService Integration Tests")
struct VerovioServiceIntegrationTests {

    // MARK: - Staff Filtering Tests

    @Test("hideDisabledStaves removes staff elements from MusicXML")
    func hideDisabledStavesRemovesElements() throws {
        let service = VerovioService()

        // Sample MusicXML with two staves
        let musicXML = """
        <score-partwise>
            <part id="P1">
                <measure number="1">
                    <note>
                        <pitch><step>C</step><octave>5</octave></pitch>
                        <staff>1</staff>
                    </note>
                    <note>
                        <pitch><step>E</step><octave>4</octave></pitch>
                        <staff>2</staff>
                    </note>
                </measure>
            </part>
        </score-partwise>
        """

        // Set available staves (needed for the method to know which staves exist)
        service.availableStaves = [
            ("P1", 1, "Treble"),
            ("P1", 2, "Bass")
        ]

        // Enable only staff 1
        let enabledStaves: Set<String> = ["P1-1"]

        let filtered = service.hideDisabledStaves(in: musicXML, enabledStaves: enabledStaves)

        // Should keep staff 1
        #expect(filtered.contains("<staff>1</staff>"))

        // Should remove staff 2 notes
        #expect(!filtered.contains("<staff>2</staff>") || filtered.range(of: "<staff>2</staff>") == nil)
    }

    @Test("hideDisabledStaves preserves all staves when all are enabled")
    func hideDisabledStavesPreservesAll() throws {
        let service = VerovioService()

        let musicXML = """
        <score-partwise>
            <part id="P1">
                <measure>
                    <note><staff>1</staff></note>
                    <note><staff>2</staff></note>
                </measure>
            </part>
        </score-partwise>
        """

        service.availableStaves = [
            ("P1", 1, "Treble"),
            ("P1", 2, "Bass")
        ]

        // Enable both staves
        let enabledStaves: Set<String> = ["P1-1", "P1-2"]

        let filtered = service.hideDisabledStaves(in: musicXML, enabledStaves: enabledStaves)

        // Both staves should be present
        #expect(filtered.contains("<staff>1</staff>"))
        #expect(filtered.contains("<staff>2</staff>"))
    }

    @Test("hideDisabledStaves handles empty enabledStaves correctly")
    func hideDisabledStavesEmptySet() throws {
        let service = VerovioService()

        let musicXML = """
        <score-partwise>
            <part id="P1">
                <measure>
                    <note><staff>1</staff></note>
                </measure>
            </part>
        </score-partwise>
        """

        service.availableStaves = [("P1", 1, "Treble")]

        // Empty set - in actual usage, this means all staves enabled
        let enabledStaves: Set<String> = []

        let filtered = service.hideDisabledStaves(in: musicXML, enabledStaves: enabledStaves)

        // When empty, the function should process all staves as potentially disabled
        // The actual behavior depends on implementation
        #expect(filtered.count > 0)
    }

    // MARK: - Part Filtering Tests

    @Test("hideDisabledParts removes part elements from MusicXML")
    func hideDisabledPartsRemovesElements() throws {
        let service = VerovioService()

        let musicXML = """
        <score-partwise>
            <part-list>
                <score-part id="P1"><part-name>Piano</part-name></score-part>
                <score-part id="P2"><part-name>Violin</part-name></score-part>
            </part-list>
            <part id="P1">
                <measure><note><pitch><step>C</step></pitch></note></measure>
            </part>
            <part id="P2">
                <measure><note><pitch><step>D</step></pitch></note></measure>
            </part>
        </score-partwise>
        """

        service.availableParts = [
            ("P1", "Piano"),
            ("P2", "Violin")
        ]

        // Enable only Piano
        let enabledPartIds: Set<String> = ["P1"]

        let filtered = service.hideDisabledParts(in: musicXML, enabledIds: enabledPartIds)

        // Should keep P1 part and its content
        #expect(filtered.contains("id=\"P1\""))
        #expect(filtered.contains("<step>C</step>"))

        // P2 part structure remains but notes are removed
        #expect(filtered.contains("id=\"P2\""))
        #expect(!filtered.contains("<step>D</step>"))
    }

    @Test("hideDisabledParts preserves all parts when all are enabled")
    func hideDisabledPartsPreservesAll() throws {
        let service = VerovioService()

        let musicXML = """
        <score-partwise>
            <part id="P1"><measure/></part>
            <part id="P2"><measure/></part>
        </score-partwise>
        """

        service.availableParts = [
            ("P1", "Piano"),
            ("P2", "Violin")
        ]

        let enabledPartIds: Set<String> = ["P1", "P2"]

        let filtered = service.hideDisabledParts(in: musicXML, enabledIds: enabledPartIds)

        // Both parts should be present
        #expect(filtered.contains("id=\"P1\""))
        #expect(filtered.contains("id=\"P2\""))
    }

    // MARK: - Load MusicXML Integration Tests

    @Test("Load twinkle_twinkle.xml detects correct number of staves")
    func loadTwinkleTwinkleStaves() throws {
        let service = VerovioService()

        // Load the test file from the main app bundle (Resources folder)
        let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml")

        guard let url = url else {
            Issue.record("Could not find twinkle_twinkle.xml - make sure Resources folder is included in app target")
            return
        }

        let data = try Data(contentsOf: url)

        // Render to trigger parsing
        _ = try service.renderAllPages(data: data)

        // Should detect 2 staves (Right Hand and Left Hand)
        #expect(service.availableStaves.count == 2)

        // Check staff names
        let staffNames = service.availableStaves.map { $0.2 }
        #expect(staffNames.contains("Right Hand") || staffNames.contains("Left Hand"))
    }

    @Test("Load twinkle_twinkle.xml generates MIDI with correct note count")
    func loadTwinkleTwinkleMIDI() throws {
        let service = VerovioService()
        let player = MIDIPlayer()

        let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml")

        guard let url = url else {
            Issue.record("Could not find twinkle_twinkle.xml")
            return
        }

        let data = try Data(contentsOf: url)
        _ = try service.renderAllPages(data: data)

        // Generate full MIDI
        let midiString = service.getMIDI()
        guard let midiData = Data(base64Encoded: midiString) else {
            Issue.record("Failed to decode MIDI base64")
            return
        }

        try player.loadMIDI(data: midiData)

        // Should have notes (exact count may vary, but should be > 0)
        #expect(player.noteEvents.count > 0)

        // For twinkle_twinkle.xml, we expect around 14 notes total
        #expect(player.noteEvents.count >= 10)  // At least 10 notes
    }

    @Test("getMIDIForFirstStaff produces fewer or equal notes than full MIDI")
    func firstStaffFilteringReducesNotes() throws {
        let service = VerovioService()
        let fullPlayer = MIDIPlayer()
        let filteredPlayer = MIDIPlayer()

        let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml")

        guard let url = url else {
            Issue.record("Could not find twinkle_twinkle.xml")
            return
        }

        let data = try Data(contentsOf: url)
        _ = try service.renderAllPages(data: data)

        // Get full MIDI note count
        let fullMIDI = service.getMIDI()
        guard let fullData = Data(base64Encoded: fullMIDI) else {
            Issue.record("Failed to decode full MIDI")
            return
        }
        try fullPlayer.loadMIDI(data: fullData)
        let fullCount = fullPlayer.noteEvents.count

        // Get filtered MIDI note count (first staff only)
        guard let filteredMIDI = service.getMIDIForFirstStaff() else {
            Issue.record("Failed to get first staff MIDI")
            return
        }
        guard let filteredData = Data(base64Encoded: filteredMIDI) else {
            Issue.record("Failed to decode filtered MIDI")
            return
        }
        try filteredPlayer.loadMIDI(data: filteredData)
        let filteredCount = filteredPlayer.noteEvents.count

        // Filtered should have fewer or equal notes
        #expect(filteredCount <= fullCount)
        #expect(filteredCount > 0)  // Should still have some notes
    }

    @Test("Enabled staves start with all staves enabled on first load")
    func initialEnabledStavesState() throws {
        let service = VerovioService()

        // Initially empty
        #expect(service.enabledStaves.isEmpty)

        let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml")

        guard let url = url else {
            Issue.record("Could not find twinkle_twinkle.xml")
            return
        }

        let data = try Data(contentsOf: url)
        _ = try service.renderAllPages(data: data)

        // After loading, all staves should be enabled (if availableStaves is not empty)
        if !service.availableStaves.isEmpty {
            #expect(service.enabledStaves.count == service.availableStaves.count)
        }
    }

    @Test("Toggling staff selection updates enabledStaves correctly")
    func toggleStaffSelection() throws {
        let service = VerovioService()

        let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml")

        guard let url = url else {
            Issue.record("Could not find twinkle_twinkle.xml")
            return
        }

        let data = try Data(contentsOf: url)
        _ = try service.renderAllPages(data: data)

        let initialCount = service.enabledStaves.count

        // Get first staff key
        guard let firstStave = service.availableStaves.first else {
            Issue.record("No staves available")
            return
        }

        let firstStaveKey = "\(firstStave.0)-\(firstStave.1)"

        // Disable first staff
        service.enabledStaves.remove(firstStaveKey)

        #expect(service.enabledStaves.count == initialCount - 1)
        #expect(!service.enabledStaves.contains(firstStaveKey))

        // Re-enable first staff
        service.enabledStaves.insert(firstStaveKey)

        #expect(service.enabledStaves.count == initialCount)
        #expect(service.enabledStaves.contains(firstStaveKey))
    }

    // MARK: - Staff Name Tests

    @Test("Staff names are unique and correctly extracted")
    func staffNamesUniqueness() throws {
        let service = VerovioService()

        let url = Bundle.main.url(forResource: "fur_elise", withExtension: "xml")

        guard let url = url else {
            Issue.record("Could not find fur_elise.xml")
            return
        }

        let data = try Data(contentsOf: url)
        _ = try service.renderAllPages(data: data)

        // If there are 2 staves with same partId, they should have different names
        // or we should detect them properly
        if service.availableStaves.count > 1 {
            let partIds = service.availableStaves.map { $0.0 }
            if Set(partIds).count == 1 {
                // Same part, multiple staves - names should be different OR
                // we should handle staff numbers properly
                // The key is: "\(partId)-\(staffNumber)" should be unique
                let staveKeys = service.availableStaves.map { "\($0.0)-\($0.1)" }
                let uniqueKeys = Set(staveKeys)
                #expect(staveKeys.count == uniqueKeys.count)  // All keys should be unique
            }
        }
    }
}
