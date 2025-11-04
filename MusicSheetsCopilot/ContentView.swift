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
                // Metronome visual indicator
                MetronomeVisualView(metronome: metronome)
                    .padding(.top, 8)

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

                    Text("Load a MusicXML or .mxl file or try a demo")
                        .foregroundColor(.secondary)

                    HStack(spacing: 15) {
                        Menu {
                            Button("Twinkle Twinkle Little Star") {
                                loadDemoFile(named: "twinkle_twinkle")
                            }
                            Button("Für Elise (Easy Piano)") {
                                loadDemoFile(named: "fur_elise")
                            }
                        } label: {
                            Text("Load Demo")
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

            // Sync time signature from MIDIPlayer to Metronome
            metronomeCancellable = midiPlayer.$timeSignature
                .sink { newTimeSignature in
                    metronome.timeSignature = newTimeSignature
                }
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

                    // Staves selector (show if multiple staves available)
                    if verovioService.availableStaves.count > 1 {
                        Menu {
                            ForEach(verovioService.availableStaves, id: \.1) { partId, staffNumber, staffName in
                                Button(action: {
                                    toggleStaff(partId: partId, staffNumber: staffNumber)
                                }) {
                                    HStack {
                                        let staveKey = "\(partId)-\(staffNumber)"
                                        if verovioService.enabledStaves.contains(staveKey) {
                                            Image(systemName: "checkmark")
                                        }
                                        Text(staffName)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "music.note.list")
                                Text("\(verovioService.enabledStaves.count)/\(verovioService.availableStaves.count)")
                            }
                        }
                        .help("Select Staves")

                        Divider()
                    }
                    // Parts selector (only show if multiple parts available)
                    else if verovioService.availableParts.count > 1 {
                        Menu {
                            ForEach(verovioService.availableParts, id: \.0) { partId, partName in
                                Button(action: {
                                    togglePart(partId)
                                }) {
                                    HStack {
                                        if verovioService.enabledPartIds.contains(partId) {
                                            Image(systemName: "checkmark")
                                        }
                                        Text(partName)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "music.note.list")
                                Text("\(verovioService.enabledPartIds.count)/\(verovioService.availableParts.count)")
                            }
                        }
                        .help("Select Parts")

                        Divider()
                    }

                    Button("Load Another") {
                        isImporting = true
                    }

                    Menu {
                        Button("Twinkle Twinkle Little Star") {
                            loadDemoFile(named: "twinkle_twinkle")
                        }
                        Button("Für Elise (Easy Piano)") {
                            loadDemoFile(named: "fur_elise")
                        }
                    } label: {
                        Text("Demo")
                    }
                }
            }
        }
    }

    private func setPlaybackRate(_ rate: Float) {
        midiPlayer.playbackRate = rate
        metronome.playbackRate = rate
    }

    private func toggleStaff(partId: String, staffNumber: Int) {
        let staveKey = "\(partId)-\(staffNumber)"

        if verovioService.enabledStaves.contains(staveKey) {
            // Don't allow disabling all staves
            if verovioService.enabledStaves.count > 1 {
                verovioService.enabledStaves.remove(staveKey)
                reloadScore()
            }
        } else {
            verovioService.enabledStaves.insert(staveKey)
            reloadScore()
        }
    }

    private func togglePart(_ partId: String) {
        if verovioService.enabledPartIds.contains(partId) {
            // Don't allow disabling all parts
            if verovioService.enabledPartIds.count > 1 {
                verovioService.enabledPartIds.remove(partId)
                reloadScore()
            }
        } else {
            verovioService.enabledPartIds.insert(partId)
            reloadScore()
        }
    }

    private func reloadScore() {
        // Reload the score with current enabled parts
        guard let xmlData = verovioService.lastLoadedData else { return }

        do {
            let pages = try verovioService.renderAllPages(data: xmlData)
            svgPages = pages

            let timing = verovioService.getTimingMap()
            timingData = timing

            let midiString = verovioService.getMIDI()
            if let midiData = Data(base64Encoded: midiString) {
                try midiPlayer.loadMIDI(data: midiData)
                let bpm = verovioService.getTempoBPM() ?? 120.0
                metronome.bpm = bpm
            }
        } catch {
            errorMessage = "Failed to reload score: \(error.localizedDescription)"
        }
    }

    private func loadDemoFile(named fileName: String = "twinkle_twinkle") {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "xml") else {
            errorMessage = "Demo file not found: \(fileName)"
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
        errorMessage = nil

        do {
            var data = try Data(contentsOf: url)

            // Check if this is a compressed .mxl file
            let fileExtension = url.pathExtension.lowercased()
            if fileExtension == "mxl" {
                data = try MXLDecompressor.decompress(data)
            }

            // Render all pages with Verovio
            let pages = try verovioService.renderAllPages(data: data)
            svgPages = pages

            // Get timing information for accurate note highlighting
            let timing = verovioService.getTimingMap()
            timingData = timing

            // Get MIDI data and load into player
            let midiString = verovioService.getMIDI()
            if let midiData = Data(base64Encoded: midiString) {
                try midiPlayer.loadMIDI(data: midiData)
                // Set metronome BPM from VerovioService if available
                let bpm = verovioService.getTempoBPM() ?? 120.0
                metronome.bpm = bpm
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
