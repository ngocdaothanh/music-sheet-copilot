//
//  MusicSheetView.swift
//  MusicSheetsCopilot
//
//  Created on November 4, 2025.
//

import SwiftUI

struct MusicSheetView: View {
    let score: MusicScore

    @State private var scale: CGFloat = 1.0

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 30) {
                // Title and composer
                VStack(alignment: .center, spacing: 8) {
                    Text(score.title)
                        .font(.title)
                        .fontWeight(.bold)

                    if let composer = score.composer {
                        Text(composer)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)

                // Render each part
                ForEach(Array(score.parts.enumerated()), id: \.offset) { index, part in
                    VStack(alignment: .leading, spacing: 10) {
                        if !part.name.isEmpty {
                            Text(part.name)
                                .font(.headline)
                        }

                        StaffView(part: part)
                    }
                }
            }
            .padding(40)
            .scaleEffect(scale)
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: { scale = max(0.5, scale - 0.1) }) {
                    Image(systemName: "minus.magnifyingglass")
                }

                Button(action: { scale = min(2.0, scale + 0.1) }) {
                    Image(systemName: "plus.magnifyingglass")
                }

                Button(action: { scale = 1.0 }) {
                    Text("100%")
                }
            }
        }
    }
}

struct StaffView: View {
    let part: MusicScore.Part

    let staffLineSpacing: CGFloat = 10
    let measureWidth: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            ForEach(splitIntoSystems(measures: part.measures), id: \.0) { systemIndex, systemMeasures in
                SystemView(
                    measures: systemMeasures,
                    staffLineSpacing: staffLineSpacing,
                    measureWidth: measureWidth
                )
            }
        }
    }

    // Split measures into systems (lines) - 4 measures per system
    private func splitIntoSystems(measures: [MusicScore.Measure]) -> [(Int, [MusicScore.Measure])] {
        let measuresPerSystem = 4
        var systems: [(Int, [MusicScore.Measure])] = []

        for (index, chunk) in measures.chunked(into: measuresPerSystem).enumerated() {
            systems.append((index, chunk))
        }

        return systems
    }
}

struct SystemView: View {
    let measures: [MusicScore.Measure]
    let staffLineSpacing: CGFloat
    let measureWidth: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Staff lines
            StaffLinesView(
                lineCount: 5,
                spacing: staffLineSpacing,
                width: measureWidth * CGFloat(measures.count)
            )

            // Measures
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(measures.enumerated()), id: \.offset) { index, measure in
                    MeasureView(
                        measure: measure,
                        staffLineSpacing: staffLineSpacing,
                        width: measureWidth,
                        isFirst: index == 0
                    )
                }
            }
        }
    }
}

struct StaffLinesView: View {
    let lineCount: Int
    let spacing: CGFloat
    let width: CGFloat

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<lineCount, id: \.self) { _ in
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: width, height: 1)
            }
        }
    }
}

struct MeasureView: View {
    let measure: MusicScore.Measure
    let staffLineSpacing: CGFloat
    let width: CGFloat
    let isFirst: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Measure background and border
            Rectangle()
                .stroke(Color.primary, lineWidth: isFirst ? 2 : 1)
                .frame(width: width, height: staffLineSpacing * 4)

            HStack(spacing: 8) {
                // Clef, key, time signature (only in first measure)
                if isFirst, let attributes = measure.attributes {
                    HStack(spacing: 6) {
                        if let clef = attributes.clef {
                            ClefView(clef: clef, spacing: staffLineSpacing)
                                .padding(.leading, 8)
                        }

                        if let key = attributes.key {
                            KeySignatureView(key: key, spacing: staffLineSpacing)
                        }

                        if let time = attributes.time {
                            TimeSignatureView(time: time, spacing: staffLineSpacing)
                        }
                    }
                }

                // Notes
                HStack(spacing: 15) {
                    ForEach(Array(measure.notes.enumerated()), id: \.offset) { index, note in
                        NoteView(note: note, spacing: staffLineSpacing)
                    }
                }
                .padding(.horizontal, 8)

                Spacer()
            }
            .frame(width: width, height: staffLineSpacing * 4)
        }
    }
}

struct ClefView: View {
    let clef: MusicScore.Clef
    let spacing: CGFloat

    var body: some View {
        Text(clefSymbol)
            .font(.system(size: spacing * 4))
            .offset(y: clefOffset)
    }

    private var clefSymbol: String {
        switch clef.sign {
        case "G": return "𝄞"  // Treble clef
        case "F": return "𝄢"  // Bass clef
        case "C": return "𝄡"  // Alto/Tenor clef
        default: return "𝄞"
        }
    }

    private var clefOffset: CGFloat {
        switch clef.sign {
        case "G": return -spacing * 1.5
        case "F": return -spacing * 0.5
        default: return -spacing
        }
    }
}

struct KeySignatureView: View {
    let key: MusicScore.Key
    let spacing: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            if key.fifths > 0 {
                // Sharps
                ForEach(0..<key.fifths, id: \.self) { _ in
                    Text("♯")
                        .font(.system(size: spacing * 2))
                }
            } else if key.fifths < 0 {
                // Flats
                ForEach(0..<abs(key.fifths), id: \.self) { _ in
                    Text("♭")
                        .font(.system(size: spacing * 2))
                }
            }
        }
    }
}

struct TimeSignatureView: View {
    let time: MusicScore.Time
    let spacing: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text("\(time.beats)")
                .font(.system(size: spacing * 1.8, weight: .bold))
            Text("\(time.beatType)")
                .font(.system(size: spacing * 1.8, weight: .bold))
        }
        .offset(y: spacing * 0.5)
    }
}

struct NoteView: View {
    let note: MusicScore.Note
    let spacing: CGFloat

    var body: some View {
        ZStack {
            if note.isRest {
                RestView(type: note.type ?? "quarter", spacing: spacing)
            } else if let pitch = note.pitch {
                VStack(spacing: 0) {
                    // Note head
                    Text(noteHeadSymbol)
                        .font(.system(size: spacing * 2.5))
                        .offset(y: verticalPosition(for: pitch))

                    // Ledger lines if needed
                    LedgerLinesView(pitch: pitch, spacing: spacing)
                }
            }
        }
    }

    private var noteHeadSymbol: String {
        switch note.type {
        case "whole": return "𝅝"
        case "half": return "𝅗𝅥"
        case "quarter", "eighth", "16th":
            return "𝅘𝅥"
        default: return "𝅘𝅥"
        }
    }

    private func verticalPosition(for pitch: MusicScore.Pitch) -> CGFloat {
        // Calculate position on staff (middle C = C4 is on the first ledger line below treble staff)
        let steps = ["C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6]
        let stepValue = steps[pitch.step] ?? 0
        let totalSteps = (pitch.octave - 4) * 7 + stepValue

        // Position relative to middle staff line (B4 in treble clef)
        let referenceSteps = 6  // B4
        let stepsFromReference = totalSteps - referenceSteps

        return CGFloat(stepsFromReference) * spacing * 0.5
    }
}

struct RestView: View {
    let type: String
    let spacing: CGFloat

    var body: some View {
        Text(restSymbol)
            .font(.system(size: spacing * 2))
            .offset(y: spacing)
    }

    private var restSymbol: String {
        switch type {
        case "whole": return "𝄻"
        case "half": return "𝄼"
        case "quarter": return "𝄽"
        case "eighth": return "𝄾"
        default: return "𝄽"
        }
    }
}

struct LedgerLinesView: View {
    let pitch: MusicScore.Pitch
    let spacing: CGFloat

    var body: some View {
        // For now, a simplified version - would need to calculate which ledger lines are needed
        EmptyView()
    }
}

// Helper extension to chunk arrays
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

#Preview {
    let sampleScore = MusicScore(
        title: "Twinkle Twinkle Little Star",
        composer: "Traditional",
        parts: [
            MusicScore.Part(
                id: "P1",
                name: "Piano",
                measures: [
                    MusicScore.Measure(
                        number: 1,
                        attributes: MusicScore.Attributes(
                            divisions: 4,
                            key: MusicScore.Key(fifths: 0, mode: "major"),
                            time: MusicScore.Time(beats: 4, beatType: 4),
                            clef: MusicScore.Clef(sign: "G", line: 2)
                        ),
                        notes: [
                            MusicScore.Note(
                                pitch: MusicScore.Pitch(step: "C", octave: 4, alter: nil),
                                duration: 4,
                                type: "quarter",
                                isRest: false,
                                stem: "up",
                                beam: nil
                            )
                        ]
                    )
                ]
            )
        ]
    )

    NavigationStack {
        MusicSheetView(score: sampleScore)
    }
}
