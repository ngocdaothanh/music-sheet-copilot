//
//  ContentView.swift
//  MusicSheetsCopilot
//
//  Created on November 4, 2025.
//

import SwiftUI
import UniformTypeIdentifiers

import AVFoundation

// Add metronome support
import Combine

struct ContentView: View {
    @State private var svgPages: [String]?
    @State private var timingData: String?
    @State private var documentTitle: String = "Music Sheets"
    @State private var isImporting = false
    @State private var errorMessage: String?
    @StateObject private var midiPlayer = MIDIPlayer()
    @StateObject private var verovioService = VerovioService()

    @StateObject private var metronome = Metronome()
    @State private var metronomeCancellable: AnyCancellable?

    init() {
        // Can't set metronome.midiPlayer in init with @StateObject
        // Will set it in onAppear
    }

    var body: some View {
        VStack(spacing: 0) {
            if let pages = svgPages, let timing = timingData {
                MultiPageSVGMusicSheetView(svgPages: pages, timingData: timing, midiPlayer: midiPlayer)
                    .environmentObject(verovioService)
                    .environmentObject(midiPlayer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)

                    Text("Music Sheets")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Load a MusicXML or .mxl file or try the demo")
                        .foregroundColor(.secondary)

                    HStack(spacing: 15) {
                        Button("Load Demo") {
                            loadDemoFile()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open File...") {
                            isImporting = true
                        }
                        .buttonStyle(.bordered)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                    }
                }
                .padding()
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [
                .xml,
                UTType(filenameExtension: "musicxml") ?? .xml,
                UTType(filenameExtension: "mxl") ?? .xml
            ],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDocument)) { _ in
            isImporting = true
        }
        .onChange(of: midiPlayer.isPlaying) { isPlaying in
            // Stop metronome when playback stops (e.g., when song finishes)
            if !isPlaying && metronome.isTicking {
                metronome.stop()
            }
        }
        .onAppear {
            // Set the MIDIPlayer reference for the metronome
            metronome.midiPlayer = midiPlayer
        }
        .navigationTitle(documentTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup {
                if svgPages != nil {
                    // Play/Pause button
                    Button(action: {
                        midiPlayer.togglePlayPause()
                        // Sync metronome with playback
                        if midiPlayer.isPlaying {
                            // Set BPM from VerovioService if available, else default
                            let bpm = verovioService.getTempoBPM() ?? 120.0
                            metronome.bpm = bpm
                            metronome.start()
                        } else {
                            metronome.stop()
                        }
                    }) {
                        Image(systemName: midiPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    .help(midiPlayer.isPlaying ? "Pause" : "Play")

                    Divider()

                    // Metronome toggle
                    Toggle(isOn: $metronome.isEnabled) {
                        Image(systemName: "metronome")
                    }
                    .toggleStyle(.button)
                    .help(metronome.isEnabled ? "Disable Metronome" : "Enable Metronome")
                    .onChange(of: metronome.isEnabled) { enabled in
                        if enabled && midiPlayer.isPlaying {
                            let bpm = verovioService.getTempoBPM() ?? 120.0
                            metronome.bpm = bpm
                            metronome.start()
                        } else {
                            metronome.stop()
                        }
                    }

                    // Metronome mode selector (only show when metronome is enabled)
                    if metronome.isEnabled {
                        Menu {
                            Button("Tick") {
                                metronome.mode = .tick
                                if metronome.isTicking {
                                    metronome.stop()
                                    metronome.start()
                                }
                            }
                            Button("Count (1-2-3-4)") {
                                metronome.mode = .counting
                                if metronome.isTicking {
                                    metronome.stop()
                                    metronome.start()
                                }
                            }
                            Button("Solfege (Do-Re-Mi)") {
                                metronome.mode = .solfege
                                if metronome.isTicking {
                                    metronome.stop()
                                    metronome.start()
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                switch metronome.mode {
                                case .tick:
                                    Image(systemName: "waveform")
                                case .counting:
                                    Image(systemName: "textformat.123")
                                case .solfege:
                                    Image(systemName: "music.note")
                                }
                            }
                        }
                        .help("Metronome Mode")
                    }

                    Divider()

                    // Tempo adjustment
                    Menu {
                        Button("0.5x (Half Speed)") {
                            setPlaybackRate(0.5)
                        }
                        Button("0.75x") {
                            setPlaybackRate(0.75)
                        }
                        Button("1.0x (Normal)") {
                            setPlaybackRate(1.0)
                        }
                        Button("1.25x") {
                            setPlaybackRate(1.25)
                        }
                        Button("1.5x") {
                            setPlaybackRate(1.5)
                        }
                        Button("2.0x (Double Speed)") {
                            setPlaybackRate(2.0)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gauge.with.dots.needle.50percent")
                            Text(String(format: "%.2fx", midiPlayer.playbackRate))
                        }
                    }
                    .help("Adjust Playback Speed")

                    Divider()

                    Button("Load Another") {
                        isImporting = true
                    }

                    Button("Demo") {
                        loadDemoFile()
                    }
                }
            }
        }
    }

    private func setPlaybackRate(_ rate: Float) {
        midiPlayer.playbackRate = rate
        metronome.playbackRate = rate
    }

    private func loadDemoFile() {
        guard let url = Bundle.main.url(forResource: "twinkle_twinkle", withExtension: "xml") else {
            errorMessage = "Demo file not found"
            return
        }

        loadMusicXML(from: url)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            loadMusicXML(from: url)
        case .failure(let error):
            errorMessage = "Failed to open file: \(error.localizedDescription)"
        }
    }

    private func loadMusicXML(from url: URL) {
        print("loadMusicXML")
        errorMessage = nil

        do {
            var data = try Data(contentsOf: url)

            // Check if this is a compressed .mxl file
            let fileExtension = url.pathExtension.lowercased()
            if fileExtension == "mxl" {
                print("Decompressing .mxl file...")
                data = try MXLDecompressor.decompress(data)
                print("Successfully decompressed .mxl file")
            }

            // Render all pages with Verovio
            let pages = try verovioService.renderAllPages(data: data)
            print("ContentView received \(pages.count) page(s)")
            svgPages = pages

            // Get timing information for accurate note highlighting
            let timing = verovioService.getTimingMap()
            timingData = timing
            print("Timing data length: \(timing.count) chars")
            print("Timing data preview (first 500 chars): \(String(timing.prefix(500)))")

            // Get MIDI data and load into player
            let midiString = verovioService.getMIDI()
            if let midiData = Data(base64Encoded: midiString) {
                try midiPlayer.loadMIDI(data: midiData)
                print("MIDI loaded successfully")
                // Set metronome BPM from VerovioService if available
                let bpm = verovioService.getTempoBPM() ?? 120.0
                metronome.bpm = bpm
            } else {
                print("Failed to decode MIDI data from base64")
            }

            // Extract title from filename if needed
            documentTitle = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "_", with: " ")
                .capitalized

        } catch {
            errorMessage = "Failed to render MusicXML: \(error.localizedDescription)"
            svgPages = nil
        }
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}
