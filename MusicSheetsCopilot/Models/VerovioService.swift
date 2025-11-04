//
//  VerovioService.swift
//  MusicSheetsCopilot
//
//  Created on November 4, 2025.
//

import Foundation
import VerovioToolkit

/// A service class to interact with the Verovio music notation library
class VerovioService {
    private let toolkit: VerovioToolkit

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