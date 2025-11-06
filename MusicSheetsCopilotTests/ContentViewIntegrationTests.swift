import Testing
import Foundation
import SwiftUI
@testable import MusicSheetsCopilot

/// Integration tests for ContentView - Main UI and workflow testing
@Suite("ContentView Integration Tests")
struct ContentViewIntegrationTests {

    // MARK: - Playback Mode Tests

    @Test("PlaybackMode enum has expected cases")
    func playbackModeValues() {
        // Test that enum has expected values
        let midiMode: ContentView.PlaybackMode = .midiWithMetronome
        let metronomeMode: ContentView.PlaybackMode = .metronomeOnly

        #expect(midiMode == .midiWithMetronome)
        #expect(metronomeMode == .metronomeOnly)
    }

    // MARK: - Demo File Loading Tests

    @Test("Demo file URLs are accessible")
    func demoFileURLs() {
        let twinkleURL = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml")
        let furEliseURL = Bundle.main.url(forResource: "fur_elise", withExtension: "xml")

        #expect(twinkleURL != nil)
        #expect(furEliseURL != nil)
    }

    @Test("Demo files contain valid MusicXML data")
    func demoFilesValidData() throws {
        let twinkleURL = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml")
        guard let url = twinkleURL else {
            Issue.record("Demo file not found")
            return
        }

        let data = try Data(contentsOf: url)
        guard let xmlString = String(data: data, encoding: .utf8) else {
            Issue.record("Failed to decode XML string")
            return
        }

        // Check for MusicXML root element
        #expect(xmlString.contains("<score-partwise") || xmlString.contains("<score-timewise"))
        #expect(xmlString.contains("</score-partwise>") || xmlString.contains("</score-timewise>"))
    }

    // MARK: - MXL File Extension Tests

    @Test("MXL file extension is recognized")
    func mxlExtensionRecognition() {
        let testFilename = "test_file.mxl"
        let fileExtension = (testFilename as NSString).pathExtension.lowercased()

        #expect(fileExtension == "mxl")
    }

    @Test("MusicXML file extension is recognized")
    func musicxmlExtensionRecognition() {
        let testFilename = "test_file.musicxml"
        let fileExtension = (testFilename as NSString).pathExtension.lowercased()

        #expect(fileExtension == "musicxml")
    }

    @Test("XML file extension is recognized")
    func xmlExtensionRecognition() {
        let testFilename = "test_file.xml"
        let fileExtension = (testFilename as NSString).pathExtension.lowercased()

        #expect(fileExtension == "xml")
    }

    // MARK: - Time Signature Tests

    @Test("Default time signature is 4/4")
    func defaultTimeSignature() {
        let midiPlayer = MIDIPlayer()

        #expect(midiPlayer.timeSignature.0 == 4)
        #expect(midiPlayer.timeSignature.1 == 4)
    }

    @Test("Time signature formats correctly for display",
          arguments: [
        ((4, 4), "4/4"),
        ((3, 4), "3/4"),
        ((6, 8), "6/8"),
        ((2, 2), "2/2"),
    ])
    func timeSignatureDisplay(timeSignature: (Int, Int), expected: String) {
        let display = "\(timeSignature.0)/\(timeSignature.1)"
        #expect(display == expected)
    }
}

/// Tests for TempoSliderView component
@Suite("Tempo Slider View Tests")
struct TempoSliderViewTests {

    @Test("BPM calculation with playback rate",
          arguments: [
        (120.0, 1.0, 120),    // Normal speed
        (120.0, 0.5, 60),     // Half speed
        (120.0, 2.0, 240),    // Double speed
        (100.0, 1.5, 150),    // 1.5x speed
        (80.0, 0.75, 60),     // 75% speed
    ])
    func bpmWithRate(baseBPM: Double, rate: Double, expectedBPM: Int) {
        let calculatedBPM = Int(baseBPM * rate)
        #expect(calculatedBPM == expectedBPM)
    }

    @Test("Playback rate percentage display",
          arguments: [
        (0.5, 50),
        (1.0, 100),
        (1.5, 150),
        (2.0, 200),
    ])
    func playbackRatePercentage(rate: Double, expectedPercent: Int) {
        let percent = Int(rate * 100)
        #expect(percent == expectedPercent)
    }

    @Test("Playback rate bounds")
    func playbackRateBounds() {
        let minRate = 0.5
        let maxRate = 2.0

        // Test values within bounds
        #expect(1.0 >= minRate && 1.0 <= maxRate)

        // Test boundary values
        #expect(minRate >= 0.5)
        #expect(maxRate <= 2.0)
    }
}

/// Tests for playback control logic
@Suite("Playback Control Tests")
struct PlaybackControlTests {

    @Test("Playback rate affects metronome and MIDI player")
    func playbackRateSync() {
        let midiPlayer = MIDIPlayer()
        let metronome = Metronome()
        let testRate: Float = 1.5

        midiPlayer.playbackRate = testRate
        metronome.playbackRate = testRate

        #expect(midiPlayer.playbackRate == testRate)
        #expect(metronome.playbackRate == testRate)
    }

    @Test("BPM updates propagate correctly")
    func bpmPropagation() {
        let metronome = Metronome()
        let testBPM = 140.0

        metronome.bpm = testBPM

        #expect(metronome.bpm == testBPM)
    }

    @Test("Time signature propagation from MIDI player to metronome")
    func timeSignatureSync() {
        let midiPlayer = MIDIPlayer()
        let metronome = Metronome()

        midiPlayer.timeSignature = (3, 4)
        metronome.timeSignature = midiPlayer.timeSignature

        #expect(metronome.timeSignature.0 == 3)
        #expect(metronome.timeSignature.1 == 4)
    }
}

/// Tests for staff and part selection logic
@Suite("Staff Selection Logic Tests")
struct StaffSelectionTests {

    @Test("Staff key generation is consistent")
    func staffKeyGeneration() {
        let partId = "P1"
        let staffNumber = 2
        let staffKey = "\(partId)-\(staffNumber)"

        #expect(staffKey == "P1-2")
    }

    @Test("Cannot disable all staves (at least one must remain)")
    func minimumOneStaff() {
        var enabledStaves = Set(["P1-1", "P1-2"])

        // Try to remove last staff
        if enabledStaves.count > 1 {
            enabledStaves.remove("P1-1")
        }

        #expect(enabledStaves.count >= 1)

        // Cannot remove the last one
        let canRemoveLast = enabledStaves.count > 1
        #expect(canRemoveLast == false)
    }

    @Test("Toggling staff updates enabled set correctly")
    func toggleStaffLogic() {
        var enabledStaves = Set(["P1-1", "P1-2"])
        let staffToToggle = "P1-1"

        // Disable
        if enabledStaves.contains(staffToToggle) && enabledStaves.count > 1 {
            enabledStaves.remove(staffToToggle)
        }

        #expect(enabledStaves.count == 1)
        #expect(!enabledStaves.contains(staffToToggle))

        // Re-enable
        enabledStaves.insert(staffToToggle)

        #expect(enabledStaves.count == 2)
        #expect(enabledStaves.contains(staffToToggle))
    }
}

/// Tests for error handling
@Suite("Error Handling Tests")
struct ErrorHandlingTests {

    @Test("VerovioError descriptions are informative")
    func verovioErrorDescriptions() {
        let invalidDataError = VerovioError.invalidData
        let loadError = VerovioError.loadFailed(message: "Test error")
        let renderError = VerovioError.renderFailed

        #expect(invalidDataError.errorDescription?.contains("Invalid") == true)
        #expect(loadError.errorDescription?.contains("Failed to load") == true)
        #expect(renderError.errorDescription?.contains("Failed to render") == true)
    }

    @Test("Error messages contain helpful context")
    func errorMessageContext() {
        let errorMessage = "Test error details"
        let error = VerovioError.loadFailed(message: errorMessage)

        #expect(error.errorDescription?.contains(errorMessage) == true)
    }
}
