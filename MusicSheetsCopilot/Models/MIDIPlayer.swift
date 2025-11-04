//
//  MIDIPlayer.swift
//  MusicSheetsCopilot
//
//  Created on November 4, 2025.
//

import Foundation
import AVFoundation
import CoreMIDI

/// Simple MIDI player using AVMIDIPlayer
class MIDIPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var midiPlayer: AVMIDIPlayer?
    private var updateTimer: Timer?
    private var midiData: Data?
    private var noteEvents: [(time: TimeInterval, midiNote: UInt8)] = []

    /// Load MIDI data and prepare for playback
    func loadMIDI(data: Data) throws {
        stop()

        do {
            midiPlayer = try AVMIDIPlayer(data: data, soundBankURL: nil)
            duration = midiPlayer?.duration ?? 0
            midiData = data
            noteEvents = parseMIDINoteEvents(data: data)
            print("MIDI loaded successfully - duration: \(duration)s")
            print("Extracted \(noteEvents.count) note events")
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

    /// Parse MIDI data to extract note on events with their timestamps
    private func parseMIDINoteEvents(data: Data) -> [(time: TimeInterval, midiNote: UInt8)] {
        var events: [(TimeInterval, UInt8)] = []

        // Basic MIDI file parsing
        guard data.count > 14 else { return events }

        var offset = 0

        // Read header chunk
        guard data.count >= 14,
              String(data: data.subdata(in: 0..<4), encoding: .ascii) == "MThd" else {
            return events
        }

        offset = 14 // Skip header

        // Read track chunks
        var currentTime: Double = 0
        var ticksPerQuarterNote: UInt16 = 480 // Default

        // Extract ticks per quarter note from header
        if data.count >= 13 {
            ticksPerQuarterNote = UInt16(data[12]) << 8 | UInt16(data[13])
        }

        var microsecondsPerQuarterNote: Double = 500000 // Default 120 BPM

        while offset < data.count - 8 {
            // Check for track chunk
            guard let chunkType = String(data: data.subdata(in: offset..<offset+4), encoding: .ascii) else {
                break
            }

            if chunkType != "MTrk" {
                offset += 4
                continue
            }

            offset += 4

            // Read chunk length
            let chunkLength = Int(data[offset]) << 24 | Int(data[offset+1]) << 16 |
                             Int(data[offset+2]) << 8 | Int(data[offset+3])
            offset += 4

            let trackEnd = offset + chunkLength
            currentTime = 0

            // Parse events in this track
            while offset < trackEnd && offset < data.count {
                // Read variable-length delta time
                var deltaTime: UInt32 = 0
                var byte: UInt8
                repeat {
                    if offset >= data.count { break }
                    byte = data[offset]
                    offset += 1
                    deltaTime = (deltaTime << 7) | UInt32(byte & 0x7F)
                } while (byte & 0x80) != 0

                // Convert delta time to seconds
                let deltaSeconds = Double(deltaTime) * microsecondsPerQuarterNote / Double(ticksPerQuarterNote) / 1_000_000
                currentTime += deltaSeconds

                // Read event type
                if offset >= data.count { break }
                let status = data[offset]
                offset += 1

                // Meta event
                if status == 0xFF {
                    if offset >= data.count { break }
                    let metaType = data[offset]
                    offset += 1

                    // Read length
                    var length: UInt32 = 0
                    repeat {
                        if offset >= data.count { break }
                        byte = data[offset]
                        offset += 1
                        length = (length << 7) | UInt32(byte & 0x7F)
                    } while (byte & 0x80) != 0

                    // Set tempo meta event
                    if metaType == 0x51 && length == 3 && offset + 3 <= data.count {
                        microsecondsPerQuarterNote = Double(data[offset]) * 65536 +
                                                    Double(data[offset+1]) * 256 +
                                                    Double(data[offset+2])
                    }

                    offset += Int(length)
                }
                // Note On event (0x90-0x9F)
                else if (status & 0xF0) == 0x90 {
                    if offset + 1 < data.count {
                        let note = data[offset]
                        let velocity = data[offset+1]
                        offset += 2

                        // Only add if velocity > 0 (velocity 0 is note off)
                        if velocity > 0 {
                            events.append((currentTime, note))
                        }
                    }
                }
                // Note Off event (0x80-0x8F) or other channel events
                else if (status & 0xF0) == 0x80 || (status & 0xF0) == 0xA0 ||
                        (status & 0xF0) == 0xB0 || (status & 0xF0) == 0xE0 {
                    offset += 2 // Skip 2 data bytes
                }
                else if (status & 0xF0) == 0xC0 || (status & 0xF0) == 0xD0 {
                    offset += 1 // Skip 1 data byte
                }
            }
        }

        return events.sorted(by: { $0.0 < $1.0 })
    }

    /// Get notes playing at or near a specific time (within 100ms window)
    func getNotesAtTime(_ time: TimeInterval) -> [UInt8] {
        let tolerance: TimeInterval = 0.1
        return noteEvents
            .filter { abs($0.0 - time) < tolerance }
            .map { $0.1 }
    }

    deinit {
        stop()
    }
}
