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
                    currentTimeOverride: metronome.isEnabled ? metronome.currentTime : nil,
                    isPlayingOverride: metronome.isEnabled ? metronome.isTicking : (isVisualPlaying ? true : nil)
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
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if svgPages != nil {
                    // Play/Pause button
                    Button(action: {
                        togglePlayback()
                    }) {
                        let isAnyPlaying = midiPlayer.isPlaying || isVisualPlaying
                        Image(systemName: isAnyPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    .help(getPlayButtonHelp())

                    Divider()

                    // Metronome toggle (always available)
                    Toggle(isOn: $metronome.isEnabled) {
                        Image(systemName: "metronome")
                    }
                    .toggleStyle(.button)
                    .help(metronome.isEnabled ? "Disable Metronome" : "Enable Metronome")
                    .onChange(of: metronome.isEnabled) { oldValue, newValue in
                        if newValue && midiPlayer.isPlaying {
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

                        // Subdivision selector (only show for counting mode) - iOS
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

                    Divider()

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
                            Image(systemName: "music.note.list")
                        }
                        .help("Select Parts")

                        Divider()
                    }

                    Button("Load MusicXML file") {
                        isImporting = true
                    }
                }
            }
        }
        #else
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if svgPages != nil {
                    // Play/Pause button
                    Button(action: {
                        togglePlayback()
                    }) {
                        let isAnyPlaying = midiPlayer.isPlaying || isVisualPlaying
                        Image(systemName: isAnyPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    .help(getPlayButtonHelp())

                    Divider()

                    // Metronome toggle (always available)
                    Toggle(isOn: $metronome.isEnabled) {
                        Image(systemName: "metronome")
                    }
                    .toggleStyle(.button)
                    .help(metronome.isEnabled ? "Disable Metronome" : "Enable Metronome")
                    .onChange(of: metronome.isEnabled) { oldValue, newValue in
                        if newValue && midiPlayer.isPlaying {
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

                        // Subdivision selector (only show for counting mode) - macOS
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
                            Image(systemName: "music.note.list")
                        }
                        .help("Select Parts")

                        Divider()
                    }

                    Button("Load MusicXML file") {
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
        // Determine if there is audio to play: either MIDIPlayer has data and a selected-staves
        // MIDI was loaded, or metronome is enabled. If not, we should still advance visuals
        // (silent playback) so users can follow along without sound.

        let hasAudioOutput: Bool = {
            // If metronome is enabled it will produce sound.
            if metronome.isEnabled { return true }

            // If the MIDIPlayer has data and either selected staves are non-empty (we loaded
            // selected-staves MIDI) or the main MIDI was loaded, consider audio available.
            if midiPlayer.duration > 0 && verovioService.getMIDI().count > 0 { return true }
            return false
        }()

        if hasAudioOutput {
            // Normal audio playback via MIDIPlayer
            midiPlayer.togglePlayPause()

            // Notify metronome of MIDI playback state change
            metronome.onMIDIPlaybackStateChanged()

            // Sync metronome with MIDI playback
            if midiPlayer.isPlaying && metronome.isEnabled {
                let bpm = verovioService.getTempoBPM() ?? 120.0
                metronome.bpm = bpm
                metronome.start()
            } else {
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
        isVisualPlaying = true
        visualPlaybackTimer?.invalidate()
        visualPlaybackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // Advance currentTime by the timer interval adjusted by playbackRate
            let delta = 0.1 * TimeInterval(midiPlayer.playbackRate)
            midiPlayer.currentTime += delta
            // Cap at duration if known
            if midiPlayer.duration > 0 && midiPlayer.currentTime >= midiPlayer.duration {
                midiPlayer.currentTime = 0
                stopVisualPlayback()
            }
        }
    }

    private func stopVisualPlayback() {
        isVisualPlaying = false
        visualPlaybackTimer?.invalidate()
        visualPlaybackTimer = nil
        // Ensure the WebView and UI see the paused time; don't reset unless at end
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
                do {
                    try midiPlayer.loadMIDI(data: selectedMidiData)
                    midiPlayer.loadNoteEventsFromFilteredMIDI(data: selectedMidiData)
                    metronome.setNoteEvents(midiPlayer.noteEvents)
                    print("ContentView.updateMIDISelection: loaded selected staves MIDI (\(selectedStavesForPlayback.count) staves)")
                    if wasPlaying { midiPlayer.play() }
                } catch {
                    print("Warning: Failed to load selected-staves MIDI: \(error.localizedDescription)")
                }
            } else {
                print("ContentView.updateMIDISelection: Verovio failed to produce MIDI for selected staves: \(selectedStavesForPlayback)")
            }
        } else {
            // No selection: reload full MIDI into player and restore prior note-event filtering (first staff)
            let fullMidiString = verovioService.getMIDI()
            if !fullMidiString.isEmpty, let fullMidiData = Data(base64Encoded: fullMidiString) {
                let wasPlaying = midiPlayer.isPlaying
                do {
                    try midiPlayer.loadMIDI(data: fullMidiData)
                    if let filteredMidiString = verovioService.getMIDIForFirstStaff(), let filteredMidiData = Data(base64Encoded: filteredMidiString) {
                        midiPlayer.loadNoteEventsFromFilteredMIDI(data: filteredMidiData)
                        metronome.setNoteEvents(midiPlayer.noteEvents)
                    }
                    print("ContentView.updateMIDISelection: loaded full MIDI")
                    if wasPlaying { midiPlayer.play() }
                } catch {
                    print("Warning: Failed to reload full MIDI: \(error.localizedDescription)")
                }
            } else {
                print("ContentView.updateMIDISelection: no full MIDI available")
            }
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

            // Load either full MIDI or filtered MIDI depending on user selection
            let fullMidiString = verovioService.getMIDI()
            if fullMidiString.isEmpty {
                print("Warning: Verovio returned empty MIDI string")
            } else if let fullMidiData = Data(base64Encoded: fullMidiString) {
                do {
                    // If user selected staves for playback, prefer that MIDI as the audio source
                    if !selectedStavesForPlayback.isEmpty, let selectedMidiString = verovioService.getMIDIForStaves(selectedStavesForPlayback), let selectedMidiData = Data(base64Encoded: selectedMidiString) {
                        try midiPlayer.loadMIDI(data: selectedMidiData)
                    } else {
                        try midiPlayer.loadMIDI(data: fullMidiData)
                    }

                    let bpm = verovioService.getTempoBPM() ?? 120.0
                    metronome.bpm = bpm

                    // Load filtered note events for solfege mode (first staff only) or use selected staves note events
                    if !selectedStavesForPlayback.isEmpty, let selectedMidiString = verovioService.getMIDIForStaves(selectedStavesForPlayback), let selectedMidiData = Data(base64Encoded: selectedMidiString) {
                        midiPlayer.loadNoteEventsFromFilteredMIDI(data: selectedMidiData)
                        metronome.setNoteEvents(midiPlayer.noteEvents)
                    } else if let filteredMidiString = verovioService.getMIDIForFirstStaff() {
                        if let filteredMidiData = Data(base64Encoded: filteredMidiString) {
                            midiPlayer.loadNoteEventsFromFilteredMIDI(data: filteredMidiData)
                            metronome.setNoteEvents(midiPlayer.noteEvents)
                        }
                    }
                } catch {
                    print("Warning: Failed to load MIDI data: \(error.localizedDescription)")
                    // Continue without MIDI playback
                }
            } else {
                print("Warning: Failed to decode base64 MIDI string (length: \(fullMidiString.count))")
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

            // Get MIDI data and load into player
            let midiString = verovioService.getMIDI()
            if midiString.isEmpty {
                print("Warning: Verovio returned empty MIDI string")
            } else if let midiData = Data(base64Encoded: midiString) {
                do {
                    try midiPlayer.loadMIDI(data: midiData)
                    // Set metronome BPM from VerovioService if available
                    let bpm = verovioService.getTempoBPM() ?? 120.0
                    metronome.bpm = bpm

                    // Load filtered note events for playback. If user selected staves for "Play for me",
                    // load note events from those staves; otherwise fall back to solfege-first-staff behavior.
                    if !selectedStavesForPlayback.isEmpty, let selectedMidiString = verovioService.getMIDIForStaves(selectedStavesForPlayback), let selectedMidiData = Data(base64Encoded: selectedMidiString) {
                        midiPlayer.loadNoteEventsFromFilteredMIDI(data: selectedMidiData)
                        metronome.setNoteEvents(midiPlayer.noteEvents)
                    } else if let filteredMidiString = verovioService.getMIDIForFirstStaff() {
                        if let filteredMidiData = Data(base64Encoded: filteredMidiString) {
                            midiPlayer.loadNoteEventsFromFilteredMIDI(data: filteredMidiData)
                            metronome.setNoteEvents(midiPlayer.noteEvents)
                        }
                    }
                } catch {
                    print("Warning: Failed to load MIDI data: \(error.localizedDescription)")
                    // Continue without MIDI playback
                }
            } else {
                print("Warning: Failed to decode base64 MIDI string (length: \(midiString.count))")
            }

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
