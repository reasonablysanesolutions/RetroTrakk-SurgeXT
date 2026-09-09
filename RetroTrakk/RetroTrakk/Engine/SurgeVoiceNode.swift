import AVFoundation

/// A single Surge XT instance for one tracker voice. Event positions are
/// calculated from PlaybackTimeline before playback; the render callback only
/// applies those events and asks the embedded DSP for PCM. No UI timer starts
/// notes.
final class SurgeVoiceNode {
    struct Event {
        enum Kind {
            case noteOn
            case noteOff
            case releaseAll
        }
        let frame: Int64
        let key: UInt8
        let velocity: UInt8
        let kind: Kind
    }

    private enum Command {
        case noteOn(UInt8, UInt8)
        case noteOff(UInt8)
        case allNotesOff
    }

    private(set) var node: AVAudioSourceNode!
    private let sampleRate: Double
    private let scratch: UnsafeMutablePointer<Float>
    private let scratchFrames = 8_192
    private var surge: OpaquePointer?
    private var events: [Event] = []
    private var eventIndex = 0
    private var originSampleTime: Int64?
    private var active = false
    /// Surge's synth instance is not thread-safe. UI/MIDI calls enqueue a
    /// command here; only the Core Audio render callback touches the DSP.
    private let commandLock = NSLock()
    private var pendingCommands: [Command] = []
    var gain: Float = 0.8

    init?(patchURL: URL, sampleRate: Double = 44_100) {
        self.sampleRate = sampleRate
        scratch = .allocate(capacity: scratchFrames * 2)
        guard let dataURL = Bundle.main.resourceURL?.appendingPathComponent("SurgeRuntimeData", isDirectory: true) else {
            scratch.deallocate(); return nil
        }
        surge = rtk_surge_create(dataURL.path, sampleRate)
        guard let surge, rtk_surge_load_patch(surge, patchURL.path) != 0 else {
            if let surge { rtk_surge_destroy(surge) }
            scratch.deallocate(); return nil
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        node = AVAudioSourceNode(format: format) { [weak self] _, timestamp, frameCount, buffers in
            self?.render(timestamp: timestamp, frameCount: Int(frameCount), buffers: buffers) ?? noErr
        }
    }

    deinit {
        if let surge { rtk_surge_destroy(surge) }
        scratch.deallocate()
    }

    func schedule(notes: [PlaybackTimeline.Note], fades: [PlaybackTimeline.Fade] = [], from beat: Double, bpm: Double) {
        let framesPerBeat = sampleRate * 60 / max(20, bpm)
        var scheduled: [Event] = []
        scheduled.reserveCapacity(notes.count * 2)
        for note in notes {
            let onFrame = Int64(((note.beat - beat) * framesPerBeat).rounded())
            let offFrame = Int64(((note.beat + note.duration - beat) * framesPerBeat).rounded())
            if onFrame >= 0 { scheduled.append(Event(frame: onFrame, key: note.key, velocity: note.velocity, kind: .noteOn)) }
            if offFrame >= 0 { scheduled.append(Event(frame: offFrame, key: note.key, velocity: 0, kind: .noteOff)) }
        }
        for fade in fades {
            let frame = Int64(((fade.beat - beat) * framesPerBeat).rounded())
            if frame >= 0 { scheduled.append(Event(frame: frame, key: 0, velocity: 0, kind: .releaseAll)) }
        }
        commandLock.lock()
        events = scheduled.sorted {
            if $0.frame != $1.frame { return $0.frame < $1.frame }
            func rank(_ kind: Event.Kind) -> Int {
                switch kind {
                case .releaseAll: return 0
                case .noteOff: return 1
                case .noteOn: return 2
                }
            }
            return rank($0.kind) < rank($1.kind)
        }
        eventIndex = 0
        originSampleTime = nil
        active = false
        pendingCommands.append(.allNotesOff)
        commandLock.unlock()
    }

    func activate() {
        commandLock.lock(); active = true; commandLock.unlock()
    }
    func stop() {
        commandLock.lock()
        active = false
        pendingCommands.append(.allNotesOff)
        commandLock.unlock()
    }
    func noteOn(_ note: UInt8, velocity: UInt8) {
        commandLock.lock()
        active = true
        pendingCommands.append(.noteOn(note, velocity))
        commandLock.unlock()
    }
    func noteOff(_ note: UInt8) { enqueue(.noteOff(note)) }

    private func enqueue(_ command: Command) {
        commandLock.lock()
        pendingCommands.append(command)
        commandLock.unlock()
    }

    private func consumeRenderState() -> (active: Bool, commands: [Command]) {
        commandLock.lock()
        defer { commandLock.unlock() }
        let commands = pendingCommands
        pendingCommands.removeAll(keepingCapacity: true)
        return (active, commands)
    }

    private func render(timestamp: UnsafePointer<AudioTimeStamp>, frameCount: Int, buffers: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let bufferList = UnsafeMutableAudioBufferListPointer(buffers)
        func silence() {
            for buffer in bufferList where buffer.mDataByteSize > 0 { memset(buffer.mData, 0, Int(buffer.mDataByteSize)) }
        }
        let state = consumeRenderState()
        guard state.active, let surge else { silence(); return noErr }
        for command in state.commands {
            switch command {
            case let .noteOn(note, velocity): rtk_surge_note_on(surge, note, velocity)
            case let .noteOff(note): rtk_surge_note_off(surge, note)
            case .allNotesOff: rtk_surge_all_notes_off(surge)
            }
        }
        let start = Int64(timestamp.pointee.mSampleTime)
        if originSampleTime == nil { originSampleTime = start }
        let relativeStart = start - (originSampleTime ?? start)
        var rendered = 0
        while rendered < frameCount {
            let current = relativeStart + Int64(rendered)
            while eventIndex < events.count && events[eventIndex].frame <= current {
                let event = events[eventIndex]
                switch event.kind {
                case .noteOn: rtk_surge_note_on(surge, event.key, event.velocity)
                case .noteOff: rtk_surge_note_off(surge, event.key)
                case .releaseAll: rtk_surge_all_notes_off(surge)
                }
                eventIndex += 1
            }
            let nextEvent = eventIndex < events.count ? events[eventIndex].frame : Int64.max
            let untilEvent = max(1, Int(nextEvent - current))
            let count = min(scratchFrames, frameCount - rendered, untilEvent)
            rtk_surge_render(surge, scratch, Int32(count))
            for channel in 0..<min(2, bufferList.count) {
                guard let output = bufferList[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<count { output[rendered + frame] = scratch[frame * 2 + channel] * gain }
            }
            rendered += count
        }
        return noErr
    }
}
