import Foundation
import AVFoundation

enum MetronomeMode {
    case tick        // Traditional tick sound
    case counting    // One Two Three Four based on beats
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

    private var audioPlayer: AVAudioPlayer?
    private var timer: TimerProtocol?  // Changed from Timer? to TimerProtocol?
    private var tickCount: Int = 0
    private var speechSynthesizer = AVSpeechSynthesizer()
    
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

    // Map MIDI note number to solfege syllable
    // MIDI notes: C=0, C#=1, D=2, D#=3, E=4, F=5, F#=6, G=7, G#=8, A=9, A#=10, B=11
    func midiNoteToSolfege(_ midiNote: UInt8) -> String {
        let noteInOctave = Int(midiNote) % 12
        let solfegeMap = [
            "Do",  // C
            "Do",  // C# (same as C)
            "Re",  // D
            "Re",  // D# (same as D)
            "Mi",  // E
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
        // Calculate total duration from the last note event (add a bit of buffer)
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
        data.append(Data(buffer: UnsafeBufferPointer(start: &buffer, count: samples)))
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
        isTicking = true
        tickCount = 0
        currentBeat = 0  // Reset visual beat indicator
        lastSpokenTime = -1
        lastSpokenNotes = []
        lastBeatTime = 0  // Reset beat timing

        // Initialize metronome-only mode timing
        metronomeStartTime = timeProvider.now()
        metronomePausedTime = 0

        // Play an immediate tick/count when starting
        if mode == .tick {
            playTickSound()
            // Increment tickCount so the timer continues from the next beat
            tickCount += 1
            if tickCount >= timeSignature.0 {
                tickCount = 0
            }
        } else if mode == .counting {
            speakCount()
            // Increment tickCount and currentBeat so the timer continues from the next beat
            tickCount += 1
            currentBeat = 1
            if tickCount >= timeSignature.0 {
                tickCount = 0
                currentBeat = 0
            }
        } else if mode == .solfege {
            // In solfege mode, speak the first note immediately if available
            if !noteEvents.isEmpty && midiPlayer?.isPlaying != true {
                speakNotesAtMetronomeTime()
            }
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
        metronomeStartTime = nil
        metronomePausedTime = 0
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func updateTimer() {
        timer?.invalidate()
        guard isEnabled && isTicking else { return }

        // Adjust BPM by playback rate
        let adjustedBPM = bpm * Double(playbackRate)

        // When using solfege names, check more frequently to catch note events
        let interval = mode == .solfege ? 0.05 : (60.0 / adjustedBPM)

        timer = timeProvider.scheduleTimer(interval: interval, repeats: true) { [weak self] in
            self?.tick()
        }
    }

    private func tick() {
        // Check if we've reached the end of the piece in metronome-only mode
        if midiPlayer?.isPlaying != true && totalDuration > 0 {
            let currentMetronomeTime = getCurrentMetronomeTime()
            if currentMetronomeTime >= totalDuration {
                // Reached the end - stop playback
                stop()
                return
            }
        }

        switch mode {
        case .tick:
            playTickSound()
            currentBeat = tickCount  // Update visual indicator before incrementing
            tickCount += 1
            if tickCount >= timeSignature.0 {
                tickCount = 0
            }
        case .solfege:
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
            currentBeat = tickCount  // Update visual indicator before incrementing
            speakCount()
            tickCount += 1
            if tickCount >= timeSignature.0 {
                tickCount = 0
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

        // Get unique solfege syllables for the notes
        let syllables = notes.map { midiNoteToSolfege($0) }
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

        // Get unique solfege syllables for the notes
        let syllables = notesToSpeak.map { midiNoteToSolfege($0.midiNote) }
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

    private func speakCount() {
        // Speak the beat number (1, 2, 3, 4...)
        let beatNumber = tickCount + 1
        let numberWords = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight",
                          "Nine", "Ten", "Eleven", "Twelve"]

        guard beatNumber <= numberWords.count else { return }

        let utterance = AVSpeechUtterance(string: numberWords[beatNumber - 1])
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
