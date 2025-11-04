// Metronome.swift
// MusicSheetsCopilot
//
// Provides a metronome that ticks in sync with the current tempo.

import Foundation
import AVFoundation

enum MetronomeMode {
    case tick        // Traditional tick sound
    case solfege     // Do Re Mi based on actual notes
    case counting    // One Two Three Four based on beats
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

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var tickCount: Int = 0
    private var speechSynthesizer = AVSpeechSynthesizer()

    // Reference to MIDIPlayer for getting current notes
    weak var midiPlayer: MIDIPlayer?
    private var lastSpokenTime: TimeInterval = -1
    private var lastSpokenNotes: Set<UInt8> = []

    // Map MIDI note number to solfege syllable
    // MIDI notes: C=0, C#=1, D=2, D#=3, E=4, F=5, F#=6, G=7, G#=8, A=9, A#=10, B=11
    private func midiNoteToSolfege(_ midiNote: UInt8) -> String {
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
        lastSpokenTime = -1
        lastSpokenNotes = []

        // Play an immediate tick/count when starting
        if mode == .tick {
            playTickSound()
        } else if mode == .counting {
            speakCount()
            // Increment tickCount so the timer continues from the next beat
            tickCount += 1
            if tickCount >= timeSignature.0 {
                tickCount = 0
            }
        }

        updateTimer()
    }

    func stop() {
        isTicking = false
        timer?.invalidate()
        timer = nil
        lastSpokenTime = -1
        lastSpokenNotes = []
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

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        switch mode {
        case .tick:
            playTickSound()
            tickCount += 1
            if tickCount >= timeSignature.0 {
                tickCount = 0
            }
        case .solfege:
            speakNotesAtCurrentTime()
        case .counting:
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
            print("Failed to play metronome tick: \(error)")
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
