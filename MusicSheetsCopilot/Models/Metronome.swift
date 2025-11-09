import Foundation
import AVFoundation

enum MetronomeMode {
    case tick        // Traditional tick sound
    case counting    // One Two Three Four based on beats
    case letter      // C D E F G A B letters based on actual notes
    case solfege     // Do Re Mi based on actual notes
}

class Metronome: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var isTicking: Bool = false
    @Published var bpm: Double = 120.0 {
        didSet { updateTimer() }
    }
    @Published var playbackRate: Float = 1.0 {
        didSet { updateTimer() }
    }
    @Published var timeSignature: (Int, Int) = (4, 4)
    @Published var mode: MetronomeMode = .tick
    @Published var currentBeat: Int = 0  // Expose current beat position (0-indexed)
    @Published var currentTime: TimeInterval = 0  // Current playback time in metronome-only mode
    @Published var subdivisions: Int = 1 {  // 1=quarter notes, 2=eighth notes, 4=sixteenth notes
        didSet { updateTimer() }
    }

    private var audioPlayer: AVAudioPlayer?
    private var timer: TimerProtocol?  // Changed from Timer? to TimerProtocol?
    private var tickCount: Int = 0
    private var subdivisionCount: Int = 0  // Track position within a beat (0 to subdivisions-1)
    private var lastSpokenSubdivisionIndex: Int = -1 // For MIDI counting mode
    private var speechSynthesizer = AVSpeechSynthesizer()

    // For MIDI sync: track when we started and what the MIDI time was at start
    private var midiSyncStartTime: Date?
    private var midiSyncStartPosition: TimeInterval = 0

    // Dependency injection for time provider (defaults to system time)
    private let timeProvider: TimeProvider

    // Reference to MIDIPlayer for getting current notes (when MIDI is playing)
    weak var midiPlayer: MIDIPlayer?
    private var lastSpokenTime: TimeInterval = -1
    private var lastSpokenNotes: Set<UInt8> = []

    // For metronome-only mode: track playback position and note events
    private var metronomeStartTime: Date?
    private var metronomePausedTime: TimeInterval = 0
    private var noteEvents: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = []
    var firstStaffChannel: UInt8 = 0  // Cache the first staff's channel (internal for testing)
    var totalDuration: TimeInterval = 0  // Total duration based on last note event (internal for testing)
    private var lastBeatTime: TimeInterval = 0  // Track when we last advanced the beat (for solfege mode)

    // Initializer with dependency injection (defaults to system time provider)
    init(timeProvider: TimeProvider = SystemTimeProvider()) {
        self.timeProvider = timeProvider
    }

    /// Map MIDI note number to letter name (naturalized - sharps/flats map to nearest natural)
    /// e.g. C, D, E, F, G, A, B
    func midiNoteToLetter(_ midiNote: UInt8) -> String {
        let noteInOctave = Int(midiNote) % 12
        let letterMap = [
            "c",  // C
            "c",  // C# -> C
            "d",  // D
            "d",  // D# -> D
            "e",  // E
            "f",  // F
            "f",  // F# -> F
            "g",  // G
            "g",  // G# -> G
            "a",  // A
            "a",  // A# -> A
            "b"   // B
        ]
        return letterMap[noteInOctave]
    }

    // Map MIDI note number to solfege syllable
    // MIDI notes: C=0, C#=1, D=2, D#=3, E=4, F=5, F#=6, G=7, G#=8, A=9, A#=10, B=11
    func midiNoteToSolfege(_ midiNote: UInt8) -> String {
        let noteInOctave = Int(midiNote) % 12
        let solfegeMap = [
            "Doh",  // C
            "Doh",  // C# (same as C)
            "Reh",  // D
            "Reh",  // D# (same as D)
            "Mee",  // E
            "Fa",  // F
            "Fa",  // F# (same as F)
            "Sol", // G
            "Sol", // G# (same as G)
            "La",  // A
            "La",  // A# (same as A)
            "Si"   // B
        ]
        return solfegeMap[noteInOctave]
    }

    /// Set note events for metronome-only mode (when MIDI is not playing)
    /// This allows the metronome to speak notes based on timing data
    func setNoteEvents(_ events: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)]) {
        self.noteEvents = events
        // Cache the first staff's channel (lowest channel number)
        self.firstStaffChannel = events.map { $0.channel }.min() ?? 0
        // Calculate total duration from the last note event (add a 2.0 second buffer for the last note to ring)
        self.totalDuration = (events.map { $0.time }.max() ?? 0) + 2.0
    }

    /// Get current playback time in metronome-only mode
    private func getCurrentMetronomeTime() -> TimeInterval {
        guard let startTime = metronomeStartTime else { return 0 }
        let elapsed = timeProvider.now().timeIntervalSince(startTime)
        // Adjust for playback rate
        let time = metronomePausedTime + (elapsed * Double(playbackRate))

        // Update the published currentTime
        DispatchQueue.main.async { [weak self] in
            self?.currentTime = time
        }

        return time
    }

    // Provide a short tick sound (440Hz sine wave, 0.05s)
    private static func tickSoundData() -> Data {
        let sampleRate = 44100.0
        let duration = 0.05
        let freq = 440.0
        let samples = Int(sampleRate * duration)
        var buffer = [Int16](repeating: 0, count: samples)
        for i in 0..<samples {
            let t = Double(i) / sampleRate
            let value = sin(2 * .pi * freq * t)
            buffer[i] = Int16(value * 32767.0)
        }
        let wavHeader = Metronome.wavHeader(sampleCount: samples, sampleRate: Int(sampleRate))
        var data = Data(wavHeader)
        // Use withUnsafeBufferPointer to avoid dangling pointer
        buffer.withUnsafeBufferPointer { bufferPointer in
            data.append(Data(buffer: bufferPointer))
        }
        return data
    }

    private static func wavHeader(sampleCount: Int, sampleRate: Int) -> [UInt8] {
        let byteRate = sampleRate * 2
        let blockAlign = 2
        let dataSize = sampleCount * 2
        let chunkSize = 36 + dataSize
        return [
            0x52, 0x49, 0x46, 0x46, // "RIFF"
            UInt8(chunkSize & 0xff), UInt8((chunkSize >> 8) & 0xff), UInt8((chunkSize >> 16) & 0xff), UInt8((chunkSize >> 24) & 0xff),
            0x57, 0x41, 0x56, 0x45, // "WAVE"
            0x66, 0x6d, 0x74, 0x20, // "fmt "
            16, 0, 0, 0, // Subchunk1Size
            1, 0, // AudioFormat (PCM)
            1, 0, // NumChannels
            UInt8(sampleRate & 0xff), UInt8((sampleRate >> 8) & 0xff), UInt8((sampleRate >> 16) & 0xff), UInt8((sampleRate >> 24) & 0xff),
            UInt8(byteRate & 0xff), UInt8((byteRate >> 8) & 0xff), UInt8((byteRate >> 16) & 0xff), UInt8((byteRate >> 24) & 0xff),
            UInt8(blockAlign), 0, // BlockAlign
            16, 0, // BitsPerSample
            0x64, 0x61, 0x74, 0x61, // "data"
            UInt8(dataSize & 0xff), UInt8((dataSize >> 8) & 0xff), UInt8((dataSize >> 16) & 0xff), UInt8((dataSize >> 24) & 0xff)
        ]
    }

    func start() {
        guard isEnabled else { return }

        // If already ticking, just re-sync (don't restart)
        if isTicking {
            // Check if we need to sync with MIDI that just started
            if let player = midiPlayer, player.isPlaying, midiSyncStartTime == nil {
                midiSyncStartTime = timeProvider.now()
                midiSyncStartPosition = player.currentTime

                // Update beat position to match MIDI
                let beatDuration = 60.0 / bpm
                let currentBeat = Int(player.currentTime / beatDuration) % timeSignature.0
                self.currentBeat = currentBeat
                self.tickCount = currentBeat

                // Update timer to switch to MIDI sync mode
                updateTimer()
            }
            return
        }

        // Configure audio session for iOS
        #if os(iOS)
        configureAudioSession()
        #endif

        isTicking = true
        lastSpokenTime = -1
        lastSpokenNotes = []
        lastBeatTime = 0  // Reset beat timing
        subdivisionCount = 0  // Reset subdivision tracking

        // Calculate initial beat position based on current playback time
        let initialTime: TimeInterval
        if midiPlayer?.isPlaying == true {
            // MIDI is playing: sync to MIDI's current position
            initialTime = midiPlayer!.currentTime
            // Track when we started syncing with MIDI
            midiSyncStartTime = timeProvider.now()
            midiSyncStartPosition = initialTime
        } else {
            // Metronome-only mode: start from beginning
            initialTime = 0
            metronomeStartTime = timeProvider.now()
            metronomePausedTime = 0
            midiSyncStartTime = nil
        }

        // Calculate which beat we should be on based on the initial time
        let beatDuration = 60.0 / bpm
        let initialBeat = Int(initialTime / beatDuration) % timeSignature.0
        tickCount = initialBeat
        currentBeat = initialBeat

        // When MIDI is playing, check if we're starting exactly on a beat boundary
        // If so, play an immediate tick; otherwise wait for the next beat
        let shouldPlayImmediate: Bool
        let initialSubdivision: Int
        if midiPlayer?.isPlaying == true {
            // Check if we're very close to a beat/subdivision boundary (within 50ms tolerance)
            let subdivisionDuration = beatDuration / Double(subdivisions)
            let timeIntoSubdivision = initialTime.truncatingRemainder(dividingBy: subdivisionDuration)
            shouldPlayImmediate = timeIntoSubdivision < 0.05  // Within 50ms of subdivision start

            // Calculate which subdivision within the beat we're on
            let timeIntoBeat = initialTime.truncatingRemainder(dividingBy: beatDuration)
            initialSubdivision = Int(timeIntoBeat / subdivisionDuration) % subdivisions
            subdivisionCount = initialSubdivision
        } else {
            // Metronome-only mode: always play immediate tick
            shouldPlayImmediate = true
            initialSubdivision = 0
            subdivisionCount = 0
        }

        if shouldPlayImmediate {
            // Play immediate tick/count since we're on or near a beat boundary
            if mode == .tick {
                playTickSound()
                // currentBeat stays at initialBeat (represents the beat being played)
                tickCount += 1
                if tickCount >= timeSignature.0 {
                    tickCount = 0
                }
            } else if mode == .counting {
                print("🎬 START COUNTING: initialBeat=\(initialBeat), initialSubdivision=\(initialSubdivision), bpm=\(bpm)")
                speakCount(beat: initialBeat, subdivisionIndex: initialSubdivision)

                // Advance subdivision
                subdivisionCount += 1
                if subdivisionCount >= subdivisions {
                    subdivisionCount = 0
                    tickCount += 1
                    currentBeat = tickCount
                    if tickCount >= timeSignature.0 {
                        tickCount = 0
                        currentBeat = 0
                    }
                }
            } else if mode == .letter || mode == .solfege {
                if !noteEvents.isEmpty {
                    speakNotesAtMetronomeTime()
                }
            }
        }

        // Publish initial currentTime immediately so UI/WebView sees the starting position
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentTime = initialTime
        }

        updateTimer()
    }

    func stop() {
        isTicking = false
        currentBeat = 0  // Reset visual beat indicator
        currentTime = 0  // Reset playback time
        timer?.invalidate()
        timer = nil
        lastSpokenTime = -1
        lastSpokenNotes = []
        subdivisionCount = 0  // Reset subdivision tracking
        metronomeStartTime = nil
        metronomePausedTime = 0
        midiSyncStartTime = nil
        midiSyncStartPosition = 0
        // Stop speech synthesis on main queue to avoid priority inversion
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.speechSynthesizer.isSpeaking {
                self.speechSynthesizer.stopSpeaking(at: .immediate)
            }
        }
    }

    /// Call this when MIDI playback state changes (starts or stops)
    /// This allows the metronome to re-sync with MIDI timing
    func onMIDIPlaybackStateChanged() {
        guard isTicking else { return }
        updateTimer()
    }

    /// Seek metronome to a specific time (in seconds).
    /// This updates internal timing so metronome currentTime and beat state reflect the requested position.
    func seek(to time: TimeInterval) {
        // If MIDI is playing, prefer syncing to MIDI player's position via midiSyncStartTime
        if let player = midiPlayer, player.isPlaying {
            // Set sync start so updateTimer will compute correctly
            midiSyncStartTime = timeProvider.now()
            midiSyncStartPosition = time

            // Update current beat based on BPM
            let beatDuration = 60.0 / bpm
            let beatIndex = Int(time / beatDuration) % timeSignature.0
            currentBeat = beatIndex
            tickCount = beatIndex
        } else {
            // Metronome-only mode: set the paused time so getCurrentMetronomeTime returns `time`
            metronomeStartTime = timeProvider.now()
            metronomePausedTime = time

            // Update beat indices
            let beatDuration = 60.0 / bpm
            let beatIndex = Int(time / beatDuration) % timeSignature.0
            currentBeat = beatIndex
            tickCount = beatIndex
        }

        // Publish currentTime immediately
        DispatchQueue.main.async { [weak self] in
            self?.currentTime = time
        }
    }

    private func updateTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timer?.invalidate()
            guard self.isEnabled && self.isTicking else { return }

            // Check if we need to sync with MIDI that just started playing
            if let player = self.midiPlayer, player.isPlaying, self.midiSyncStartTime == nil {
                // MIDI is now playing but we weren't tracking it - start tracking
                self.midiSyncStartTime = self.timeProvider.now()
                self.midiSyncStartPosition = player.currentTime

                // Update beat position to match MIDI
                let beatDuration = 60.0 / self.bpm
                let currentBeat = Int(player.currentTime / beatDuration) % self.timeSignature.0
                self.currentBeat = currentBeat
                self.tickCount = currentBeat
            } else if self.midiPlayer?.isPlaying != true && self.midiSyncStartTime != nil {
                // MIDI stopped - switch back to metronome-only mode
                self.midiSyncStartTime = nil
                self.midiSyncStartPosition = 0
                self.metronomeStartTime = self.timeProvider.now()
                self.metronomePausedTime = 0
            }

            // Adjust BPM by playback rate
            let adjustedBPM = self.bpm * Double(self.playbackRate)

            // Compute beat and subdivision durations
            let subdivisionInterval = 60.0 / (adjustedBPM * Double(max(1, self.subdivisions)))

            // Prefer using the musical subdivision interval for metronome ticks when
            // running in metronome-only modes. Reserve the high-frequency short
            // interval (maxInterval) only for MIDI sync or solfege mode where we need
            // very frequent checks for UI highlighting or precise note boundaries.
            let maxInterval: TimeInterval = 0.05

            let interval: TimeInterval
            if self.midiPlayer?.isPlaying == true {
                // When MIDI is playing, poll at high frequency (capped to maxInterval)
                interval = min(maxInterval, subdivisionInterval)
            } else if self.mode == .solfege {
                // Solfege needs frequent checks to catch note events
                interval = min(maxInterval, subdivisionInterval)
            } else if self.mode == .counting && self.subdivisions > 1 {
                // Counting with subdivisions: tick exactly at subdivision intervals
                interval = subdivisionInterval
            } else {
                // Metronome-only simple tick/counting: use the beat/subdivision interval
                // (no extra high-frequency polling) so audio ticks occur at musical tempo.
                interval = subdivisionInterval
            }

            self.timer = self.timeProvider.scheduleTimer(interval: interval, repeats: true) { [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        // Update metronome currentTime on every tick when MIDI is not playing so
        // the published `currentTime` updates frequently and UI (WebView) can
        // reflect playback position smoothly.
        if midiPlayer?.isPlaying != true {
            _ = getCurrentMetronomeTime()
        }

        // Check if we've reached the end of the piece
        if let player = midiPlayer, player.isPlaying {
            // When MIDI is playing, only auto-stop if the player's duration is known (> 0)
            // and we're within a small epsilon of the end. This avoids treating a zero
            // duration (the default in tests/mocks) as 'already finished'.
            let epsilon: TimeInterval = 0.1
            if player.duration > 0 && player.currentTime >= player.duration - epsilon {
                stop()
                return
            }
            // Do NOT auto-stop in metronome-only mode if MIDI is playing
        } else if (midiPlayer == nil || midiPlayer?.isPlaying == false) && totalDuration > 0 {
            // Metronome-only mode: check against total duration ONLY if MIDI is not playing
            let currentMetronomeTime = getCurrentMetronomeTime()
            if currentMetronomeTime >= totalDuration {
                // Reached the end - stop playback
                stop()
                return
            }
        }

        switch mode {
        case .tick:
            // When MIDI is playing, check if we're actually on a beat boundary
            if let player = midiPlayer, player.isPlaying,
               midiSyncStartTime != nil {
                let currentMIDITime = player.currentTime
                let beatDuration = 60.0 / bpm
                let currentBeatIndex = Int(currentMIDITime / beatDuration) % timeSignature.0

                // Only tick if we've actually moved to a new beat
                if currentBeatIndex != currentBeat {
                    currentBeat = currentBeatIndex
                    tickCount = currentBeatIndex
                    playTickSound()
                    tickCount += 1
                    if tickCount >= timeSignature.0 {
                        tickCount = 0
                    }
                }
            } else {
                // Metronome-only mode: tick on every timer fire
                playTickSound()
                currentBeat = tickCount
                tickCount += 1
                if tickCount >= timeSignature.0 {
                    tickCount = 0
                }
            }
        case .letter, .solfege:
            // In solfege mode, update beat based on time, not on every timer tick
            // Get the current playback time
            let currentTime: TimeInterval
            if midiPlayer?.isPlaying == true {
                currentTime = midiPlayer!.currentTime
            } else {
                currentTime = getCurrentMetronomeTime()
            }

            // Calculate beat duration based on ORIGINAL BPM (not adjusted)
            // Note: The MIDI timestamps are based on the original BPM from the score
            // getCurrentMetronomeTime() already accounts for playbackRate in the elapsed time
            // So we should use the original BPM to calculate beat positions
            let beatDuration = 60.0 / bpm

            // Determine which beat we should be on based on elapsed time
            let currentBeatIndex = Int(currentTime / beatDuration) % timeSignature.0

            // Only update if the beat has actually changed
            if currentBeatIndex != currentBeat {
                currentBeat = currentBeatIndex
                tickCount = currentBeatIndex
            }

            // Speak notes at the current time
            if midiPlayer?.isPlaying == true {
                // MIDI is playing: speak notes from MIDI playback
                speakNotesAtCurrentTime()
            } else {
                // Metronome-only mode: speak notes based on timing data
                speakNotesAtMetronomeTime()
            }
        case .counting:
            // When MIDI is playing, check if we're actually on a beat or subdivision boundary
            if let player = midiPlayer, player.isPlaying,
               midiSyncStartTime != nil {
                let currentMIDITime = player.currentTime
                let beatDuration = 60.0 / bpm
                let subdivisionDuration = beatDuration / Double(subdivisions)

                // Calculate current subdivision index (across all beats)
                let totalSubdivisionIndex = Int(currentMIDITime / subdivisionDuration)
                let currentBeatIndex = totalSubdivisionIndex / subdivisions % timeSignature.0
                let currentSubdivisionIndex = totalSubdivisionIndex % subdivisions

                // Only speak if we've moved to a new subdivision
                if totalSubdivisionIndex != lastSpokenSubdivisionIndex {
                    lastSpokenSubdivisionIndex = totalSubdivisionIndex
                    currentBeat = currentBeatIndex
                    subdivisionCount = currentSubdivisionIndex
                    speakCount(beat: currentBeatIndex, subdivisionIndex: currentSubdivisionIndex)
                }
            } else {
                // Metronome-only mode: count on every timer fire
                currentBeat = tickCount
                speakCount(beat: tickCount, subdivisionIndex: subdivisionCount)

                // Advance subdivision
                subdivisionCount += 1
                if subdivisionCount >= subdivisions {
                    subdivisionCount = 0
                    tickCount += 1
                    if tickCount >= timeSignature.0 {
                        tickCount = 0
                    }
                }
            }
        }
    }

    private func playTickSound() {
        let data = Metronome.tickSoundData()
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
        }
    }

    private func speakNotesAtCurrentTime() {
        guard let player = midiPlayer else { return }

        let currentTime = player.currentTime

        let notes = player.getNotesAtTime(currentTime)

        guard !notes.isEmpty else {
            // If no notes are playing, clear the last spoken notes
            if !lastSpokenNotes.isEmpty {
                lastSpokenNotes = []
            }
            return
        }

        let currentNotesSet = Set(notes)

        // Only speak if we have NEW notes (different from what we last spoke)
        if currentNotesSet == lastSpokenNotes {
            return
        }

        // Also check time to avoid speaking too frequently even if notes changed
        if abs(currentTime - lastSpokenTime) < 0.15 {
            return
        }

        // Map notes to appropriate labels depending on mode
        let syllables: [String]
        if mode == .letter {
            syllables = notes.map { midiNoteToLetter($0) }
        } else {
            syllables = notes.map { midiNoteToSolfege($0) }
        }
        let uniqueSyllables = Array(Set(syllables)).sorted()

        // Speak the note names
        if !uniqueSyllables.isEmpty {
            lastSpokenTime = currentTime
            lastSpokenNotes = currentNotesSet
            let text = uniqueSyllables.joined(separator: " ")

            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = 0.55
            utterance.volume = 1.0
            utterance.pitchMultiplier = 1.0

            // Stop any ongoing speech
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
            }

            speechSynthesizer.speak(utterance)
        }
    }

    /// Speak notes at the current time in metronome-only mode
    /// Uses the noteEvents array and metronome timing to determine which notes to speak
    /// Note events are already filtered to first staff only
    private func speakNotesAtMetronomeTime() {
        guard !noteEvents.isEmpty else { return }

        let currentTime = getCurrentMetronomeTime()

        // Find notes that should be spoken at the current time (within a small tolerance)
        // Note events are already filtered to first staff via Verovio
        let tolerance: TimeInterval = 0.1
        let notesToSpeak = noteEvents.filter { event in
            abs(event.time - currentTime) < tolerance
        }

        guard !notesToSpeak.isEmpty else {
            // If no notes at current time, clear last spoken notes
            if !lastSpokenNotes.isEmpty {
                lastSpokenNotes = []
            }
            return
        }

        let currentNotesSet = Set(notesToSpeak.map { $0.midiNote })

        // Only speak if we have NEW notes (different from what we last spoke)
        if currentNotesSet == lastSpokenNotes {
            return
        }

        // Also check time to avoid speaking too frequently even if notes changed
        if abs(currentTime - lastSpokenTime) < 0.15 {
            return
        }

        // Map notes to appropriate labels depending on mode
        let syllables: [String]
        if mode == .letter {
            syllables = notesToSpeak.map { midiNoteToLetter($0.midiNote) }
        } else {
            syllables = notesToSpeak.map { midiNoteToSolfege($0.midiNote) }
        }
        let uniqueSyllables = Array(Set(syllables)).sorted()

        // Speak the note names
        if !uniqueSyllables.isEmpty {
            lastSpokenTime = currentTime
            lastSpokenNotes = currentNotesSet
            let text = uniqueSyllables.joined(separator: " ")

            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = 0.55
            utterance.volume = 1.0
            utterance.pitchMultiplier = 1.0

            // Stop any ongoing speech
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
            }

            speechSynthesizer.speak(utterance)
        }
    }

    private func speakCount(beat: Int, subdivisionIndex: Int = 0) {
        let text: String

        if subdivisions == 1 {
            // Quarter notes: traditional counting (1, 2, 3, 4...)
            let beatNumber = beat + 1
            let numberWords = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight",
                              "Nine", "Ten", "Eleven", "Twelve"]
            guard beatNumber <= numberWords.count else { return }
            text = numberWords[beatNumber - 1]
        } else if subdivisions == 2 {
            // Eighth notes: 1 and 2 and 3 and...
            if subdivisionIndex == 0 {
                let beatNumber = beat + 1
                let numberWords = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight",
                                  "Nine", "Ten", "Eleven", "Twelve"]
                guard beatNumber <= numberWords.count else { return }
                text = numberWords[beatNumber - 1]
            } else {
                text = "and"
            }
        } else if subdivisions == 4 {
            // Sixteenth notes: 1 e and a 2 e and a...
            if subdivisionIndex == 0 {
                let beatNumber = beat + 1
                let numberWords = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight",
                                  "Nine", "Ten", "Eleven", "Twelve"]
                guard beatNumber <= numberWords.count else { return }
                text = numberWords[beatNumber - 1]
            } else if subdivisionIndex == 1 {
                text = "e"
            } else if subdivisionIndex == 2 {
                text = "and"
            } else {
                text = "a"
            }
        } else {
            // Unsupported subdivision count
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.55
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1.0

        // Stop any ongoing speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        speechSynthesizer.speak(utterance)
    }

    /// Configure audio session for iOS
    #if os(iOS)
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    #endif
}
