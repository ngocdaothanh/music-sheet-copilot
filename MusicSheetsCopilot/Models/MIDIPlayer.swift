import Foundation
import AVFoundation
import CoreMIDI

/// Simple MIDI player using AVMIDIPlayer
class MIDIPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0 {
        didSet {
            midiPlayer?.rate = playbackRate
        }
    }
    @Published var timeSignature: (Int, Int) = (4, 4)

    private var midiPlayer: AVMIDIPlayer?
    private var updateTimer: Timer?
    private var midiData: Data?
    // Note events array is internal to allow Metronome to access for metronome-only mode
    // Includes channel information: channel 0 = first staff, channel 1 = second staff, etc.
    var noteEvents: [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] = []
    private var firstStaffChannel: UInt8 = 0  // Cache the first staff's channel

    /// Load MIDI data and prepare for playback
    func loadMIDI(data: Data) throws {
        stop()

        do {
            midiPlayer = try AVMIDIPlayer(data: data, soundBankURL: nil)
            midiPlayer?.rate = playbackRate
            duration = midiPlayer?.duration ?? 0
            midiData = data
            noteEvents = parseMIDINoteEvents(data: data)
            // Cache the first staff's channel
            firstStaffChannel = noteEvents.map { $0.channel }.min() ?? 0
            print("DEBUG MIDIPlayer: First staff channel is \(firstStaffChannel)")
            print("DEBUG MIDIPlayer: All unique channels: \(Set(noteEvents.map { $0.channel }).sorted())")
            print("DEBUG MIDIPlayer: Total note events: \(noteEvents.count)")
        } catch {
            throw error
        }
    }

    /// Load note events from separate MIDI data (for filtered staff playback)
    /// This doesn't affect the main MIDI player, only updates noteEvents for solfege mode
    func loadNoteEventsFromFilteredMIDI(data: Data) {
        let filteredEvents = parseMIDINoteEvents(data: data)
        noteEvents = filteredEvents
        firstStaffChannel = filteredEvents.map { $0.channel }.min() ?? 0
        print("DEBUG MIDIPlayer: Loaded filtered note events")
        print("DEBUG MIDIPlayer: Filtered channels: \(Set(filteredEvents.map { $0.channel }).sorted())")
        print("DEBUG MIDIPlayer: Filtered note events count: \(filteredEvents.count)")
        print("DEBUG MIDIPlayer: Sample filtered notes: \(filteredEvents.prefix(5).map { $0.midiNote })")
    
        print("DEBUG MIDIPlayer: Loaded filtered note events")
        print("DEBUG MIDIPlayer: Filtered channels: \(Set(filteredEvents.map { $0.channel }).sorted())")
        print("DEBUG MIDIPlayer: Filtered note events: \(filteredEvents.count)")
    }

    /// Start or resume playback
    /// - Parameter fromPosition: Optional position to start from (in seconds). If nil, continues from current position.
    func play(fromPosition: TimeInterval? = nil) {
        guard let player = midiPlayer else {
            return
        }

        // Reset to beginning if we're at the end (and not explicitly seeking)
        if fromPosition == nil && player.currentPosition >= player.duration {
            player.currentPosition = 0
            currentTime = 0
        }

        player.prepareToPlay()

        // Ensure playback rate is set
        player.rate = playbackRate

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
            }
        }

        isPlaying = true
        startTimer()
    }

    /// Pause playback
    func pause() {
        midiPlayer?.stop()
        isPlaying = false
        stopTimer()
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

    /// Parse MIDI data to extract note on events with their timestamps and channels
    private func parseMIDINoteEvents(data: Data) -> [(time: TimeInterval, midiNote: UInt8, channel: UInt8)] {
        var events: [(TimeInterval, UInt8, UInt8)] = []

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
        var foundTimeSignature = false

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
                    // Time signature meta event (0x58)
                    else if metaType == 0x58 && length == 4 && offset + 4 <= data.count && !foundTimeSignature {
                        let numerator = Int(data[offset])
                        let denominatorPower = Int(data[offset+1])
                        let denominator = Int(pow(2.0, Double(denominatorPower)))
                        DispatchQueue.main.async {
                            self.timeSignature = (numerator, denominator)
                        }
                        foundTimeSignature = true
                    }

                    offset += Int(length)
                }
                // Note On event (0x90-0x9F)
                else if (status & 0xF0) == 0x90 {
                    if offset + 1 < data.count {
                        let note = data[offset]
                        let velocity = data[offset+1]
                        let channel = status & 0x0F  // Extract channel from status byte
                        offset += 2

                        // Only add if velocity > 0 (velocity 0 is note off)
                        if velocity > 0 {
                            events.append((currentTime, note, channel))
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
    /// Note events are already filtered to first staff via loadNoteEventsFromFilteredMIDI
    func getNotesAtTime(_ time: TimeInterval) -> [UInt8] {
        guard !noteEvents.isEmpty else { return [] }

        let tolerance: TimeInterval = 0.1
        let notesAtTime = noteEvents.filter { abs($0.time - time) < tolerance }

        return notesAtTime.map { $0.midiNote }
    }

    deinit {
        stop()
    }
}
