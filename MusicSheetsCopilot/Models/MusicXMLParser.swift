//
//  MusicXMLParser.swift
//  MusicSheetsCopilot
//
//  Created on November 4, 2025.
//

import Foundation

enum MusicXMLParserError: Error {
    case invalidXML
    case missingRequiredElement(String)
}

class MusicXMLParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentText = ""

    // Score-level data
    private var title = ""
    private var composer: String?
    private var parts: [MusicScore.Part] = []

    // Part-level data
    private var currentPartId = ""
    private var currentPartName = ""
    private var measures: [MusicScore.Measure] = []

    // Measure-level data
    private var currentMeasureNumber = 0
    private var currentAttributes: MusicScore.Attributes?
    private var notes: [MusicScore.Note] = []

    // Attributes data
    private var divisions: Int?
    private var keyFifths: Int?
    private var keyMode: String?
    private var timeBeats: Int?
    private var timeBeatType: Int?
    private var clefSign: String?
    private var clefLine: Int?

    // Note data
    private var isRest = false
    private var noteDuration: Int?
    private var noteType: String?
    private var pitchStep: String?
    private var pitchOctave: Int?
    private var pitchAlter: Int?
    private var noteStem: String?

    func parse(data: Data) throws -> MusicScore {
        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw MusicXMLParserError.invalidXML
        }

        return MusicScore(
            title: title.isEmpty ? "Untitled" : title,
            composer: composer,
            parts: parts
        )
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "part":
            currentPartId = attributeDict["id"] ?? ""
            measures = []
        case "measure":
            if let numberStr = attributeDict["number"], let number = Int(numberStr) {
                currentMeasureNumber = number
            }
            notes = []
            currentAttributes = nil
        case "note":
            isRest = false
            noteDuration = nil
            noteType = nil
            pitchStep = nil
            pitchOctave = nil
            pitchAlter = nil
            noteStem = nil
        case "rest":
            isRest = true
        case "attributes":
            divisions = nil
            keyFifths = nil
            keyMode = nil
            timeBeats = nil
            timeBeatType = nil
            clefSign = nil
            clefLine = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "movement-title", "work-title":
            if title.isEmpty {
                title = currentText
            }
        case "creator":
            if composer == nil {
                composer = currentText
            }
        case "part-name":
            currentPartName = currentText
        case "part":
            parts.append(MusicScore.Part(
                id: currentPartId,
                name: currentPartName,
                measures: measures
            ))
        case "measure":
            measures.append(MusicScore.Measure(
                number: currentMeasureNumber,
                attributes: currentAttributes,
                notes: notes
            ))
        case "attributes":
            var key: MusicScore.Key?
            if let fifths = keyFifths {
                key = MusicScore.Key(fifths: fifths, mode: keyMode)
            }

            var time: MusicScore.Time?
            if let beats = timeBeats, let beatType = timeBeatType {
                time = MusicScore.Time(beats: beats, beatType: beatType)
            }

            var clef: MusicScore.Clef?
            if let sign = clefSign, let line = clefLine {
                clef = MusicScore.Clef(sign: sign, line: line)
            }

            currentAttributes = MusicScore.Attributes(
                divisions: divisions,
                key: key,
                time: time,
                clef: clef
            )
        case "note":
            var pitch: MusicScore.Pitch?
            if let step = pitchStep, let octave = pitchOctave {
                pitch = MusicScore.Pitch(step: step, octave: octave, alter: pitchAlter)
            }

            notes.append(MusicScore.Note(
                pitch: pitch,
                duration: noteDuration ?? 0,
                type: noteType,
                isRest: isRest,
                stem: noteStem,
                beam: nil
            ))
        case "divisions":
            divisions = Int(currentText)
        case "fifths":
            keyFifths = Int(currentText)
        case "mode":
            keyMode = currentText
        case "beats":
            timeBeats = Int(currentText)
        case "beat-type":
            timeBeatType = Int(currentText)
        case "sign":
            clefSign = currentText
        case "line":
            if currentElement == "line" {
                clefLine = Int(currentText)
            }
        case "step":
            pitchStep = currentText
        case "octave":
            pitchOctave = Int(currentText)
        case "alter":
            pitchAlter = Int(currentText)
        case "duration":
            noteDuration = Int(currentText)
        case "type":
            noteType = currentText
        case "stem":
            noteStem = currentText
        default:
            break
        }

        currentText = ""
    }
}
