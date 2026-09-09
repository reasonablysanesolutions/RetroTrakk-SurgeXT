import Foundation
import AVFoundation
import Combine

/// All graph and sequence edits occur on the main thread. Core Audio schedules
/// the MIDI events independently of UI refreshes, in musical beats.
public final class RetroTrakkAudioEngine: ObservableObject {
    @Published public var isRunning = false
    @Published public var statusText = "Motorn stoppad"
    @Published public var availableAUs: [AUInfo] = []
    @Published public var loadingInstrument: String?
    private var loadToken = UUID()
    private let loader = DispatchQueue(label: "RetroTrakk.instrumentLoading", qos: .userInitiated)
    public let engine = AVAudioEngine()
    public let master = AVAudioMixerNode()
    public let previewMixer = AVAudioMixerNode()
    public var channelMixers: [AVAudioMixerNode] = []
    private var previews: [Int: AVAudioUnitMIDIInstrument] = [:]
    private var surgePreviews: [Int: SurgeVoiceNode] = [:]
    private var previewModels: [Int: InstrumentModel] = [:]
    private var previewHeld: [Int: Set<UInt8>] = [:]
    private var voices: [PlaybackTimeline.Voice: AVAudioUnitMIDIInstrument] = [:]
    private var surgeVoices: [PlaybackTimeline.Voice: SurgeVoiceNode] = [:]
    private var voiceModels: [PlaybackTimeline.Voice: InstrumentModel] = [:]
    private var sequencer: AVAudioSequencer!
    private var tracks: [PlaybackTimeline.Voice: AVMusicTrack] = [:]
    // AVAudioSequencer rejects start when a project contains only source-node
    // voices. Keep an event-free track as the native transport's anchor.
    private var transportTrack: AVMusicTrack?
    private var sequenceNotes: [PlaybackTimeline.Note] = []
    private var sequenceFades: [PlaybackTimeline.Fade] = []
    private var sequenceSteps = 4.0
    private var sequenceLength = 0.0
    private var sequenceTempo = 120.0
    private var hasTempo = false

    // MARK: - Audition Preview
    private let auditionSampler = AVAudioUnitSampler()
    private var surgeAudition: SurgeVoiceNode?
    private var auditionDefinition: InstrumentDefinition?
    private var auditionHeldNotes = Set<UInt8>()
    private var auditionConfigured = false

    public init() {
        engine.attach(master)
        master.outputVolume = 1
        engine.connect(master, to: engine.mainMixerNode, format: nil)
        for i in 0..<SongModel.channelCount {
            let mixer = AVAudioMixerNode()
            engine.attach(mixer)
            engine.connect(mixer, to: master, fromBus: 0, toBus: i, format: nil)
            channelMixers.append(mixer)
        }
        engine.attach(previewMixer)
        engine.connect(previewMixer, to: master, fromBus: 0, toBus: SongModel.channelCount, format: nil)
        // AVAudioSequencer must be associated with the engine before that engine is
        // first started. Creating it lazily after app launch yields a moving but
        // silent transport on the hardware output, while offline WAV still works.
        sequencer = AVAudioSequencer(audioEngine: engine)
    }

    private var tapsInstalled = false

    private func playbackError(_ message: String, code: Int = 4) -> NSError {
        NSError(domain: "RetroTrakk", code: code,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// Starts the hardware-backed graph and propagates failures to transport.
    /// A running sequencer without a running AVAudioEngine advances visually but is silent.
    private func startEngineIfNeeded() throws {
        if engine.isRunning {
            isRunning = true
            return
        }
        engine.prepare()
        try engine.start()
        guard engine.isRunning else {
            throw playbackError("Ljudmotorn startade inte realtime-utgången.", code: 3)
        }
        isRunning = true
        statusText = String(format: "Redo — %.0f Hz", engine.outputNode.outputFormat(forBus: 0).sampleRate)
        installWaveformTaps()
    }

    public func start() {
        do {
            try startEngineIfNeeded()
        } catch {
            isRunning = false
            statusText = "Kunde inte starta: \(error.localizedDescription)"
        }
    }

    public func stopEngine() {
        stopPlayback()
        removeWaveformTaps()
        auditionAllOff()
        engine.stop()
        isRunning = false
    }

    private func installWaveformTaps() {
        guard !tapsInstalled else { return }
        for ch in 0..<channelMixers.count {
            let mixer = channelMixers[ch]
            let format = mixer.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { continue }
            mixer.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
                WaveformManager.shared.update(channel: ch, buffer: buffer)
            }
        }
        tapsInstalled = true
        WaveformManager.shared.startTimer()
    }

    private func removeWaveformTaps() {
        WaveformManager.shared.stopTimer()
        if tapsInstalled {
            for mixer in channelMixers {
                mixer.removeTap(onBus: 0)
            }
            tapsInstalled = false
        }
    }

    public func rescanAUs() { availableAUs = AudioUnitManager.shared.availableMusicDevices() }

    private func sameSound(_ a: InstrumentModel?, _ b: InstrumentModel) -> Bool {
        guard let a else { return false }
        return a.kind == b.kind && a.gmProgram == b.gmProgram && a.bankMSB == b.bankMSB &&
            a.bankLSB == b.bankLSB && a.isDrumKit == b.isDrumKit && a.midiChannel == b.midiChannel &&
            a.samplePath == b.samplePath && a.soundFontIdentifier == b.soundFontIdentifier &&
            a.surgePatchPath == b.surgePatchPath &&
            a.auName == b.auName && a.auManufacturer == b.auManufacturer
    }

    private func makeInstrument(_ inst: InstrumentModel) throws -> AVAudioUnitMIDIInstrument {
        let node: AVAudioUnitMIDIInstrument
        switch inst.kind {
        case .surge:
            throw playbackError("Surge XT använder sin inbyggda ljudnod.")
        case .coreSoundFont:
            let sampler = AVAudioUnitSampler()
            guard let sfURL = CoreSoundFont.resolveURL(identifier: inst.soundFontIdentifier) else {
                throw NSError(domain: "RetroTrakk", code: 2, userInfo: [NSLocalizedDescriptionKey: "SoundFont hittades inte för \(inst.name)."])
            }
            let msb = UInt8(max(0, min(127, inst.bankMSB)))
            let lsb = UInt8(max(0, min(127, inst.bankLSB)))
            let prog = UInt8(max(0, min(127, inst.gmProgram)))
            try sampler.loadSoundBankInstrument(at: sfURL, program: prog, bankMSB: msb, bankLSB: lsb)
            node = sampler
        case .dls:
            node = AVAudioUnitMIDIInstrument(audioComponentDescription: AudioUnitManager.dlsDescription())
        case .sample, .auSampler:
            let sampler = AVAudioUnitSampler()
            if let path = inst.samplePath, !path.isEmpty {
                let url = URL(fileURLWithPath: path)
                if ["exs", "aupreset"].contains(url.pathExtension.lowercased()) {
                    // EXS loading requires an attached engine (unlike loadAudioFiles).
                    // A staging graph allows disk work off the UI thread, then the
                    // fully loaded sampler is moved into the live/offline graph.
                    let staging = AVAudioEngine()
                    staging.attach(sampler)
                    staging.connect(sampler, to: staging.mainMixerNode, format: nil)
                    defer { staging.detach(sampler) }
                    try sampler.loadInstrument(at: url)
                } else { try sampler.loadAudioFiles(at: [url]) }
            }
            node = sampler
        case .audioUnit:
            let available = availableAUs.isEmpty ? AudioUnitManager.shared.availableMusicDevices() : availableAUs
            guard let match = available.first(where: { $0.name == inst.auName && (inst.auManufacturer == nil || $0.manufacturer == inst.auManufacturer) }) else {
                throw NSError(domain: "RetroTrakk", code: 1, userInfo: [NSLocalizedDescriptionKey: "Instrumentet \(inst.name) saknas."])
            }
            node = try AudioUnitManager.shared.instantiate(match)
        }
        return node
    }

    private func configureInstrument(_ node: AVAudioUnitMIDIInstrument, from inst: InstrumentModel) {
        let channel = UInt8(inst.midiChannel & 15)
        if !(node is AVAudioUnitSampler) {
            let msb = UInt8(max(0, min(127, inst.bankMSB)))
            let lsb = UInt8(max(0, min(127, inst.bankLSB)))
            node.sendMIDIEvent(0xB0 | channel, data1: 0, data2: msb)
            node.sendMIDIEvent(0xB0 | channel, data1: 32, data2: lsb)
            node.sendMIDIEvent(0xC0 | channel, data1: UInt8(max(0, min(127, inst.gmProgram))), data2: 0)
        }
        node.sendController(7, withValue: UInt8(max(0, min(127, Int(inst.volume * 127)))), onChannel: channel)
        node.sendController(10, withValue: UInt8(max(0, min(127, Int((inst.pan + 1) * 63.5)))), onChannel: channel)
    }

    private func loadInstrument(_ inst: InstrumentModel, into node: AVAudioUnitMIDIInstrument) throws {
        switch inst.kind {
        case .surge:
            return
        case .coreSoundFont:
            guard let sampler = node as? AVAudioUnitSampler else { return }
            guard let sfURL = CoreSoundFont.resolveURL(identifier: inst.soundFontIdentifier) else {
                throw NSError(domain: "RetroTrakk", code: 2, userInfo: [NSLocalizedDescriptionKey: "SoundFont hittades inte för \(inst.name)."])
            }
            let msb = UInt8(max(0, min(127, inst.bankMSB)))
            let lsb = UInt8(max(0, min(127, inst.bankLSB)))
            let prog = UInt8(max(0, min(127, inst.gmProgram)))
            try sampler.loadSoundBankInstrument(at: sfURL, program: prog, bankMSB: msb, bankLSB: lsb)
        case .sample, .auSampler:
            guard let sampler = node as? AVAudioUnitSampler else { return }
            if let path = inst.samplePath, !path.isEmpty {
                let url = URL(fileURLWithPath: path)
                if ["exs", "aupreset"].contains(url.pathExtension.lowercased()) {
                    try sampler.loadInstrument(at: url)
                } else {
                    try sampler.loadAudioFiles(at: [url])
                }
            }
        case .dls, .audioUnit:
            break
        }
    }

    @discardableResult
    public func ensureInstrument(_ inst: InstrumentModel) -> AVAudioNode? {
        if inst.kind == .surge {
            if let existing = surgePreviews[inst.id], sameSound(previewModels[inst.id], inst) { return existing.node }
            guard let voice = try? makeSurgeVoice(inst) else { return nil }
            removeInstrument(id: inst.id)
            engine.attach(voice.node)
            engine.connect(voice.node, to: previewMixer, format: nil)
            surgePreviews[inst.id] = voice; previewModels[inst.id] = inst
            start()
            return voice.node
        }
        if let node = previews[inst.id] {
            if sameSound(previewModels[inst.id], inst) { return node }
            // Snabb omladdning av CoreSoundFont direkt på befintlig sampler
            if inst.kind == .coreSoundFont, let sampler = node as? AVAudioUnitSampler {
                do {
                    try loadInstrument(inst, into: sampler)
                    configureInstrument(sampler, from: inst)
                    previewModels[inst.id] = inst
                    return sampler
                } catch {
                    // Vid eventuellt fel fall igenom till full ombyggnad nedan
                }
            }
        }
        do {
            let node = try makeInstrument(inst)
            removeInstrument(id: inst.id)
            engine.attach(node)
            // Preview has its own node, routed to previewMixer so channelMixers remain untouched.
            engine.connect(node, to: previewMixer, format: nil)
            try loadInstrument(inst, into: node)
            configureInstrument(node, from: inst)
            previews[inst.id] = node; previewModels[inst.id] = inst
            start()
            return node
        } catch {
            statusText = "Kunde inte ladda \(inst.name): \(error.localizedDescription)"
            return nil
        }
    }

    /// Förladda projektets aktiva instrument vid uppstart så att de är redo
    /// omedelbart utan fördröjning eller fallback vid första uppspelning/tangenttryck.
    public func prewarm(song: SongModel) {
        for inst in song.instruments {
            _ = ensureInstrument(inst)
        }
    }

    /// Disk reads and sampler decoding do not block scrolling or typing.
    func prepareSample(_ inst: InstrumentModel, completion: @escaping (Bool) -> Void) {
        let token = UUID(); loadToken = token; loadingInstrument = inst.name
        loader.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.makeInstrument(inst) }
            DispatchQueue.main.async {
                guard self.loadToken == token else { return }
                self.loadingInstrument = nil
                switch result {
                case .success(let node):
                    self.removeInstrument(id: inst.id)
                    self.engine.attach(node); self.engine.connect(node, to: self.previewMixer, format: nil)
                    self.configureInstrument(node, from: inst)
                    self.previews[inst.id] = node; self.previewModels[inst.id] = inst
                    self.start(); completion(true)
                case .failure(let error):
                    let code = (error as NSError).code
                    let reason = code == -43 ? "AUSampler hittar inte alla ljudfiler som instrumentet hänvisar till." :
                        code == -10868 ? "Instrumentet använder ett EXS-format som AUSampler inte stöder." : error.localizedDescription
                    self.statusText = "\(inst.name): \(reason)"
                    completion(false)
                }
            }
        }
    }

    func cancelInstrumentLoad() { loadToken = UUID(); loadingInstrument = nil }

    public func removeInstrument(id: Int) {
        if let node = previews.removeValue(forKey: id) {
            silence(node)
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }
        if let voice = surgePreviews.removeValue(forKey: id) {
            voice.stop(); engine.disconnectNodeOutput(voice.node); engine.detach(voice.node)
        }
        previewModels.removeValue(forKey: id)
        previewHeld.removeValue(forKey: id)
    }
    public func setProgram(_ inst: InstrumentModel) { _ = ensureInstrument(inst) }
    public func loadSample(into inst: InstrumentModel, url: URL) {
        var updated = inst; updated.samplePath = url.path; updated.kind = .sample
        _ = ensureInstrument(updated)
    }

    public func previewOn(inst: InstrumentModel, midiNote: UInt8, velocity: UInt8) {
        if inst.kind == .surge {
            guard let voice = surgePreviews[inst.id] ?? (ensureInstrument(inst).flatMap { _ in surgePreviews[inst.id] }) else { return }
            voice.noteOn(midiNote, velocity: velocity)
            previewHeld[inst.id, default: []].insert(midiNote)
            return
        }
        guard let node = ensureInstrument(inst) as? AVAudioUnitMIDIInstrument else { return }
        let ch = UInt8(inst.midiChannel & 15)
        if previewHeld[inst.id, default: []].contains(midiNote) {
            node.sendMIDIEvent(0x80 | ch, data1: midiNote, data2: 0)
        }
        node.sendMIDIEvent(0x90 | ch, data1: midiNote, data2: max(1, velocity))
        previewHeld[inst.id, default: []].insert(midiNote)
    }
    public func previewOff(instrumentId: Int, midiNote: UInt8) {
        guard previewHeld[instrumentId]?.remove(midiNote) != nil else { return }
        if let voice = surgePreviews[instrumentId] { voice.noteOff(midiNote); return }
        let ch = UInt8((previewModels[instrumentId]?.midiChannel ?? 0) & 15)
        previews[instrumentId]?.sendMIDIEvent(0x80 | ch, data1: midiNote, data2: 0)
    }
    private func silence(_ node: AVAudioUnitMIDIInstrument) {
        for ch: UInt8 in 0..<16 {
            node.sendMIDIEvent(0xB0 | ch, data1: 64, data2: 0)
            node.sendMIDIEvent(0xB0 | ch, data1: 123, data2: 0)
            node.sendMIDIEvent(0xB0 | ch, data1: 120, data2: 0)
        }
    }
    public func allNotesOff() {
        for node in previews.values { silence(node) }
        for voice in surgePreviews.values { voice.stop() }
        for node in voices.values { silence(node) }
        previewHeld.removeAll()
        auditionAllOff()
    }

    // MARK: - Browser Audition / Preview

    private func ensureAuditionEngine() {
        guard !auditionConfigured else { return }
        engine.attach(auditionSampler)
        engine.connect(auditionSampler, to: previewMixer, format: nil)
        auditionConfigured = true
    }

    public func auditionOn(definition: InstrumentDefinition, note: UInt8 = 60, velocity: UInt8 = 100) {
        if definition.sourceType == .surge {
            if auditionDefinition?.id != definition.id {
                if let old = surgeAudition { old.stop(); engine.disconnectNodeOutput(old.node); engine.detach(old.node) }
                guard let patch = SurgePresetCatalog.patchURL(relativePath: definition.sourceIdentifier),
                      let voice = SurgeVoiceNode(patchURL: patch) else { return }
                engine.attach(voice.node); engine.connect(voice.node, to: previewMixer, format: nil)
                surgeAudition = voice; auditionDefinition = definition
            }
            if !engine.isRunning { try? startEngineIfNeeded() }
            surgeAudition?.noteOn(note, velocity: velocity)
            auditionHeldNotes.insert(note)
            return
        }
        ensureAuditionEngine()
        if !engine.isRunning {
            try? startEngineIfNeeded()
        }
        if auditionDefinition?.id != definition.id {
            guard let sfURL = CoreSoundFont.resolveURL(identifier: definition.sourceIdentifier) else { return }
            do {
                try auditionSampler.loadSoundBankInstrument(at: sfURL, program: definition.program,
                                                             bankMSB: definition.bankMSB, bankLSB: definition.bankLSB)
                auditionDefinition = definition
            } catch {
                return
            }
        }
        guard auditionDefinition?.id == definition.id else { return }
        let ch = definition.defaultMidiChannel & 15
        auditionSampler.sendMIDIEvent(0x90 | ch, data1: note, data2: max(1, velocity))
        auditionHeldNotes.insert(note)
    }

    public func auditionOff(note: UInt8 = 60) {
        guard auditionHeldNotes.remove(note) != nil else { return }
        if auditionDefinition?.sourceType == .surge { surgeAudition?.noteOff(note); return }
        let ch = (auditionDefinition?.defaultMidiChannel ?? 0) & 15
        auditionSampler.sendMIDIEvent(0x80 | ch, data1: note, data2: 0)
    }

    public func auditionTrigger(definition: InstrumentDefinition, note: UInt8? = nil, velocity: UInt8 = 100, duration: Double = 0.45) {
        let triggerNote: UInt8
        if let note {
            triggerNote = note
        } else {
            triggerNote = definition.isDrumKit ? 36 : 60
        }
        auditionOn(definition: definition, note: triggerNote, velocity: velocity)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.auditionOff(note: triggerNote)
        }
    }

    public func auditionAllOff() {
        if auditionDefinition?.sourceType == .surge { surgeAudition?.stop(); auditionHeldNotes.removeAll(); return }
        for n in auditionHeldNotes {
            let ch = (auditionDefinition?.defaultMidiChannel ?? 0) & 15
            auditionSampler.sendMIDIEvent(0x80 | ch, data1: n, data2: 0)
        }
        auditionHeldNotes.removeAll()
    }

    public func applyChannelState(song: SongModel) {
        let solo = song.channelSolo.contains(true)
        for ch in 0..<SongModel.channelCount {
            let audible = song.channelEnabled[ch] && !song.channelMute[ch] && (!solo || song.channelSolo[ch])
            channelMixers[ch].outputVolume = audible ? Float(song.channelVolume[ch]) : 0
            channelMixers[ch].pan = Float(song.channelPan[ch])
        }
        for (key, node) in voices {
            if let inst = song.instruments.first(where: { $0.id == key.instrumentID }) {
                node.sendController(7, withValue: UInt8(max(0, min(127, Int(inst.volume * 127)))), onChannel: UInt8(inst.midiChannel & 15))
                node.sendController(10, withValue: UInt8(max(0, min(127, Int((inst.pan + 1) * 63.5)))), onChannel: UInt8(inst.midiChannel & 15))
            }
        }
    }

    var playbackBeat: Double { sequencer.currentPositionInBeats }
    func setPlaybackTempo(_ bpm: Double) { sequencer.rate = Float(max(20, bpm) / sequenceTempo) }

    private func makeSurgeVoice(_ inst: InstrumentModel) throws -> SurgeVoiceNode {
        guard let path = inst.surgePatchPath, let patch = SurgePresetCatalog.patchURL(relativePath: path),
              let voice = SurgeVoiceNode(patchURL: patch) else {
            throw playbackError("Surge XT-preset saknas för \(inst.name).")
        }
        return voice
    }

    private func removeSurgeVoice(_ key: PlaybackTimeline.Voice) {
        guard let voice = surgeVoices.removeValue(forKey: key) else { return }
        voice.stop()
        engine.disconnectNodeOutput(voice.node)
        engine.detach(voice.node)
        voiceModels.removeValue(forKey: key)
    }

    func preparePlayback(song: SongModel, timeline: PlaybackTimeline) throws {
        stopPlayback()

        // Preview keeps the hardware graph running before Play. Rebuild transport
        // while rendering is stopped so newly attached sequencer voices become part
        // of the render graph. AVAudioSequencer remains the native note clock.
        if engine.isRunning {
            removeWaveformTaps()
            engine.stop()
            isRunning = false
        }

        for track in sequencer.tracks.reversed() { sequencer.removeTrack(track) }
        tracks.removeAll(); transportTrack = nil; sequenceNotes = []; sequenceFades = []
        if hasTempo {
            sequencer.tempoTrack.clearEvents(in: AVBeatRange(start: 0, length: AVMusicTimeStampEndOfTrack))
        }
        let required = Set(timeline.notes.map(\.voice) + timeline.fades.map(\.voice))
        for key in Array(voices.keys) where !required.contains(key) {
            tracks[key]?.destinationAudioUnit = nil
            if let node = voices.removeValue(forKey: key) {
                silence(node)
                engine.disconnectNodeOutput(node)
                engine.detach(node)
            }
            voiceModels.removeValue(forKey: key)
        }
        sequenceTempo = max(20, song.bpm)
        sequencer.tempoTrack.addEvent(AVExtendedTempoEvent(tempo: sequenceTempo), at: 0)
        hasTempo = true
        sequencer.rate = 1
        try updatePlayback(song: song, timeline: timeline)
        if tracks.isEmpty {
            let track = sequencer.createAndAppendTrack()
            track.lengthInBeats = timeline.length
            transportTrack = track
        }
        sequencer.prepareToPlay()
        try startEngineIfNeeded()

        // AVMusicTrack destinations assigned while the hardware graph was stopped
        // can remain clocked but silent. Bind every destination once more against
        // the now-running graph, ensure the soundbank is loaded into the active AU,
        // then let Core Audio prepare the final routes.
        for (key, track) in tracks {
            guard let node = voices[key] else {
                throw playbackError("Ljudnod saknas efter motorstart för kanal \(key.channel + 1).")
            }
            track.destinationAudioUnit = node
            if let inst = song.instruments.first(where: { $0.id == key.instrumentID }) {
                try loadInstrument(inst, into: node)
                configureInstrument(node, from: inst)
            }
        }
        sequencer.prepareToPlay()
    }

    func updatePlayback(song: SongModel, timeline: PlaybackTimeline) throws {
        let required = Set(timeline.notes.map(\.voice))
        let surgeRequired = Set(required.filter { key in
            song.instruments.first(where: { $0.id == key.instrumentID })?.kind == .surge
        })
        let midiRequired = required.subtracting(surgeRequired)
        for key in Array(surgeVoices.keys) where !surgeRequired.contains(key) { removeSurgeVoice(key) }
        for key in surgeRequired {
            guard let inst = song.instruments.first(where: { $0.id == key.instrumentID }) else {
                throw playbackError("Instrument \(key.instrumentID) saknas för kanal \(key.channel + 1).")
            }
            if surgeVoices[key] == nil || !sameSound(voiceModels[key], inst) {
                removeSurgeVoice(key)
                let voice = try makeSurgeVoice(inst)
                engine.attach(voice.node)
                engine.connect(voice.node, to: channelMixers[key.channel], format: nil)
                surgeVoices[key] = voice
                voiceModels[key] = inst
            }
            guard let voice = surgeVoices[key] else { continue }
            voice.gain = Float(inst.volume)
            voice.schedule(notes: timeline.notes.filter { $0.voice == key },
                           fades: timeline.fades.filter { $0.voice == key },
                           from: sequencer.currentPositionInBeats, bpm: song.bpm)
            if sequencer.isPlaying { voice.activate() }
        }
        for key in Array(voices.keys) where !midiRequired.contains(key) {
            tracks[key]?.destinationAudioUnit = nil
            if let node = voices.removeValue(forKey: key) {
                silence(node); engine.disconnectNodeOutput(node); engine.detach(node)
            }
            voiceModels.removeValue(forKey: key)
        }
        let changedVoices = midiRequired.filter { key in
            guard let inst = song.instruments.first(where: { $0.id == key.instrumentID }) else { return false }
            return voices[key] == nil || !sameSound(voiceModels[key], inst)
        }
        // Om bara CoreSoundFont ändrades på en befintlig sampler kan vi ladda om den in-place utan att stoppa grafen!
        var structurallyChangedVoices: [PlaybackTimeline.Voice] = []
        for key in changedVoices {
            guard let inst = song.instruments.first(where: { $0.id == key.instrumentID }) else { continue }
            if inst.kind == .coreSoundFont, let existingSampler = voices[key] as? AVAudioUnitSampler {
                do {
                    try loadInstrument(inst, into: existingSampler)
                    configureInstrument(existingSampler, from: inst)
                    voiceModels[key] = inst
                    continue
                } catch {
                    // Vid eventuellt fel gör vi strukturell ombyggnad
                }
            }
            structurallyChangedVoices.append(key)
        }

        let wasPlaying = sequencer.isPlaying
        let beat = sequencer.currentPositionInBeats
        if !structurallyChangedVoices.isEmpty && wasPlaying { sequencer.stop() }
        for key in structurallyChangedVoices {
            guard let inst = song.instruments.first(where: { $0.id == key.instrumentID }) else {
                throw playbackError("Instrument \(key.instrumentID) saknas för kanal \(key.channel + 1).")
            }
            let track = tracks[key]
            track?.destinationAudioUnit = nil
            if let old = voices[key] {
                silence(old)
                engine.disconnectNodeOutput(old)
                engine.detach(old)
            }
            let node = try makeInstrument(inst)
            engine.attach(node)
            engine.connect(node, to: channelMixers[key.channel], format: nil)
            try loadInstrument(inst, into: node)
            configureInstrument(node, from: inst)
            voices[key] = node
            voiceModels[key] = inst
            track?.destinationAudioUnit = node
        }
        for key in midiRequired where tracks[key] == nil {
            guard let node = voices[key] else {
                throw playbackError("Ingen ljudnod finns för kanal \(key.channel + 1).")
            }
            let track = sequencer.createAndAppendTrack()
            track.destinationAudioUnit = node
            tracks[key] = track
        }
        if sequenceNotes != timeline.notes || sequenceFades != timeline.fades || sequenceLength != timeline.length {
            let populated = Set(sequenceNotes.map(\.voice) + sequenceFades.map(\.voice))
            for (key, track) in tracks {
                // Core Audio returns paramErr when clearing a never-populated track.
                if populated.contains(key) {
                    track.clearEvents(in: AVBeatRange(start: 0, length: AVMusicTimeStampEndOfTrack))
                }
                track.lengthInBeats = timeline.length
            }
            for note in timeline.notes where midiRequired.contains(note.voice) {
                guard let track = tracks[note.voice] else {
                    throw playbackError("Sekvensspår saknas för kanal \(note.voice.channel + 1).")
                }
                track.addEvent(AVMIDINoteEvent(channel: UInt32(note.midiChannel), key: UInt32(note.key),
                                              velocity: UInt32(note.velocity), duration: note.duration), at: note.beat)
            }
            for fade in timeline.fades where midiRequired.contains(fade.voice) {
                guard let track = tracks[fade.voice] else { continue }
                track.addEvent(AVMIDIControlChangeEvent(channel: UInt32(fade.midiChannel),
                                                        messageType: .allNotesOff, value: 0), at: fade.beat)
            }
            sequenceNotes = timeline.notes
            sequenceFades = timeline.fades
        }
        if wasPlaying && sequenceSteps != timeline.stepsPerBeat {
            sequencer.currentPositionInBeats = beat * sequenceSteps / timeline.stepsPerBeat
        }
        sequenceSteps = timeline.stepsPerBeat; sequenceLength = timeline.length
        applyChannelState(song: song)
        if wasPlaying && !structurallyChangedVoices.isEmpty { try sequencer.start() }
    }

    func startPlayback(at beat: Double) throws {
        try startEngineIfNeeded()
        for voice in surgeVoices.values {
            voice.schedule(notes: [], fades: [], from: beat, bpm: sequenceTempo)
        }
        // Reinstall events after resetting their audio-frame origin. The source
        // nodes render them inside Core Audio, while AVAudioSequencer remains
        // the transport clock observed by the UI.
        for (key, voice) in surgeVoices {
            voice.schedule(notes: sequenceNotes.filter { $0.voice == key },
                           fades: sequenceFades.filter { $0.voice == key }, from: beat, bpm: sequenceTempo)
            voice.activate()
        }
        sequencer.currentPositionInBeats = beat
        try sequencer.start()
        guard sequencer.isPlaying else {
            throw playbackError("Sequencern startade inte.", code: 5)
        }
        statusText = "Spelar \(sequenceNotes.count) noter via \(tracks.count + surgeVoices.count) ljudspår"
    }
    func stopPlayback() {
        sequencer.stop()
        for node in voices.values { silence(node) }
        for voice in surgeVoices.values { voice.stop() }
    }

    /// Uses the same grid events as live playback; each render block ends at the
    /// next event boundary, rather than delaying notes to 4096-frame boundaries.
    public func renderToWAV(song: SongModel, url: URL) throws {
        let timeline = PlaybackTimeline(song: song)
        let rate = 44_100.0
        let offline = AVAudioEngine()
        var nodes: [PlaybackTimeline.Voice: AVAudioUnitMIDIInstrument] = [:]
        let solo = song.channelSolo.contains(true)
        for key in Set(timeline.notes.map(\.voice)) {
            guard let inst = song.instruments.first(where: { $0.id == key.instrumentID }) else { continue }
            let node = try makeInstrument(inst)
            let mixer = AVAudioMixerNode()
            offline.attach(node); offline.attach(mixer)
            offline.connect(node, to: mixer, format: nil)
            offline.connect(mixer, to: offline.mainMixerNode, format: nil)
            let ch = key.channel
            mixer.outputVolume = song.channelEnabled[ch] && !song.channelMute[ch] && (!solo || song.channelSolo[ch]) ? Float(song.channelVolume[ch]) : 0
            mixer.pan = Float(song.channelPan[ch])
            node.sendController(7, withValue: UInt8(max(0, min(127, Int(inst.volume * 127)))), onChannel: UInt8(inst.midiChannel & 15))
            node.sendController(10, withValue: UInt8(max(0, min(127, Int((inst.pan + 1) * 63.5)))), onChannel: UInt8(inst.midiChannel & 15))
            nodes[key] = node
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        try offline.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try offline.start()
        defer { offline.stop(); offline.disableManualRenderingMode() }
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
        struct Event {
            enum Kind { case note(PlaybackTimeline.Note, Bool), fade(PlaybackTimeline.Fade) }
            let frame: Int64
            let kind: Kind
        }
        func frame(_ beat: Double) -> Int64 { Int64((beat * 60 / max(20, song.bpm) * rate).rounded()) }
        var events: [Event] = []
        for note in timeline.notes {
            events.append(Event(frame: frame(note.beat), kind: .note(note, true)))
            events.append(Event(frame: frame(note.beat + note.duration), kind: .note(note, false)))
        }
        for fade in timeline.fades {
            events.append(Event(frame: frame(fade.beat), kind: .fade(fade)))
        }
        events.sort {
            if $0.frame != $1.frame { return $0.frame < $1.frame }
            func rank(_ kind: Event.Kind) -> Int {
                switch kind {
                case .fade: return 0
                case let .note(_, on): return on ? 2 : 1
                }
            }
            return rank($0.kind) < rank($1.kind)
        }
        let end = frame(timeline.length) + Int64(rate) // release tail
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var current: Int64 = 0; var index = 0; var retries = 0
        while current < end {
            while index < events.count && events[index].frame <= current {
                let event = events[index]
                switch event.kind {
                case let .note(note, on):
                    nodes[note.voice]?.sendMIDIEvent((on ? 0x90 : 0x80) | note.midiChannel,
                                                      data1: note.key, data2: on ? note.velocity : 0)
                case let .fade(fade):
                    nodes[fade.voice]?.sendMIDIEvent(0xB0 | fade.midiChannel, data1: 123, data2: 0)
                }
                index += 1
            }
            let next = index < events.count ? events[index].frame : end
            let count = AVAudioFrameCount(min(4096, min(end, next) - current))
            let result = try offline.renderOffline(count, to: buffer)
            if result == .success {
                try file.write(from: buffer); current += Int64(buffer.frameLength); retries = 0
            } else {
                retries += 1
                if retries > 20 || result == .error {
                    throw NSError(domain: "RetroTrakk", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ljudmotorn kunde inte rendera nästa ljudblock."])
                }
            }
        }
    }
}

/// Dedicated lightweight observable model for oscilloscope waveforms.
/// Only observed by ChannelOscilloscopeView, isolating 30 fps redraws
/// from the rest of the application.
public final class WaveformManager: ObservableObject {
    public static let shared = WaveformManager()

    @Published public var waveforms: [[Float]] = Array(repeating: Array(repeating: 0, count: 32), count: SongModel.channelCount)
    @Published public private(set) var signalPeak: Float = 0

    private var rawWaveforms: [[Float]] = Array(repeating: Array(repeating: 0, count: 32), count: SongModel.channelCount)
    private let lock = NSLock()
    private var timer: Timer?
    private var activeFrames = 0

    private init() {}

    public func update(channel: Int, buffer: AVAudioPCMBuffer) {
        guard channel >= 0, channel < SongModel.channelCount,
              let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let data = channelData[0]
        var samples = [Float](repeating: 0, count: 32)
        let step = max(1, frames / 32)
        var maxAmp: Float = 0
        for i in 0..<32 {
            let idx = min(frames - 1, i * step)
            let val = data[idx]
            samples[i] = val
            let absV = abs(val)
            if absV > maxAmp { maxAmp = absV }
        }
        lock.lock()
        rawWaveforms[channel] = samples
        if maxAmp > 0.005 { activeFrames = 20 }
        lock.unlock()
    }

    public func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stopTimer() {
        timer?.invalidate()
        timer = nil
        lock.lock()
        rawWaveforms = Array(repeating: Array(repeating: 0, count: 32), count: SongModel.channelCount)
        lock.unlock()
        waveforms = Array(repeating: Array(repeating: 0, count: 32), count: SongModel.channelCount)
        signalPeak = 0
    }

    private func tick() {
        lock.lock()
        let current = rawWaveforms
        var hasSignal = false
        for ch in 0..<rawWaveforms.count {
            for i in 0..<rawWaveforms[ch].count {
                rawWaveforms[ch][i] *= 0.82
                if abs(rawWaveforms[ch][i]) < 0.001 {
                    rawWaveforms[ch][i] = 0
                } else {
                    hasSignal = true
                }
            }
        }
        if activeFrames > 0 {
            activeFrames -= 1
            hasSignal = true
        }
        lock.unlock()

        signalPeak = current.flatMap { $0 }.reduce(Float(0)) { max($0, abs($1)) }
        if hasSignal || activeFrames > 0 {
            waveforms = current
        }
    }
}

// MARK: - CoreSoundFont Resolver

public enum CoreSoundFont {
    public static let defaultFileName = "MuseScore_General.sf2"

    public static func resolveURL(identifier: String? = nil) -> URL? {
        let raw = identifier ?? defaultFileName
        let name = (raw as NSString).deletingPathExtension
        let ext = (raw as NSString).pathExtension.isEmpty ? "sf2" : (raw as NSString).pathExtension

        // 1. App Bundle resources
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "SoundFonts") {
            return url
        }
        // 2. Framework/Class bundle resources
        let bundle = Bundle(for: RetroTrakkAudioEngine.self)
        if let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "SoundFonts") {
            return url
        }
        // 3. Utvecklings-, installations- och testsökvägar
        let candidates = [
            "/Applications/RetroTrakk.app/Contents/Resources/\(name).\(ext)",
            "RetroTrakk/RetroTrakk/Resources/SoundFonts/\(name).\(ext)",
            "RetroTrakk/Resources/SoundFonts/\(name).\(ext)",
            "Resources/SoundFonts/\(name).\(ext)",
            "/tmp/\(name).\(ext)",
            "/tmp/usr/share/sounds/sf2/\(name).\(ext)",
            "/tmp/usr/share/sounds/sf2/MuseScore_General_Full.sf2"
        ]
        for path in candidates {
            let fileURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }
        return nil
    }
}
