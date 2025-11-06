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
    var firstStaffChannel: UInt8 = 0  // Cache the first staff's channel

    /// Load MIDI data and prepare for playback
    func loadMIDI(data: Data) throws {
        stop()

        // Configure audio session for iOS
        #if os(iOS)
        configureAudioSession()
        #endif

        // Validate MIDI data before attempting to load
        guard data.count > 14 else {
            throw NSError(domain: "MIDIPlayer", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "MIDI data is too small (\(data.count) bytes) to be valid"])
        }

        guard let headerString = String(data: data.subdata(in: 0..<4), encoding: .ascii),
              headerString == "MThd" else {
            let headerBytes = data.subdata(in: 0..<min(4, data.count))
            throw NSError(domain: "MIDIPlayer", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid MIDI file header. Got: \(headerBytes.map { String(format: "%02X", $0) }.joined(separator: " "))"])
        }

        // Validate header structure
        guard data.count >= 14 else {
            throw NSError(domain: "MIDIPlayer", code: -4,
                         userInfo: [NSLocalizedDescriptionKey: "MIDI data too short for complete header"])
        }

        // Read header length (should be 6)
        let headerLength = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 |
                          UInt32(data[6]) << 8 | UInt32(data[7])
        guard headerLength == 6 else {
            throw NSError(domain: "MIDIPlayer", code: -5,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid MIDI header length: \(headerLength), expected 6"])
        }

        // Check for at least one track chunk header
        guard data.count >= 22 else { // 14 (header) + 8 (track chunk header minimum)
            throw NSError(domain: "MIDIPlayer", code: -6,
                         userInfo: [NSLocalizedDescriptionKey: "MIDI data too short to contain track data"])
        }

        // AVMIDIPlayer can crash if the MIDI data is malformed
        // Try to initialize with error handling
        // Some versions of AVMIDIPlayer work better with file URLs than raw data
        do {
            // Try data-based initialization first
            let player = try AVMIDIPlayer(data: data, soundBankURL: nil)
            midiPlayer = player
            midiPlayer?.rate = playbackRate
            duration = midiPlayer?.duration ?? 0
            midiData = data
            noteEvents = parseMIDINoteEvents(data: data)
            // Cache the first staff's channel
            firstStaffChannel = noteEvents.map { $0.channel }.min() ?? 0
        } catch let error as NSError {
            print("Failed to initialize AVMIDIPlayer with data: \(error.localizedDescription)")
            print("Error domain: \(error.domain), code: \(error.code)")
            print("MIDI data size: \(data.count) bytes")
            print("First 20 bytes: \(data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " "))")

            // Try writing to temp file as a fallback
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let tempFile = tempDir.appendingPathComponent("temp_midi_\(UUID().uuidString).mid")
                try data.write(to: tempFile)

                defer {
                    try? FileManager.default.removeItem(at: tempFile)
                }

                let player = try AVMIDIPlayer(contentsOf: tempFile, soundBankURL: nil)
                midiPlayer = player
                midiPlayer?.rate = playbackRate
                duration = midiPlayer?.duration ?? 0
                midiData = data
                noteEvents = parseMIDINoteEvents(data: data)
                firstStaffChannel = noteEvents.map { $0.channel }.min() ?? 0

                print("Successfully loaded MIDI from temp file")
            } catch {
                print("Failed to initialize AVMIDIPlayer from file as well: \(error.localizedDescription)")
                throw NSError(domain: "MIDIPlayer", code: -3,
                             userInfo: [NSLocalizedDescriptionKey: "AVMIDIPlayer failed: \(error.localizedDescription)"])
            }
        }
    }

    /// Load note events from separate MIDI data (for filtered staff playback)
    /// This doesn't affect the main MIDI player, only updates noteEvents for solfege mode
    func loadNoteEventsFromFilteredMIDI(data: Data) {
        let filteredEvents = parseMIDINoteEvents(data: data)
        noteEvents = filteredEvents
        firstStaffChannel = filteredEvents.map { $0.channel }.min() ?? 0
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
        stopTimer()

        guard let player = midiPlayer else { return }

        player.stop()
        player.currentPosition = 0
        currentTime = 0
        isPlaying = false
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

        // Clamp time to valid range. If duration is unknown (0), allow seeking to requested time
        let seekTime: TimeInterval
        if duration > 0 {
            // Avoid seeking exactly to duration which can cause AVMIDIPlayer to finish immediately
            let epsilon: TimeInterval = 0.01
            let maxSeekable = max(0, duration - epsilon)
            seekTime = max(0, min(time, maxSeekable))
        } else {
            // duration not yet known -> don't clamp to 0 which would jump to start
            seekTime = max(0, time)
        }

    // Debug logs removed

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
        // Invalidate any existing timer first
        stopTimer()

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard let player = self.midiPlayer else { return }

            // Use weak reference to avoid retain cycles and check if still valid
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.currentTime = player.currentPosition
            }
        }
        // Add timer to run loop with .common mode to ensure it continues firing
        // even when UI interactions (like dropdown menus) are happening
        RunLoop.current.add(timer, forMode: .common)
        updateTimer = timer
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

    /// Get notes playing at or near a specific time (within 100ms window)
    /// Note events are already filtered to first staff via loadNoteEventsFromFilteredMIDI
    func getNotesAtTime(_ time: TimeInterval) -> [UInt8] {
        guard !noteEvents.isEmpty else { return [] }

        let tolerance: TimeInterval = 0.1
        let notesAtTime = noteEvents.filter { abs($0.time - time) < tolerance }

        return notesAtTime.map { $0.midiNote }
    }

    deinit {
        // Stop the timer first to prevent any callbacks during deallocation
        updateTimer?.invalidate()
        updateTimer = nil

        // Stop the MIDI player
        midiPlayer?.stop()
        midiPlayer = nil
    }
}
