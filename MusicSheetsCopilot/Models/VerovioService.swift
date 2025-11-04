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


        // Try to find the actual Verovio data resources from the Swift package
        var foundResourcePath: String?

        // Method 1: Check main bundle
        if let resourcePath = Bundle.main.path(forResource: "data", ofType: nil) {
            foundResourcePath = resourcePath
        }

        // Method 2: Try to get the VerovioToolkit module bundle
        else if let frameworkBundle = Bundle(identifier: "org.rismch.verovio.VerovioToolkit") {
            if let resourcePath = frameworkBundle.path(forResource: "data", ofType: nil) {
                foundResourcePath = resourcePath
            } else if let resourcePath = frameworkBundle.resourcePath {
                let dataPath = (resourcePath as NSString).appendingPathComponent("data")
                if FileManager.default.fileExists(atPath: dataPath) {
                    foundResourcePath = dataPath
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
                        break
                    }
                }
            } catch {
            }
        }

        // Set the resource path if we found it
        if let resourcePath = foundResourcePath {
            toolkit.setResourcePath(resourcePath)
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

        // Load the MusicXML
        let loadSuccess = toolkit.loadData(musicXMLString)

        guard loadSuccess else {
            // Try to get error information
            let errorLog = toolkit.getLog()
            throw VerovioError.loadFailed(message: errorLog)
        }

        // Extract available parts from the loaded score
        extractAvailableParts(from: musicXMLString)

        // Render to SVG (page 1, no XML declaration)
        let svg = toolkit.renderToSVG(1, false)

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

        // Hide disabled staves using print-object="no" (for multi-staff single parts like piano)
        if !enabledStaves.isEmpty && enabledStaves.count < availableStaves.count {
            print("DEBUG: Hiding disabled staves. Enabled: \(enabledStaves), Available: \(availableStaves.map { "\($0.partId)-\($0.staffNumber)" })")
            musicXMLString = hideDisabledStaves(in: musicXMLString, enabledStaves: enabledStaves)
        }

        // Hide disabled parts using print-object="no" (for multi-part scores)
        if !enabledPartIds.isEmpty && enabledPartIds.count < availableParts.count {
            print("DEBUG: Hiding disabled parts. Enabled: \(enabledPartIds), Available: \(availableParts.map { $0.id })")
            musicXMLString = hideDisabledParts(in: musicXMLString, enabledIds: enabledPartIds)
        }

        // Set options
        toolkit.setOptions(options.jsonString)

        // Store for tempo extraction
        lastLoadedMusicXML = musicXMLString
        lastLoadedData = data

        // Load the MusicXML
        let loadSuccess = toolkit.loadData(musicXMLString)

        guard loadSuccess else {
            let errorLog = toolkit.getLog()
            throw VerovioError.loadFailed(message: errorLog)
        }

        // Get page count
        let pageCount = Int(toolkit.getPageCount())

        // Render all pages
        var svgPages: [String] = []
        for pageNum in 1...pageCount {
            let svg = toolkit.renderToSVG(pageNum, false)
            guard !svg.isEmpty else {
                throw VerovioError.renderFailed
            }
            svgPages.append(svg)
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
        // Pattern to match the entire score-part section
        let scorePartPattern = "<score-part id=\"([^\"]+)\">.*?</score-part>"
        if let scorePartRegex = try? NSRegularExpression(pattern: scorePartPattern, options: [.dotMatchesLineSeparators]) {
            let nsString = musicXML as NSString
            let matches = scorePartRegex.matches(in: musicXML, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                if match.numberOfRanges >= 2 {
                    let idRange = match.range(at: 1)
                    let scorePartRange = match.range

                    if idRange.location != NSNotFound {
                        let id = nsString.substring(with: idRange)
                        let scorePartSection = nsString.substring(with: scorePartRange)

                        // Try to extract display name first, fall back to part-name
                        var name = ""

                        // Look for <part-name-display><display-text>...</display-text>
                        let displayNamePattern = "<part-name-display>\\s*<display-text>([^<]+)</display-text>"
                        if let displayRegex = try? NSRegularExpression(pattern: displayNamePattern, options: []),
                           let displayMatch = displayRegex.firstMatch(in: scorePartSection, options: [], range: NSRange(location: 0, length: (scorePartSection as NSString).length)),
                           displayMatch.numberOfRanges >= 2 {
                            let displayNameRange = displayMatch.range(at: 1)
                            name = (scorePartSection as NSString).substring(with: displayNameRange)
                        } else {
                            // Fall back to <part-name>
                            let partNamePattern = "<part-name>([^<]+)</part-name>"
                            if let nameRegex = try? NSRegularExpression(pattern: partNamePattern, options: []),
                               let nameMatch = nameRegex.firstMatch(in: scorePartSection, options: [], range: NSRange(location: 0, length: (scorePartSection as NSString).length)),
                               nameMatch.numberOfRanges >= 2 {
                                let nameRange = nameMatch.range(at: 1)
                                name = (scorePartSection as NSString).substring(with: nameRange)
                            }
                        }

                        if !name.isEmpty {
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

    /// Hide disabled staves by removing their content from MusicXML
    /// Verovio doesn't respect print-object="no" for rendering, so we must remove elements
    private func hideDisabledStaves(in musicXML: String, enabledStaves: Set<String>) -> String {
        var filtered = musicXML

        // Determine which staves to hide for each part
        for (partId, staffNumber, _) in availableStaves {
            let staveKey = "\(partId)-\(staffNumber)"
            if !enabledStaves.contains(staveKey) {
                print("DEBUG: Removing content from staff \(staffNumber) for part \(partId)")
                
                // Remove notes on this staff
                let notePattern = "<note(?:(?!</note>).)*<staff>\(staffNumber)</staff>(?:(?!</note>).)*</note>"
                if let regex = try? NSRegularExpression(pattern: notePattern, options: [.dotMatchesLineSeparators]) {
                    let count = regex.numberOfMatches(in: filtered, options: [], range: NSRange(location: 0, length: filtered.utf16.count))
                    print("DEBUG: Removing \(count) notes from staff \(staffNumber)")
                    filtered = regex.stringByReplacingMatches(in: filtered, options: [], range: NSRange(location: 0, length: filtered.utf16.count), withTemplate: "")
                }
                
                // Remove directions (dynamics, pedals, etc.) on this staff
                let directionPattern = "<direction(?:(?!</direction>).)*<staff>\(staffNumber)</staff>(?:(?!</direction>).)*</direction>"
                if let regex = try? NSRegularExpression(pattern: directionPattern, options: [.dotMatchesLineSeparators]) {
                    let count = regex.numberOfMatches(in: filtered, options: [], range: NSRange(location: 0, length: filtered.utf16.count))
                    print("DEBUG: Removing \(count) directions from staff \(staffNumber)")
                    filtered = regex.stringByReplacingMatches(in: filtered, options: [], range: NSRange(location: 0, length: filtered.utf16.count), withTemplate: "")
                }
            }
        }

        return filtered
    }    /// Hide disabled parts by removing their content from MusicXML
    /// Verovio doesn't respect print-object="no" for rendering, so we must remove elements
    private func hideDisabledParts(in musicXML: String, enabledIds: Set<String>) -> String {
        var filtered = musicXML

        // Remove notes from disabled parts
        for (partId, _) in availableParts {
            if !enabledIds.contains(partId) {
                print("DEBUG: Removing content from part \(partId)")
                
                // Find and remove all notes in this part
                let partPattern = "(<part id=\"\(partId)\">)(.*?)(</part>)"
                if let partRegex = try? NSRegularExpression(pattern: partPattern, options: [.dotMatchesLineSeparators]),
                   let match = partRegex.firstMatch(in: filtered, options: [], range: NSRange(location: 0, length: filtered.utf16.count)),
                   match.numberOfRanges >= 4 {
                    
                    var partContent = (filtered as NSString).substring(with: match.range(at: 2))
                    
                    // Remove all notes
                    let notePattern = "<note(?:(?!</note>).)*</note>"
                    if let noteRegex = try? NSRegularExpression(pattern: notePattern, options: [.dotMatchesLineSeparators]) {
                        let count = noteRegex.numberOfMatches(in: partContent, options: [], range: NSRange(location: 0, length: partContent.utf16.count))
                        print("DEBUG: Removing \(count) notes from part \(partId)")
                        partContent = noteRegex.stringByReplacingMatches(in: partContent, options: [], range: NSRange(location: 0, length: partContent.utf16.count), withTemplate: "")
                    }
                    
                    // Remove all directions
                    let directionPattern = "<direction(?:(?!</direction>).)*</direction>"
                    if let directionRegex = try? NSRegularExpression(pattern: directionPattern, options: [.dotMatchesLineSeparators]) {
                        let count = directionRegex.numberOfMatches(in: partContent, options: [], range: NSRange(location: 0, length: partContent.utf16.count))
                        print("DEBUG: Removing \(count) directions from part \(partId)")
                        partContent = directionRegex.stringByReplacingMatches(in: partContent, options: [], range: NSRange(location: 0, length: partContent.utf16.count), withTemplate: "")
                    }
                    
                    filtered = (filtered as NSString).replacingCharacters(in: match.range(at: 2), with: partContent)
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
