import AVFoundation

/// A single Surge XT instance for one tracker voice. Event positions are
/// calculated from PlaybackTimeline before playback; the render callback only
/// applies those events and asks the embedded DSP for PCM. No UI timer starts
/// notes.
final class SurgeVoiceNode {
    struct Event {
        let frame: Int64
        let key: UInt8
        let velocity: UInt8
        let isOn: Bool
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
    var gain: Float = 0.8

    init?(patchURL: URL, sampleRate: Double = 44_100) {
        self.sampleRate = sampleRate
        scratch = .allocate(capacity: scratchFrames * 2)
        guard let dataURL = Bundle.main.resourceURL?.appendingPathComponent("data", isDirectory: true) else {
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

    func schedule(notes: [PlaybackTimeline.Note], from beat: Double, bpm: Double) {
        let framesPerBeat = sampleRate * 60 / max(20, bpm)
        var scheduled: [Event] = []
        scheduled.reserveCapacity(notes.count * 2)
        for note in notes {
            let onFrame = Int64(((note.beat - beat) * framesPerBeat).rounded())
            let offFrame = Int64(((note.beat + note.duration - beat) * framesPerBeat).rounded())
            if onFrame >= 0 { scheduled.append(Event(frame: onFrame, key: note.key, velocity: note.velocity, isOn: true)) }
            if offFrame >= 0 { scheduled.append(Event(frame: offFrame, key: note.key, velocity: 0, isOn: false)) }
        }
        events = scheduled.sorted { $0.frame == $1.frame ? (!$0.isOn && $1.isOn) : $0.frame < $1.frame }
        eventIndex = 0
        originSampleTime = nil
        active = false
        if let surge { rtk_surge_all_notes_off(surge) }
    }

    func activate() { active = true }
    func stop() { active = false; if let surge { rtk_surge_all_notes_off(surge) } }
    func noteOn(_ note: UInt8, velocity: UInt8) { if let surge { rtk_surge_note_on(surge, note, velocity) }; active = true }
    func noteOff(_ note: UInt8) { if let surge { rtk_surge_note_off(surge, note) } }

    private func render(timestamp: UnsafePointer<AudioTimeStamp>, frameCount: Int, buffers: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let bufferList = UnsafeMutableAudioBufferListPointer(buffers)
        func silence() {
            for buffer in bufferList where buffer.mDataByteSize > 0 { memset(buffer.mData, 0, Int(buffer.mDataByteSize)) }
        }
        guard active, let surge else { silence(); return noErr }
        let start = Int64(timestamp.pointee.mSampleTime)
        if originSampleTime == nil { originSampleTime = start }
        let relativeStart = start - (originSampleTime ?? start)
        var rendered = 0
        while rendered < frameCount {
            let current = relativeStart + Int64(rendered)
            while eventIndex < events.count && events[eventIndex].frame <= current {
                let event = events[eventIndex]
                if event.isOn { rtk_surge_note_on(surge, event.key, event.velocity) }
                else { rtk_surge_note_off(surge, event.key) }
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
