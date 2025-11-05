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
    @State private var showTempoPopover = false

    /// Playback mode: MIDI playback with optional metronome, or metronome-only for practice
    enum PlaybackMode {
        case midiWithMetronome  // Play MIDI, metronome enabled/disabled by toggle
        case metronomeOnly      // Play only metronome (for practicing on real piano)
    }
    @State private var playbackMode: PlaybackMode = .midiWithMetronome

    /// Tracks if metronome-only playback is active
    @State private var isMetronomeOnlyPlaying = false

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
            // Stop metronome when MIDI playback stops (e.g., when song finishes)
            if !isPlaying && metronome.isTicking && playbackMode == .midiWithMetronome {
                metronome.stop()
            }
        }
        .onChange(of: isMetronomeOnlyPlaying) { isPlaying in
            // When metronome-only mode stops, stop the metronome
            if !isPlaying && metronome.isTicking {
                metronome.stop()
            }
        }
        .onChange(of: playbackMode) { newMode in
            // Stop any current playback when switching modes
            if midiPlayer.isPlaying {
                midiPlayer.stop()
            }
            if isMetronomeOnlyPlaying {
                isMetronomeOnlyPlaying = false
            }
            metronome.stop()
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
                        togglePlayback()
                    }) {
                        let isAnyPlaying = midiPlayer.isPlaying || isMetronomeOnlyPlaying
                        Image(systemName: isAnyPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    .help(getPlayButtonHelp())

                    Divider()

                    // Playback mode selector
                    Menu {
                        Button {
                            playbackMode = .midiWithMetronome
                        } label: {
                            HStack {
                                if playbackMode == .midiWithMetronome {
                                    Image(systemName: "checkmark")
                                }
                                Text("MIDI Playback")
                            }
                        }

                        Button {
                            playbackMode = .metronomeOnly
                            // Auto-enable metronome when switching to metronome-only mode
                            if !metronome.isEnabled {
                                metronome.isEnabled = true
                            }
                        } label: {
                            HStack {
                                if playbackMode == .metronomeOnly {
                                    Image(systemName: "checkmark")
                                }
                                Text("Metronome Only (Practice)")
                            }
                        }
                    } label: {
                        Image(systemName: playbackMode == .midiWithMetronome ? "speaker.wave.2.fill" : "metronome.fill")
                    }
                    .help(playbackMode == .midiWithMetronome ? "Playing MIDI with optional metronome" : "Playing metronome only for practice")

                    Divider()

                    // Metronome toggle (only show in MIDI mode, always enabled in metronome-only mode)
                    if playbackMode == .midiWithMetronome {
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
                    }

                    // Metronome mode selector (only show when metronome is enabled)
                    if metronome.isEnabled {
                        Menu {
                            Button {
                                metronome.mode = .tick
                                if metronome.isTicking {
                                    metronome.stop()
                                    metronome.start()
                                }
                            } label: {
                                HStack {
                                    if metronome.mode == .tick {
                                        Image(systemName: "checkmark")
                                    }
                                    Text("Tick")
                                }
                            }
                            Button {
                                metronome.mode = .counting
                                if metronome.isTicking {
                                    metronome.stop()
                                    metronome.start()
                                }
                            } label: {
                                HStack {
                                    if metronome.mode == .counting {
                                        Image(systemName: "checkmark")
                                    }
                                    Text("Count (1-2-3-4)")
                                }
                            }
                            Button {
                                metronome.mode = .solfege
                                if metronome.isTicking {
                                    metronome.stop()
                                    metronome.start()
                                }
                            } label: {
                                HStack {
                                    if metronome.mode == .solfege {
                                        Image(systemName: "checkmark")
                                    }
                                    Text("Solfege (Do-Re-Mi)")
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

                    // Tempo adjustment with BPM display
                    Button(action: {
                        showTempoPopover.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "metronome.fill")
                            let baseBPM = verovioService.getTempoBPM() ?? 120.0
                            let currentBPM = baseBPM * Double(midiPlayer.playbackRate)
                            Text("\(Int(currentBPM)) BPM")
                        }
                    }
                    .help("Adjust Tempo")
                    .popover(isPresented: $showTempoPopover) {
                        TempoSliderView(
                            baseBPM: verovioService.getTempoBPM() ?? 120.0,
                            playbackRate: $midiPlayer.playbackRate,
                            onRateChange: { rate in
                                setPlaybackRate(rate)
                            }
                        )
                        .frame(width: 300, height: 120)
                        .padding()
                    }

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

    // MARK: - Playback Control Methods

    /// Toggle playback based on current mode (MIDI or metronome-only)
    private func togglePlayback() {
        switch playbackMode {
        case .midiWithMetronome:
            midiPlayer.togglePlayPause()
            // Sync metronome with MIDI playback
            if midiPlayer.isPlaying && metronome.isEnabled {
                let bpm = verovioService.getTempoBPM() ?? 120.0
                metronome.bpm = bpm
                metronome.start()
            } else {
                metronome.stop()
            }

        case .metronomeOnly:
            isMetronomeOnlyPlaying.toggle()
            if isMetronomeOnlyPlaying {
                // Start metronome-only playback
                let bpm = verovioService.getTempoBPM() ?? 120.0
                metronome.bpm = bpm
                metronome.isEnabled = true  // Ensure metronome is enabled
                metronome.start()
            } else {
                // Stop metronome
                metronome.stop()
            }
        }
    }

    /// Get appropriate help text for the play button based on current mode and state
    private func getPlayButtonHelp() -> String {
        let isAnyPlaying = midiPlayer.isPlaying || isMetronomeOnlyPlaying

        switch playbackMode {
        case .midiWithMetronome:
            return isAnyPlaying ? "Pause MIDI Playback" : "Play MIDI"
        case .metronomeOnly:
            return isAnyPlaying ? "Stop Metronome" : "Play Metronome (Practice Mode)"
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
                // Pass note events to metronome for metronome-only mode
                metronome.setNoteEvents(midiPlayer.noteEvents)
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

// MARK: - Tempo Slider View
struct TempoSliderView: View {
    let baseBPM: Double
    @Binding var playbackRate: Float
    let onRateChange: (Float) -> Void

    @State private var localRate: Double

    init(baseBPM: Double, playbackRate: Binding<Float>, onRateChange: @escaping (Float) -> Void) {
        self.baseBPM = baseBPM
        self._playbackRate = playbackRate
        self.onRateChange = onRateChange
        self._localRate = State(initialValue: Double(playbackRate.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Tempo Adjustment")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Tempo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(baseBPM * localRate)) BPM")
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Original")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(baseBPM)) BPM")
                        .font(.subheadline)
                }
            }

            HStack(spacing: 12) {
                Text("50%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 35)

                Slider(value: $localRate, in: 0.5...2.0, step: 0.05) { editing in
                    if !editing {
                        let newRate = Float(localRate)
                        playbackRate = newRate
                        onRateChange(newRate)
                    }
                }
                .onChange(of: localRate) { newValue in
                    // Update in real-time while dragging
                    let newRate = Float(newValue)
                    playbackRate = newRate
                    onRateChange(newRate)
                }

                Text("200%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 35)
            }

            HStack(spacing: 8) {
                Button("Reset") {
                    localRate = 1.0
                    playbackRate = 1.0
                    onRateChange(1.0)
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("\(Int(localRate * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }
}
