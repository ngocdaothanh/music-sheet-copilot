//
//  MXLDecompressor.swift
//  MusicSheetsCopilot
//
//  Created on November 4, 2025.
//

import Foundation
import UniformTypeIdentifiers

/// Utility for decompressing MusicXML (.mxl) files
/// MXL files are ZIP archives containing MusicXML and metadata
class MXLDecompressor {

    /// Decompress an .mxl file and extract the MusicXML content
    /// - Parameter mxlData: The compressed .mxl file data
    /// - Returns: The decompressed MusicXML data
    /// - Throws: DecompressionError if the file cannot be decompressed or parsed
    static func decompress(_ mxlData: Data) throws -> Data {
        // Create a temporary directory for decompression
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            // Clean up temporary directory
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Write the .mxl data to a temporary file
        let mxlFile = tempDir.appendingPathComponent("temp.mxl")
        try mxlData.write(to: mxlFile)

        // Use Process to unzip (available on macOS and iOS)
        let unzipDestination = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: unzipDestination, withIntermediateDirectories: true)

        #if os(macOS)
        // Use the system unzip command on macOS
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", mxlFile.path, "-d", unzipDestination.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DecompressionError.unzipFailed
        }
        #else
        // On iOS, use Archive/Compression framework (iOS 15+)
        // Or fallback to manual ZIP parsing
        try unzipUsingFoundation(from: mxlFile, to: unzipDestination)
        #endif

        // Look for the MusicXML file
        let musicXMLData = try findMusicXMLFile(in: unzipDestination)

        return musicXMLData
    }

    #if !os(macOS)
    /// Fallback unzip implementation using Foundation
    private static func unzipUsingFoundation(from source: URL, to destination: URL) throws {
        // For iOS 15+, we can use the Compression framework
        // For earlier versions, this is a simplified implementation
        // In production, you'd want to use a proper ZIP library or require iOS 15+

        let sourceData = try Data(contentsOf: source)

        // Simple ZIP header check (PK\x03\x04)
        guard sourceData.count >= 4,
              sourceData[0] == 0x50, // P
              sourceData[1] == 0x4B, // K
              sourceData[2] == 0x03,
              sourceData[3] == 0x04 else {
            throw DecompressionError.invalidZipFile
        }

        // For a complete implementation, parse the ZIP file structure
        // For now, throw an error directing to use macOS or provide uncompressed file
        throw DecompressionError.platformNotSupported
    }
    #endif

    /// Find and read the MusicXML file within the decompressed directory
    private static func findMusicXMLFile(in directory: URL) throws -> Data {
        let fileManager = FileManager.default

        // Method 1: Check META-INF/container.xml for the root file path
        let containerFile = directory
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")

        if fileManager.fileExists(atPath: containerFile.path) {
            if let rootFile = parseContainerXML(at: containerFile) {
                let musicXMLFile = directory.appendingPathComponent(rootFile)
                if fileManager.fileExists(atPath: musicXMLFile.path) {
                    return try Data(contentsOf: musicXMLFile)
                }
            }
        }

        // Method 2: Look for common MusicXML file patterns
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)

        while let fileURL = enumerator?.nextObject() as? URL {
            let filename = fileURL.lastPathComponent.lowercased()
            let ext = fileURL.pathExtension.lowercased()

            // Look for .xml files (excluding META-INF files)
            if ext == "xml" && !fileURL.path.contains("META-INF") {
                return try Data(contentsOf: fileURL)
            }

            // Also check for .musicxml extension
            if ext == "musicxml" {
                return try Data(contentsOf: fileURL)
            }
        }

        throw DecompressionError.noMusicXMLFound
    }

    /// Parse the META-INF/container.xml file to find the root MusicXML file
    private static func parseContainerXML(at url: URL) -> String? {
        guard let xmlString = try? String(contentsOf: url) else {
            return nil
        }

        // Simple XML parsing to extract the rootfile full-path attribute
        // Example: <rootfile full-path="score.xml" media-type="application/vnd.recordare.musicxml+xml"/>

        let pattern = #"<rootfile\s+full-path="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: xmlString,
                range: NSRange(xmlString.startIndex..., in: xmlString)
              ) else {
            return nil
        }

        if let range = Range(match.range(at: 1), in: xmlString) {
            return String(xmlString[range])
        }

        return nil
    }
}

enum DecompressionError: Error, LocalizedError {
    case unzipFailed
    case noMusicXMLFound
    case invalidContainer
    case invalidZipFile
    case platformNotSupported

    var errorDescription: String? {
        switch self {
        case .unzipFailed:
            return "Failed to decompress .mxl file"
        case .noMusicXMLFound:
            return "No MusicXML file found in .mxl archive"
        case .invalidContainer:
            return "Invalid or missing container.xml in .mxl file"
        case .invalidZipFile:
            return "Invalid ZIP file format"
        case .platformNotSupported:
            return "Compressed .mxl files are currently only supported on macOS. Please use an uncompressed .xml or .musicxml file on iOS."
        }
    }
}
