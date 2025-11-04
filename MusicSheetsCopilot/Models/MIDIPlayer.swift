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
    /// - Parameter fromPosition: Optional position to start from (in seconds). If nil, continues from current position.
    func play(fromPosition: TimeInterval? = nil) {
        guard let player = midiPlayer else {
            print("No MIDI data loaded")
            return
        }

        // Reset to beginning if we're at the end (and not explicitly seeking)
        if fromPosition == nil && player.currentPosition >= player.duration {
            player.currentPosition = 0
            currentTime = 0
        }

        player.prepareToPlay()

        // Set position AFTER prepareToPlay if specified
        if let startPosition = fromPosition {
            player.currentPosition = startPosition
            currentTime = startPosition
        }

        player.play {
            DispatchQueue.main.async {
                self.isPlaying = false
                self.stopTimer()
                // Reset to beginning when finished
                self.midiPlayer?.currentPosition = 0
                self.currentTime = 0
                print("MIDI playback finished")
            }
        }

        isPlaying = true
        startTimer()
        print("MIDI playback started from position: \(player.currentPosition)s")
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

    /// Seek to a specific time position (in seconds)
    func seek(to time: TimeInterval) {
        guard let player = midiPlayer else {
            print("No MIDI data loaded")
            return
        }

        // Clamp time to valid range
        let seekTime = max(0, min(time, duration))

        let wasPlaying = isPlaying
        if wasPlaying {
            pause()
        }

        // Update current time immediately for UI
        currentTime = seekTime
        print("Seeked to position: \(seekTime)s")

        if wasPlaying {
            // Small delay to ensure UI updates before resuming playback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.play(fromPosition: seekTime)
            }
        } else {
            // Just update position without playing
            player.currentPosition = seekTime
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
