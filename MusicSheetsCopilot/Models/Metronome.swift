// Metronome.swift
// MusicSheetsCopilot
//
// Provides a metronome that ticks in sync with the current tempo.

import Foundation
import AVFoundation

class Metronome: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var isTicking: Bool = false
    @Published var bpm: Double = 120.0 {
        didSet { updateTimer() }
    }
    @Published var timeSignature: (Int, Int) = (4, 4)

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var tickCount: Int = 0

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
        updateTimer()
    }

    func stop() {
        isTicking = false
        timer?.invalidate()
        timer = nil
    }

    private func updateTimer() {
        timer?.invalidate()
        guard isEnabled && isTicking else { return }
        let interval = 60.0 / bpm
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        playTickSound()
        tickCount += 1
        if tickCount >= timeSignature.0 {
            tickCount = 0
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
}
