//
//  MIDIPlayer.swift
//  MusicSheetsCopilot
//
//  Created on November 4, 2025.
//

import Foundation
import AVFoundation

/// Simple MIDI player using AVMIDIPlayer
class MIDIPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var midiPlayer: AVMIDIPlayer?
    private var updateTimer: Timer?

    /// Load MIDI data and prepare for playback
    func loadMIDI(data: Data) throws {
        stop()

        do {
            midiPlayer = try AVMIDIPlayer(data: data, soundBankURL: nil)
            duration = midiPlayer?.duration ?? 0
            print("MIDI loaded successfully - duration: \(duration)s")
        } catch {
            print("Failed to create MIDI player: \(error)")
            throw error
        }
    }

    /// Start or resume playback
    func play() {
        guard let player = midiPlayer else {
            print("No MIDI data loaded")
            return
        }

        player.play {
            DispatchQueue.main.async {
                self.isPlaying = false
                self.currentTime = 0
                self.stopTimer()
            }
        }

        isPlaying = true
        startTimer()
        print("MIDI playback started")
    }

    /// Pause playback
    func pause() {
        midiPlayer?.stop()
        isPlaying = false
        stopTimer()
        print("MIDI playback paused")
    }

    /// Stop playback and reset to beginning
    func stop() {
        midiPlayer?.stop()
        midiPlayer?.currentPosition = 0
        currentTime = 0
        isPlaying = false
        stopTimer()
    }

    /// Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    private func startTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.midiPlayer else { return }
            DispatchQueue.main.async {
                self.currentTime = player.currentPosition
            }
        }
    }

    private func stopTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    deinit {
        stop()
    }
}
