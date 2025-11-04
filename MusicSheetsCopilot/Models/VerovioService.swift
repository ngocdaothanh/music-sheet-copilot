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
    var lastLoadedData: Data? = nil

    @Published var availableParts: [(id: String, name: String)] = []
    @Published var enabledPartIds: Set<String> = []

    // Staves support
    @Published var availableStaves: [(partId: String, staffNumber: Int, name: String)] = []
    @Published var enabledStaves: Set<String> = [] // Format: "partId-staffNumber"

    /// Configuration options for rendering
    struct RenderOptions {
        var pageWidth: Int = 2100
        var pageHeight: Int = 2970
        var scale: Int = 40
        var adjustPageHeight: Bool = true
        var breaks: String = "auto"
        var enabledParts: [String]? = nil

        var jsonString: String {
            var json = """
            {
                "pageWidth": \(pageWidth),
                "pageHeight": \(pageHeight),
                "scale": \(scale),
                "adjustPageHeight": \(adjustPageHeight),
                "breaks": "\(breaks)"
            """

            if let parts = enabledParts, !parts.isEmpty {
                let partsJson = parts.map { "\"\($0)\"" }.joined(separator: ",")
                json += """
                ,
                "appXPathQuery": ["//score-part[@id='\(parts.first!)']"]
                """
            }

            json += "\n}"
            return json
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

        // Extract available parts from the loaded score
        extractAvailableParts(from: musicXMLString)

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
        guard var musicXMLString = String(data: data, encoding: .utf8) else {
            throw VerovioError.invalidData
        }

        // Extract available parts/staves from the ORIGINAL (unfiltered) score
        // Only extract if this is a new file (data changed) or first load
        let isNewFile = (lastLoadedData != data)
        if isNewFile {
            extractAvailableParts(from: musicXMLString)
        }

        // Filter staves if needed
        if !enabledStaves.isEmpty && enabledStaves.count < availableStaves.count {
            musicXMLString = filterStaves(in: musicXMLString, enabledStaves: enabledStaves)
        }

        // Filter parts if needed
        if !enabledPartIds.isEmpty && enabledPartIds.count < availableParts.count {
            musicXMLString = filterParts(in: musicXMLString, enabledIds: enabledPartIds)
        }

        // Store for tempo extraction
        lastLoadedMusicXML = musicXMLString
        lastLoadedData = data

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

    /// Extract available parts and staves from MusicXML
    private func extractAvailableParts(from musicXML: String) {
        var parts: [(String, String)] = []
        var staves: [(String, Int, String)] = []

        // Parse the MusicXML to find <score-part> elements
        let partPattern = "<score-part id=\"([^\"]+)\">\\s*<part-name>([^<]+)</part-name>"
        if let partRegex = try? NSRegularExpression(pattern: partPattern, options: []) {
            let nsString = musicXML as NSString
            let matches = partRegex.matches(in: musicXML, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                if match.numberOfRanges >= 3 {
                    let idRange = match.range(at: 1)
                    let nameRange = match.range(at: 2)

                    if idRange.location != NSNotFound && nameRange.location != NSNotFound {
                        let id = nsString.substring(with: idRange)
                        let name = nsString.substring(with: nameRange)
                        parts.append((id, name))

                        // Now find how many staves this part has
                        let staffCount = extractStaffCount(from: musicXML, partId: id)

                        if staffCount > 1 {
                            // Multiple staves - create separate entries for each
                            for staffNum in 1...staffCount {
                                let staffName = "\(name) - \(staffNum == 1 ? "Treble" : staffNum == 2 ? "Bass" : "Staff \(staffNum)")"
                                staves.append((id, staffNum, staffName))
                            }
                        }
                    }
                }
            }
        }

        DispatchQueue.main.async {
            let newPartIds = Set(parts.map { $0.0 })
            // Always update availableParts and enabledPartIds on new file load
            self.availableParts = parts
            self.enabledPartIds = newPartIds

            // Update staves
            self.availableStaves = staves
            if !staves.isEmpty {
                // Enable all staves by default
                self.enabledStaves = Set(staves.map { "\($0.0)-\($0.1)" })
            }
        }
    }

    /// Extract the number of staves for a given part
    private func extractStaffCount(from musicXML: String, partId: String) -> Int {
        // Find the <part id="partId"> section and look for <staves> element
        let partSectionPattern = "<part id=\"\(partId)\">.*?</part>"
        guard let partRegex = try? NSRegularExpression(pattern: partSectionPattern, options: [.dotMatchesLineSeparators]) else {
            return 1
        }

        let nsString = musicXML as NSString
        guard let partMatch = partRegex.firstMatch(in: musicXML, options: [], range: NSRange(location: 0, length: nsString.length)) else {
            return 1
        }

        let partSection = nsString.substring(with: partMatch.range)

        // Look for <staves>N</staves>
        let stavesPattern = "<staves>(\\d+)</staves>"
        guard let stavesRegex = try? NSRegularExpression(pattern: stavesPattern, options: []) else {
            return 1
        }

        let stavesNsString = partSection as NSString
        if let stavesMatch = stavesRegex.firstMatch(in: partSection, options: [], range: NSRange(location: 0, length: stavesNsString.length)),
           stavesMatch.numberOfRanges >= 2 {
            let countRange = stavesMatch.range(at: 1)
            let countString = stavesNsString.substring(with: countRange)
            return Int(countString) ?? 1
        }

        return 1
    }

    /// Filter staves within parts - removes disabled staves from the MusicXML
    private func filterStaves(in musicXML: String, enabledStaves: Set<String>) -> String {
        var filtered = musicXML

        // Group enabled staves by part
        var enabledByPart: [String: Set<Int>] = [:]
        for staveKey in enabledStaves {
            let components = staveKey.split(separator: "-")
            if components.count == 2,
               let staffNum = Int(components[1]) {
                let partId = String(components[0])
                enabledByPart[partId, default: Set()].insert(staffNum)
            }
        }

        // For each part with multiple staves, filter the disabled ones
        for (partId, staffNumber, _) in availableStaves {
            let staveKey = "\(partId)-\(staffNumber)"
            if !enabledStaves.contains(staveKey) {
                // This staff is disabled - remove all elements with this staff number
                filtered = removeStaffElements(from: filtered, partId: partId, staffNumber: staffNumber)
            }
        }

        // Update the <staves> count in attributes for each part
        for (partId, enabledStaffNums) in enabledByPart {
            let enabledCount = enabledStaffNums.count
            if enabledCount > 0 {
                // Find and update <staves>N</staves> in the attributes section
                let stavesPattern = "(<part id=\"\(partId)\">.*?<attributes>.*?)<staves>\\d+</staves>"
                if let regex = try? NSRegularExpression(pattern: stavesPattern, options: [.dotMatchesLineSeparators]) {
                    let template = "$1<staves>\(enabledCount)</staves>"
                    filtered = regex.stringByReplacingMatches(in: filtered, options: [], range: NSRange(location: 0, length: filtered.utf16.count), withTemplate: template)
                }
            }
        }

        return filtered
    }

    /// Remove all elements belonging to a specific staff number within a part
    private func removeStaffElements(from musicXML: String, partId: String, staffNumber: Int) -> String {
        var filtered = musicXML

        // Remove <note> elements with <staff>N</staff>
        let notePattern = "<note>.*?<staff>\(staffNumber)</staff>.*?</note>"
        if let regex = try? NSRegularExpression(pattern: notePattern, options: [.dotMatchesLineSeparators]) {
            filtered = regex.stringByReplacingMatches(in: filtered, options: [], range: NSRange(location: 0, length: filtered.utf16.count), withTemplate: "")
        }

        // Remove <forward> elements with <staff>N</staff>
        let forwardPattern = "<forward>.*?<staff>\(staffNumber)</staff>.*?</forward>"
        if let regex = try? NSRegularExpression(pattern: forwardPattern, options: [.dotMatchesLineSeparators]) {
            filtered = regex.stringByReplacingMatches(in: filtered, options: [], range: NSRange(location: 0, length: filtered.utf16.count), withTemplate: "")
        }

        // Remove <backup> elements with <staff>N</staff>
        let backupPattern = "<backup>.*?<staff>\(staffNumber)</staff>.*?</backup>"
        if let regex = try? NSRegularExpression(pattern: backupPattern, options: [.dotMatchesLineSeparators]) {
            filtered = regex.stringByReplacingMatches(in: filtered, options: [], range: NSRange(location: 0, length: filtered.utf16.count), withTemplate: "")
        }

        // Remove <clef> elements with number=N
        let clefPattern = "<clef number=\"\(staffNumber)\">.*?</clef>"
        if let regex = try? NSRegularExpression(pattern: clefPattern, options: [.dotMatchesLineSeparators]) {
            filtered = regex.stringByReplacingMatches(in: filtered, options: [], range: NSRange(location: 0, length: filtered.utf16.count), withTemplate: "")
        }

        return filtered
    }

    /// Filter MusicXML to only include enabled parts
    private func filterParts(in musicXML: String, enabledIds: Set<String>) -> String {
        var filtered = musicXML

        // Remove disabled parts from <part-list>
        for (partId, _) in availableParts {
            if !enabledIds.contains(partId) {
                // Remove the score-part element
                let scorePartPattern = "<score-part id=\"\(partId)\">.*?</score-part>"
                if let regex = try? NSRegularExpression(pattern: scorePartPattern, options: [.dotMatchesLineSeparators]) {
                    filtered = regex.stringByReplacingMatches(in: filtered, options: [], range: NSRange(location: 0, length: filtered.utf16.count), withTemplate: "")
                }

                // Remove the part element
                let partPattern = "<part id=\"\(partId)\">.*?</part>"
                if let regex = try? NSRegularExpression(pattern: partPattern, options: [.dotMatchesLineSeparators]) {
                    filtered = regex.stringByReplacingMatches(in: filtered, options: [], range: NSRange(location: 0, length: filtered.utf16.count), withTemplate: "")
                }
            }
        }

        return filtered
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