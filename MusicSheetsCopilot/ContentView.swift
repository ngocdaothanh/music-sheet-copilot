import SwiftUI
import UniformTypeIdentifiers

import AVFoundation

// Add metronome support
import Combine

struct ContentView: View {
    @State private var svgPages: [String]?
    @State private var timingData: String?
    @State private var isImporting = false
    @State private var errorMessage: String?
    @StateObject private var midiPlayer = MIDIPlayer()
    @StateObject private var verovioService = VerovioService()
    // Staves selected for MIDI playback ("Play for me")
    @State private var selectedStavesForPlayback: Set<String> = []

    @StateObject private var metronome = Metronome()
    @State private var metronomeCancellable: AnyCancellable?
    @State private var showTempoPopover = false

    // Visual-only playback state: when playing without audio (no selected staves
    // and metronome disabled) we advance the visual position via a timer.
    @State private var visualPlaybackTimer: Timer?
    @State private var isVisualPlaying: Bool = false
    @State private var noteNameMode: NoteNameMode = .none

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

                MultiPageSVGMusicSheetView(
                    svgPages: pages,
                    timingData: timing,
                    midiPlayer: midiPlayer,
                    metronome: metronome,
                    // Use metronome time only when metronome is enabled AND MIDI is not playing.
                    // When MIDI is playing, prefer the MIDI player's time for precise highlighting.
                    currentTimeOverride: (metronome.isEnabled && !midiPlayer.isPlaying) ? metronome.currentTime : nil,
                    isPlayingOverride: (metronome.isEnabled && !midiPlayer.isPlaying) ? metronome.isTicking : (isVisualPlaying ? true : nil),
                    noteNameMode: noteNameMode
                )
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
        .onChange(of: midiPlayer.isPlaying) { oldValue, newValue in
            // Only stop metronome if MIDI playback truly stopped at the end, not after a seek
            let atEnd = midiPlayer.duration > 0 && abs(midiPlayer.currentTime - midiPlayer.duration) < 0.1
            if !newValue && metronome.isTicking && atEnd {
                metronome.stop()
            }
        }
        .onChange(of: metronome.isTicking) {
            // No-op: we no longer have a separate metronome-only playback mode state
            // Keep this hook in case other components depend on metronome.isTicking
        }
        // React to changes in the user's "Play for me" stave selection
        .onChange(of: selectedStavesForPlayback) {
            updateMIDISelection()
        }
        .onAppear {
            // Set the MIDIPlayer reference for the metronome
            metronome.midiPlayer = midiPlayer

            // Sync time signature from MIDIPlayer to Metronome
            metronomeCancellable = midiPlayer.$timeSignature
                .sink { newTimeSignature in
                    metronome.timeSignature = newTimeSignature
                }
            // Ensure metronome honors the current playback rate (e.g., default 50%)
            metronome.playbackRate = midiPlayer.playbackRate
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if svgPages != nil {
                    // Demo menu (Load demos)
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
                    .buttonStyle(.bordered)

                    // Open File
                    Button("Open File...") {
                        isImporting = true
                    }
                    .buttonStyle(.bordered)

                    // "Play for me" selector: choose staves to include in MIDI playback
                    if verovioService.availableStaves.count > 0 {
                        Menu {
                            ForEach(verovioService.availableStaves.indices, id: \.self) { index in
                                let (partId, staffNumber, staffName) = verovioService.availableStaves[index]
                                let staveKey = "\(partId)-\(staffNumber)"
                                Button(action: {
                                    if selectedStavesForPlayback.contains(staveKey) {
                                        selectedStavesForPlayback.remove(staveKey)
                                    } else {
                                        selectedStavesForPlayback.insert(staveKey)
                                    }
                                }) {
                                    HStack {
                                        if selectedStavesForPlayback.contains(staveKey) {
                                            Image(systemName: "checkmark")
                                        }
                                        Text(staffName)
                                    }
                                }
                            }

                        } label: {
                            HStack {
                                Image(systemName: "play.circle")
                            }
                        }
                        .help("Play for me: select which staves to include in MIDI playback")
                    } else if verovioService.availableParts.count > 1 {
                        // Parts selector (fallback)
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
                            Image(systemName: "music.note.list")
                        }
                        .help("Select Parts")
                    }

                    // Metronome toggle and mode menus
                    Toggle(isOn: $metronome.isEnabled) {
                        Image(systemName: "metronome")
                    }
                    .toggleStyle(.button)
                    .help(metronome.isEnabled ? "Disable Metronome" : "Enable Metronome")
                    .onChange(of: metronome.isEnabled) { oldValue, newValue in
                        if newValue {
                            let bpm = verovioService.getTempoBPM() ?? 120.0
                            metronome.bpm = bpm
                            // Keep metronome playback rate in sync with MIDI player's rate
                            metronome.playbackRate = midiPlayer.playbackRate
                            if midiPlayer.isPlaying || isVisualPlaying || selectedStavesForPlayback.isEmpty {
                                metronome.start()
                            }
                        } else {
                            metronome.stop()
                        }
                    }

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
                                    if metronome.mode == .tick { Image(systemName: "checkmark") }
                                    Text("Tick")
                                }
                            }
                            Button {
                                metronome.mode = .counting
                                if metronome.isTicking { metronome.stop(); metronome.start() }
                            } label: {
                                HStack {
                                    if metronome.mode == .counting { Image(systemName: "checkmark") }
                                    Text("Count (1-2-3-4)")
                                }
                            }
                            Button {
                                metronome.mode = .letter
                                if metronome.isTicking { metronome.stop(); metronome.start() }
                            } label: {
                                HStack {
                                    if metronome.mode == .letter { Image(systemName: "checkmark") }
                                    Text("Letter (C-D-E)")
                                }
                            }
                            Button {
                                metronome.mode = .solfege
                                if metronome.isTicking { metronome.stop(); metronome.start() }
                            } label: {
                                HStack {
                                    if metronome.mode == .solfege { Image(systemName: "checkmark") }
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
                                case .letter:
                                    Image(systemName: "character.textbox")
                                case .solfege:
                                    Image(systemName: "music.note")
                                }
                            }
                        }
                        .help("Metronome Mode")

                        if metronome.mode == .counting {
                            Menu {
                                Button {
                                    metronome.subdivisions = 1
                                    if metronome.isTicking {
                                        metronome.stop()
                                        metronome.start()
                                    }
                                } label: {
                                    HStack {
                                        if metronome.subdivisions == 1 {
                                            Image(systemName: "checkmark")
                                        }
                                        Text("Quarter Notes")
                                    }
                                }

                                Button {
                                    metronome.subdivisions = 2
                                    if metronome.isTicking {
                                        metronome.stop()
                                        metronome.start()
                                    }
                                } label: {
                                    HStack {
                                        if metronome.subdivisions == 2 {
                                            Image(systemName: "checkmark")
                                        }
                                        Text("Eighth Notes (+ and)")
                                    }
                                }

                                Button {
                                    metronome.subdivisions = 4
                                    if metronome.isTicking {
                                        metronome.stop()
                                        metronome.start()
                                    }
                                } label: {
                                    HStack {
                                        if metronome.subdivisions == 4 {
                                            Image(systemName: "checkmark")
                                        }
                                        Text("Sixteenth Notes (+ e and a)")
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "divide.circle")
                                    switch metronome.subdivisions {
                                    case 1:
                                        Text("♩")
                                    case 2:
                                        Text("♫")
                                    case 4:
                                        Text("♬")
                                    default:
                                        Text("♩")
                                    }
                                }
                            }
                            .help("Subdivision Level")
                        }
                    }

                    // Note name display mode (None / Letter / Solfege) - use a list-style Menu like MetronomeMode
                    Menu {
                        ForEach(NoteNameMode.allCases, id: \.self) { mode in
                            Button(action: { noteNameMode = mode }) {
                                HStack {
                                    if noteNameMode == mode { Image(systemName: "checkmark") }
                                    Text(mode.menuTitle)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "textformat")
                            Text(noteNameMode.title)
                                .font(.caption)
                        }
                    }
                    .help("Toggle note name overlays on the score")

                    // Tempo adjustment with BPM display
                    Button(action: { showTempoPopover.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "metronome.fill")
                            let baseBPM = verovioService.getTempoBPM() ?? 120.0
                            let currentBPM = baseBPM * Double(midiPlayer.playbackRate)
                            Text("\(Int(currentBPM)) BPM")
                        }
                    }
                    .help("Adjust Tempo")

                    // Play/Pause button (moved to right-most position)
                    Button(action: { togglePlayback() }) {
                        let isAnyPlaying = midiPlayer.isPlaying || isVisualPlaying
                        Image(systemName: isAnyPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    .help(getPlayButtonHelp())
                }
            }
        }
        #else
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if svgPages != nil {
                    // Demo menu (first)
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
                    .buttonStyle(.bordered)

                    // Open File
                    Button("Open File...") {
                        isImporting = true
                    }
                    .buttonStyle(.bordered)

                    // Note name display mode selector for macOS (list-style like MetronomeMode)
                    Menu {
                        ForEach(NoteNameMode.allCases, id: \.self) { mode in
                            Button(action: { noteNameMode = mode }) {
                                HStack {
                                    if noteNameMode == mode { Image(systemName: "checkmark") }
                                    Text(mode.menuTitle)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "textformat")
                            Text(noteNameMode.title)
                                .font(.caption)
                        }
                    }
                    .help("Toggle note name overlays on the score")

                    // "Play for me" selector: choose staves to include in MIDI playback
                    if verovioService.availableStaves.count > 0 {
                        Menu {
                            ForEach(verovioService.availableStaves.indices, id: \.self) { index in
                                let (partId, staffNumber, staffName) = verovioService.availableStaves[index]
                                let staveKey = "\(partId)-\(staffNumber)"
                                Button(action: {
                                    if selectedStavesForPlayback.contains(staveKey) {
                                        selectedStavesForPlayback.remove(staveKey)
                                    } else {
                                        selectedStavesForPlayback.insert(staveKey)
                                    }
                                }) {
                                    HStack {
                                        if selectedStavesForPlayback.contains(staveKey) {
                                            Image(systemName: "checkmark")
                                        }
                                        Text(staffName)
                                    }
                                }
                            }

                        } label: {
                            HStack {
                                Image(systemName: "play.circle")
                            }
                        }
                        .help("Play for me: select which staves to include in MIDI playback")
                    }
                    // Parts selector (fallback)
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
                            Image(systemName: "music.note.list")
                        }
                        .help("Select Parts")
                    }

                    // Metronome toggle and mode menus
                    Toggle(isOn: $metronome.isEnabled) {
                        Image(systemName: "metronome")
                    }
                    .toggleStyle(.button)
                    .help(metronome.isEnabled ? "Disable Metronome" : "Enable Metronome")
                    .onChange(of: metronome.isEnabled) { oldValue, newValue in
                            if newValue {
                                let bpm = verovioService.getTempoBPM() ?? 120.0
                                metronome.bpm = bpm
                                // Keep metronome playback rate in sync with MIDI player's rate
                                metronome.playbackRate = midiPlayer.playbackRate
                                if midiPlayer.isPlaying || isVisualPlaying || selectedStavesForPlayback.isEmpty {
                                    metronome.start()
                                }
                            } else {
                                metronome.stop()
                            }
                    }

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
                                metronome.mode = .letter
                                if metronome.isTicking {
                                    metronome.stop()
                                    metronome.start()
                                }
                            } label: {
                                HStack {
                                    if metronome.mode == .letter {
                                        Image(systemName: "checkmark")
                                    }
                                    Text("Letter (C-D-E)")
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
                                case .letter:
                                    Image(systemName: "character.textbox")
                                case .solfege:
                                    Image(systemName: "music.note")
                                }
                            }
                        }
                        .help("Metronome Mode")

                        if metronome.mode == .counting {
                            Menu {
                                Button {
                                    metronome.subdivisions = 1
                                    if metronome.isTicking {
                                        metronome.stop()
                                        metronome.start()
                                    }
                                } label: {
                                    HStack {
                                        if metronome.subdivisions == 1 {
                                            Image(systemName: "checkmark")
                                        }
                                        Text("Quarter Notes")
                                    }
                                }
                                Button {
                                    metronome.subdivisions = 2
                                    if metronome.isTicking {
                                        metronome.stop()
                                        metronome.start()
                                    }
                                } label: {
                                    HStack {
                                        if metronome.subdivisions == 2 {
                                            Image(systemName: "checkmark")
                                        }
                                        Text("Eighth Notes (+ and)")
                                    }
                                }
                                Button {
                                    metronome.subdivisions = 4
                                    if metronome.isTicking {
                                        metronome.stop()
                                        metronome.start()
                                    }
                                } label: {
                                    HStack {
                                        if metronome.subdivisions == 4 {
                                            Image(systemName: "checkmark")
                                        }
                                        Text("Sixteenth Notes (+ e and a)")
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "divide.circle")
                                    switch metronome.subdivisions {
                                    case 1:
                                        Text("♩")
                                    case 2:
                                        Text("♫")
                                    case 4:
                                        Text("♬")
                                    default:
                                        Text("♩")
                                    }
                                }
                            }
                            .help("Subdivision Level")
                        }
                    }

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

                    // Play/Pause button (right-most)
                    Button(action: {
                        togglePlayback()
                    }) {
                        let isAnyPlaying = midiPlayer.isPlaying || isVisualPlaying
                        Image(systemName: isAnyPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    .help(getPlayButtonHelp())
                }
            }
        }
        #endif
        #if os(iOS)
        .sheet(isPresented: $showTempoPopover) {
            // On iOS, use a sheet instead of popover for tempo adjustment
            NavigationView {
                TempoSliderView(
                    baseBPM: verovioService.getTempoBPM() ?? 120.0,
                    playbackRate: $midiPlayer.playbackRate,
                    onRateChange: { rate in
                        setPlaybackRate(rate)
                    }
                )
                .padding()
                .navigationTitle("Adjust Tempo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showTempoPopover = false
                        }
                    }
                }
            }
        }
        #endif
    }

    // MARK: - Playback Control Methods

    /// Toggle playback based on current mode (MIDI or metronome-only)
    private func togglePlayback() {
        // Defensive: if user selected no staves for "Play for me", force visual-only playback
        // and ensure any loaded MIDI is unloaded. This prevents stray MIDI audio.
        if selectedStavesForPlayback.isEmpty {
            print("togglePlayback: no staves selected -> applying selection policy")
            // Ensure MIDI is unloaded
            midiPlayer.unload()

            if metronome.isEnabled {
                // If metronome is enabled, start/stop it as the audio source.
                let wasTickingBefore = metronome.isTicking
                // Sync bpm
                let bpm = verovioService.getTempoBPM() ?? 120.0
                metronome.bpm = bpm
                if !wasTickingBefore {
                    // If nothing was playing, start metronome
                    metronome.start()
                } else {
                    // If it was ticking, toggle it off
                    metronome.stop()
                }
            } else {
                // Visual-only playback when metronome disabled
                if isVisualPlaying {
                    stopVisualPlayback()
                } else {
                    startVisualPlayback()
                }
            }

            return
        }

        // Determine if there is audio to play: either MIDIPlayer has data and a selected-staves
        // MIDI was loaded, or metronome is enabled. If not, we should still advance visuals
        // (silent playback) so users can follow along without sound.

        let hasAudioOutput: Bool = {
            // If metronome is enabled it will produce sound.
            if metronome.isEnabled { return true }

            // If the MIDIPlayer has data and Verovio has MIDI, consider audio available.
            if midiPlayer.duration > 0 && verovioService.getMIDI().count > 0 { return true }
            return false
        }()

        if hasAudioOutput {
            // Determine whether the user is starting or stopping playback.
            // We treat the call as a toggle: if nothing was playing before, this is a start.
            let wasPlayingBefore = midiPlayer.isPlaying || isVisualPlaying || metronome.isTicking

            // Normal audio playback via MIDIPlayer
            midiPlayer.togglePlayPause()

            // Notify metronome of MIDI playback state change so it can re-sync if needed
            metronome.onMIDIPlaybackStateChanged()

            // If metronome is enabled, start it when the user started playback, stop it when they paused.
            if metronome.isEnabled {
                let bpm = verovioService.getTempoBPM() ?? 120.0
                metronome.bpm = bpm
                if !wasPlayingBefore {
                    // User pressed Play -> ensure metronome is running
                    metronome.start()
                } else {
                    // User pressed Pause -> stop metronome
                    metronome.stop()
                }
            } else {
                // Metronome disabled -> ensure it's stopped
                metronome.stop()
            }
        } else {
            // No audio output available -> perform visual-only playback by driving the
            // midiPlayer.currentTime forward with a timer. This keeps the WebView highlighting
            // in sync without producing sound.
            if isVisualPlaying {
                stopVisualPlayback()
            } else {
                startVisualPlayback()
            }
        }
    }

    /// Get appropriate help text for the play button based on current mode and state
    private func getPlayButtonHelp() -> String {
        let isAnyPlaying = midiPlayer.isPlaying || isVisualPlaying
        return isAnyPlaying ? "Pause Playback" : "Play"
    }

    private func startVisualPlayback() {
        // Keep a reference so we can stop it. Advance at 100ms intervals to match the
        // MIDIPlayer timer granularity.
        DispatchQueue.main.async {
            self.isVisualPlaying = true
        }
        visualPlaybackTimer?.invalidate()
        visualPlaybackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // Always perform UI-model mutations on the main queue
            DispatchQueue.main.async {
                // Advance currentTime by the timer interval adjusted by playbackRate
                let delta = 0.1 * TimeInterval(self.midiPlayer.playbackRate)
                self.midiPlayer.currentTime += delta
                // Cap at duration if known, otherwise if metronome has a totalDuration use that
                if (self.midiPlayer.duration > 0 && self.midiPlayer.currentTime >= self.midiPlayer.duration) ||
                   (self.midiPlayer.duration == 0 && self.metronome.totalDuration > 0 && self.midiPlayer.currentTime >= self.metronome.totalDuration) {
                    // Reset playback state and ensure UI sees the stopped state immediately
                    self.midiPlayer.currentTime = 0
                    // Ensure MIDI player's published playing state is false
                    self.midiPlayer.isPlaying = false
                    self.stopVisualPlayback()
                    if self.metronome.isTicking {
                        self.metronome.stop()
                    }
                }
            }
        }
    }

    private func stopVisualPlayback() {
        DispatchQueue.main.async {
            self.isVisualPlaying = false
            self.visualPlaybackTimer?.invalidate()
            self.visualPlaybackTimer = nil
            // Ensure the WebView and UI see the paused time; don't reset unless at end
        }
    }

    private func setPlaybackRate(_ rate: Float) {
        midiPlayer.playbackRate = rate
        metronome.playbackRate = rate
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

    /// Update the MIDI data loaded into the MIDI player based on the user's
    /// selected staves for the "Play for me" feature. This will replace the
    /// audio source (midiPlayer.loadMIDI) and update note events used by the metronome.
    private func updateMIDISelection() {
        // If no score loaded, nothing to do
        guard verovioService.lastLoadedData != nil else { return }

        // If user selected staves, try to get MIDI for those staves and load into the player.
        if !selectedStavesForPlayback.isEmpty {
            if let selectedMidiString = verovioService.getMIDIForStaves(selectedStavesForPlayback), let selectedMidiData = Data(base64Encoded: selectedMidiString) {
                let wasPlaying = midiPlayer.isPlaying
                // Preserve current playback position so we can resume at the same spot after reload
                let savedPosition = midiPlayer.currentTime
                // Stop metronome briefly so it can be restarted cleanly after note events update
                let wasMetronomeTicking = metronome.isTicking
                if wasMetronomeTicking {
                    metronome.stop()
                }
                do {
                    try midiPlayer.loadMIDI(data: selectedMidiData)
                    midiPlayer.loadNoteEventsFromFilteredMIDI(data: selectedMidiData)
                    metronome.setNoteEvents(midiPlayer.noteEvents)
                    // Ensure metronome honors current playback rate
                    metronome.playbackRate = midiPlayer.playbackRate
                    print("ContentView.updateMIDISelection: loaded selected staves MIDI (\(selectedStavesForPlayback.count) staves)")
                    if wasPlaying {
                        // Small delay to avoid races between MIDI player stop/start and metronome timers
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                            midiPlayer.play(fromPosition: savedPosition)
                            // Seek metronome to the same logical position so it stays in sync
                            metronome.seek(to: savedPosition)

                            // Restart metronome if it was running before
                            if wasMetronomeTicking && metronome.isEnabled {
                                metronome.start()
                            } else {
                                metronome.onMIDIPlaybackStateChanged()
                            }
                        }
                    } else {
                        // Not playing: just ensure timer/resync
                        metronome.onMIDIPlaybackStateChanged()
                        if wasMetronomeTicking && metronome.isEnabled {
                            metronome.start()
                        }
                    }
                } catch {
                    print("Warning: Failed to load selected-staves MIDI: \(error.localizedDescription)")
                    // If we stopped metronome earlier, restart it to preserve user intent
                    if wasMetronomeTicking && metronome.isEnabled {
                        metronome.start()
                    }
                }
            } else {
                print("ContentView.updateMIDISelection: Verovio failed to produce MIDI for selected staves: \(selectedStavesForPlayback)")
            }
        } else {
            // No selection: user explicitly chose no staves -> disable audio playback.
            // Unload the MIDI data so the player cannot produce sound.
            midiPlayer.unload()

            // Load filtered note events for metronome (first staff) so metronome features still work
            if let filteredMidiString = verovioService.getMIDIForFirstStaff(), let filteredMidiData = Data(base64Encoded: filteredMidiString) {
                midiPlayer.loadNoteEventsFromFilteredMIDI(data: filteredMidiData)
                metronome.setNoteEvents(midiPlayer.noteEvents)
            }

            // Ensure metronome honors current playback rate and switches into metronome-only timing
            let wasMetronomeTicking = metronome.isTicking
            if wasMetronomeTicking {
                metronome.stop()
            }
            metronome.playbackRate = midiPlayer.playbackRate
            metronome.onMIDIPlaybackStateChanged()
            if wasMetronomeTicking && metronome.isEnabled {
                metronome.start()
            }

            print("ContentView.updateMIDISelection: no staves selected — audio unloaded and disabled")
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

            // Delegate MIDI loading to updateMIDISelection so the user's "Play for me"
            // selection is respected (including the case of an empty selection -> no audio).
            let fullMidiString = verovioService.getMIDI()
            if fullMidiString.isEmpty {
                print("Warning: Verovio returned empty MIDI string")
            } else {
                // Set metronome BPM immediately
                let bpm = verovioService.getTempoBPM() ?? 120.0
                metronome.bpm = bpm

                // Apply user's MIDI selection preferences (this will load selected staves or unload audio)
                updateMIDISelection()
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

        // Reset staves selection for new file
        verovioService.enabledStaves.removeAll()

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

            // Prepare MIDI selection and note events but don't load full MIDI unconditionally.
            // This ensures audio follows the user's "Play for me" selection (including empty selection -> no audio).
            let _ = verovioService.getMIDI() // ensure MIDI was generated internally if needed

            // Initialize 'Play for me' selection: always enable all available staves for the loaded score.
            let allStaveKeys: Set<String> = Set(verovioService.availableStaves.map { (partId, staffNumber, _) in "\(partId)-\(staffNumber)" })
            selectedStavesForPlayback = allStaveKeys

            // Set metronome BPM from VerovioService if available
            let bpm = verovioService.getTempoBPM() ?? 120.0
            metronome.bpm = bpm

            // Delegate actual MIDI loading to updateMIDISelection which respects the selection policy
            updateMIDISelection()

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
                Text("25%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 35)

                Slider(value: $localRate, in: 0.25...1.25, step: 0.05) { editing in
                    if !editing {
                        let newRate = Float(localRate)
                        playbackRate = newRate
                        onRateChange(newRate)
                    }
                }
                .onChange(of: localRate) { oldValue, newValue in
                    // Update in real-time while dragging
                    let newRate = Float(newValue)
                    playbackRate = newRate
                    onRateChange(newRate)
                }

                Text("125%")
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
