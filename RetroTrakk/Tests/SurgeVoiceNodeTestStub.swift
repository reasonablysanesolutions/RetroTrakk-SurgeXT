import AVFoundation

// The timing suite compiles Swift sources directly. Native Surge DSP linking is
// covered by SurgeBridgeSmoke.mm; this keeps model/timeline checks independent.
final class SurgeVoiceNode {
    let node = AVAudioMixerNode()
    var gain: Float = 0.8
    init?(patchURL: URL, sampleRate: Double = 44_100) {}
    func schedule(notes: [PlaybackTimeline.Note], fades: [PlaybackTimeline.Fade] = [], from beat: Double, bpm: Double) {}
    func activate() {}
    func stop() {}
    func noteOn(_ note: UInt8, velocity: UInt8) {}
    func noteOff(_ note: UInt8) {}
}
