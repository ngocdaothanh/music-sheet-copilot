//
//  MusicScore.swift
//  MusicSheetsCopilot
//
//  Created on November 4, 2025.
//

import Foundation

// Data model representing a parsed music score
struct MusicScore {
    let title: String
    let composer: String?
    let parts: [Part]

    struct Part {
        let id: String
        let name: String
        let measures: [Measure]
    }

    struct Measure {
        let number: Int
        let attributes: Attributes?
        let notes: [Note]
    }

    struct Attributes {
        let divisions: Int?
        let key: Key?
        let time: Time?
        let clef: Clef?
    }

    struct Key {
        let fifths: Int  // Number of sharps (positive) or flats (negative)
        let mode: String?
    }

    struct Time {
        let beats: Int
        let beatType: Int
    }

    struct Clef {
        let sign: String  // G, F, C
        let line: Int
    }

    struct Note {
        let pitch: Pitch?
        let duration: Int
        let type: String?  // whole, half, quarter, eighth, etc.
        let isRest: Bool
        let stem: String?  // up, down
        let beam: [String]?
    }

    struct Pitch {
        let step: String  // C, D, E, F, G, A, B
        let octave: Int
        let alter: Int?   // -1 for flat, 1 for sharp
    }
}
