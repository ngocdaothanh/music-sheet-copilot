//
//  VerovioService.swift
//  MusicSheetsCopilot
//
//  Created on November 4, 2025.
//

import Foundation
import VerovioToolkit

/// A service class to interact with the Verovio music notation library
class VerovioService: ObservableObject {
    private let toolkit: VerovioToolkit

    private var lastLoadedMusicXML: String? = nil

    /// Configuration options for rendering
    struct RenderOptions {
        var pageWidth: Int = 2100
        var pageHeight: Int = 2970
        var scale: Int = 40
        var adjustPageHeight: Bool = true
        var breaks: String = "auto"

        var jsonString: String {
            """
            {
                "pageWidth": \(pageWidth),
                "pageHeight": \(pageHeight),
                "scale": \(scale),
                "adjustPageHeight": \(adjustPageHeight),
                "breaks": "\(breaks)"
            }
            """
        }
    }

    init() {
        // Initialize the toolkit first
        toolkit = VerovioToolkit()

        print("Verovio version: \(toolkit.getVersion())")
        print("Default resource path: \(toolkit.getResourcePath())")

        // Try to find the actual Verovio data resources from the Swift package
        var foundResourcePath: String?

        // Method 1: Check main bundle
        if let resourcePath = Bundle.main.path(forResource: "data", ofType: nil) {
            foundResourcePath = resourcePath
            print("✓ Found resources in main bundle: \(resourcePath)")
        }

        // Method 2: Try to get the VerovioToolkit module bundle
        else if let frameworkBundle = Bundle(identifier: "org.rismch.verovio.VerovioToolkit") {
            if let resourcePath = frameworkBundle.path(forResource: "data", ofType: nil) {
                foundResourcePath = resourcePath
                print("✓ Found resources in VerovioToolkit bundle: \(resourcePath)")
            } else if let resourcePath = frameworkBundle.resourcePath {
                let dataPath = (resourcePath as NSString).appendingPathComponent("data")
                if FileManager.default.fileExists(atPath: dataPath) {
                    foundResourcePath = dataPath
                    print("✓ Found resources at: \(dataPath)")
                }
            }
        }

        // Method 3: Search all loaded bundles
        if foundResourcePath == nil {
            for bundle in Bundle.allBundles {
                if let resourcePath = bundle.path(forResource: "data", ofType: nil),
                   FileManager.default.fileExists(atPath: resourcePath) {
                    // Check if this looks like Verovio data (should have Bravura font)
                    let bravuraPath = (resourcePath as NSString).appendingPathComponent("Bravura")
                    if FileManager.default.fileExists(atPath: bravuraPath) {
                        foundResourcePath = resourcePath
                        print("✓ Found Verovio resources in bundle: \(bundle.bundlePath)")
                        print("  Resource path: \(resourcePath)")
                        break
                    }
                }
            }
        }

        // Method 4: Search in Xcode DerivedData (development workaround)
        if foundResourcePath == nil {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let derivedDataPath = (homeDir as NSString).appendingPathComponent("Library/Developer/Xcode/DerivedData")

            do {
                let derivedDataContents = try FileManager.default.contentsOfDirectory(atPath: derivedDataPath)

                for projectFolder in derivedDataContents where projectFolder.hasPrefix("MusicSheetsCopilot") {
                    let projectPath = (derivedDataPath as NSString).appendingPathComponent(projectFolder)
                    let checkoutsPath = (projectPath as NSString).appendingPathComponent("SourcePackages/checkouts/verovio/data")

                    if FileManager.default.fileExists(atPath: checkoutsPath) {
                        foundResourcePath = checkoutsPath
                        print("✓ Found Verovio resources in DerivedData: \(checkoutsPath)")
                        break
                    }
                }
            } catch {
                print("  Could not search DerivedData: \(error)")
            }
        }

        // Set the resource path if we found it
        if let resourcePath = foundResourcePath {
            let success = toolkit.setResourcePath(resourcePath)
            print("Set resource path result: \(success)")
            print("New resource path: \(toolkit.getResourcePath())")
        } else {
            print("⚠️ Could not locate Verovio data resources")
            print("   Searched in all bundles - resources might not be properly bundled")
        }
    }

    /// Load and render a MusicXML file to SVG
    /// - Parameters:
    ///   - data: The MusicXML file data
    ///   - options: Rendering options
    /// - Returns: SVG string representation
    func renderMusicXML(data: Data, options: RenderOptions = RenderOptions()) throws -> String {
        // Set options
        toolkit.setOptions(options.jsonString)

        // Convert data to string
        guard let musicXMLString = String(data: data, encoding: .utf8) else {
            throw VerovioError.invalidData
        }

        // Store for tempo extraction
        lastLoadedMusicXML = musicXMLString

        // Debug: Print first 200 chars of MusicXML
        print("Loading MusicXML (first 200 chars):")
        print(String(musicXMLString.prefix(200)))

        // Load the MusicXML
        let loadSuccess = toolkit.loadData(musicXMLString)
        print("Verovio loadData result: \(loadSuccess)")

        guard loadSuccess else {
            // Try to get error information
            let errorLog = toolkit.getLog()
            print("Verovio error log: \(errorLog)")
            throw VerovioError.loadFailed(message: errorLog)
        }

        // Render to SVG (page 1, no XML declaration)
        let svg = toolkit.renderToSVG(1, false)
        print("SVG output length: \(svg.count)")

        guard !svg.isEmpty else {
            throw VerovioError.renderFailed
        }

        return svg
    }

    /// Render all pages of the loaded MusicXML to an array of SVG strings
    /// - Parameters:
    ///   - data: MusicXML data
    ///   - options: Rendering options
    /// - Returns: Array of SVG strings, one per page
    func renderAllPages(data: Data, options: RenderOptions = RenderOptions()) throws -> [String] {
        // Set options
        toolkit.setOptions(options.jsonString)

        // Convert data to string
        guard let musicXMLString = String(data: data, encoding: .utf8) else {
            throw VerovioError.invalidData
        }

        // Store for tempo extraction
        lastLoadedMusicXML = musicXMLString

        // Load the MusicXML
        let loadSuccess = toolkit.loadData(musicXMLString)
        print("Verovio loadData result: \(loadSuccess)")

        guard loadSuccess else {
            let errorLog = toolkit.getLog()
            print("Verovio error log: \(errorLog)")
            throw VerovioError.loadFailed(message: errorLog)
        }

        // Get page count
        let pageCount = Int(toolkit.getPageCount())
        print("Total pages: \(pageCount)")

        // Render all pages
        var svgPages: [String] = []
        for pageNum in 1...pageCount {
            let svg = toolkit.renderToSVG(pageNum, false)
            guard !svg.isEmpty else {
                throw VerovioError.renderFailed
            }
            svgPages.append(svg)
            print("Rendered page \(pageNum), SVG length: \(svg.count)")
        }

        return svgPages
    }

    /// Get the number of pages in the loaded document
    func getPageCount() -> Int {
        return Int(toolkit.getPageCount())
    }

    /// Render a specific page to SVG
    /// - Parameters:
    ///   - page: The page number to render (1-indexed)
    ///   - xmlDeclaration: Whether to include XML declaration in SVG
    /// - Returns: SVG string
    func renderPage(_ page: Int, xmlDeclaration: Bool = false) -> String {
        return toolkit.renderToSVG(page, xmlDeclaration)
    }

    /// Get MIDI output from the loaded score
    func getMIDI() -> String {
        return toolkit.renderToMIDI()
    }

    /// Get timing information for all elements (notes, measures, etc.)
    /// Returns a JSON string with element IDs and their on/off times in milliseconds
    func getTimingMap() -> String {
        // renderToTimemap requires an options parameter (empty string for defaults)
        return toolkit.renderToTimemap("")
    }

    /// Try to extract the tempo (BPM) from the loaded MusicXML, if available
    /// Returns nil if not found
    func getTempoBPM() -> Double? {
        // Try to get from toolkit if available (future-proof)
        // If not, parse lastLoadedMusicXML
        guard let xml = lastLoadedMusicXML else { return nil }

        // Look for <sound tempo="..."> or <direction-type><metronome>...
        // Simple regex for tempo attribute
        if let tempoMatch = xml.range(of: "tempo=\"([0-9]+(\\.[0-9]+)?)\"", options: .regularExpression) {
            let tempoString = String(xml[tempoMatch]).replacingOccurrences(of: "tempo=\"", with: "").replacingOccurrences(of: "\"", with: "")
            if let bpm = Double(tempoString) {
                return bpm
            }
        }

        // Try to find <per-minute> value in <metronome>
        if let perMinuteRange = xml.range(of: "<per-minute>([0-9]+(\\.[0-9]+)?)</per-minute>", options: .regularExpression) {
            let match = xml[perMinuteRange]
            let numberString = match.replacingOccurrences(of: "<per-minute>", with: "").replacingOccurrences(of: "</per-minute>", with: "")
            if let bpm = Double(numberString) {
                return bpm
            }
        }

        return nil
    }

    /// Extract measure start times from timing data
    /// Returns an array of (measureNumber, startTimeInSeconds)
    func getMeasureTimings() -> [(measure: Int, time: TimeInterval)] {
        let timingJSON = getTimingMap()

        guard let data = timingJSON.data(using: .utf8),
              let timingArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("Failed to parse timing data")
            return []
        }

        var measureTimings: [(Int, TimeInterval)] = []
        var currentMeasure = 1
        var measureStartTime: TimeInterval = 0

        // Scan through timing events to find measure boundaries
        // Verovio timing data includes events with on/off arrays
        for entry in timingArray {
            guard let tstamp = entry["tstamp"] as? Double else { continue }
            let timeInSeconds = tstamp / 1000.0

            // Check if any of the "on" IDs represent a measure element
            if let onArray = entry["on"] as? [String] {
                for id in onArray {
                    // Measure IDs typically start with "measure-" in MusicXML
                    if id.contains("measure") {
                        measureTimings.append((currentMeasure, measureStartTime))
                        currentMeasure += 1
                        measureStartTime = timeInSeconds
                    }
                }
            }
        }

        // Add the first measure if we haven't found any
        if measureTimings.isEmpty {
            measureTimings.append((1, 0))
        }

        return measureTimings
    }

    /// Get the start time for a specific measure number
    func getMeasureStartTime(_ measureNumber: Int) -> TimeInterval? {
        let timings = getMeasureTimings()
        return timings.first { $0.measure == measureNumber }?.time
    }

    /// Get the start time for a specific note ID from timing data
    func getNoteStartTime(_ noteId: String) -> TimeInterval? {
        let timingJSON = getTimingMap()

        guard let data = timingJSON.data(using: .utf8),
              let timingArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        // Find the first event where this note turns on
        for entry in timingArray {
            guard let tstamp = entry["tstamp"] as? Double,
                  let onArray = entry["on"] as? [String] else { continue }

            if onArray.contains(noteId) {
                return tstamp / 1000.0 // Convert ms to seconds
            }
        }

        return nil
    }
}

enum VerovioError: Error, LocalizedError {
    case invalidData
    case loadFailed(message: String)
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid MusicXML data"
        case .loadFailed(let message):
            return "Failed to load MusicXML into Verovio: \(message)"
        case .renderFailed:
            return "Failed to render music notation"
        }
    }
}