// RetroTrakk — TrackerEngine.swift
// Uppspelning, cursor, step input och live-inspelning (kvantiserad).

import Foundation
import SwiftUI
import Combine
import CoreVideo

extension Notification.Name {
    static let retroFocusTracker = Notification.Name("retroFocusTracker")
}

public enum ComputerKeyboardPiano {
    public static func midiNote(for key: String, octave: Int) -> UInt8? {
        let base = 12 * (max(0, min(8, octave)) + 1)
        let lower: [String: Int] = ["z": 0, "s": 1, "x": 2, "d": 3, "c": 4, "v": 5, "g": 6, "h": 7,
                                    "b": 8, "n": 9, "j": 10, "m": 11, ",": 12]
        let upper: [String: Int] = ["q": 12, "2": 13, "w": 14, "3": 15, "e": 16, "r": 17, "5": 18,
                                    "t": 19, "6": 20, "y": 21, "7": 22, "u": 23, "i": 24]
        if let semitones = lower[key] ?? upper[key] {
            return UInt8(max(0, min(127, base + semitones)))
        }
        return nil
    }
}

/// En punkt i tracker-griden (rad, kanal). Används för musmarkering.
public struct SelPoint: Hashable, Sendable {
    public var row: Int
    public var channel: Int
    public init(_ row: Int, _ channel: Int) { self.row = row; self.channel = channel }
}

/// Lättviktsinspelad händelse för frikopplad live-inspelning (Del 2).
/// Ljudet hörs omedelbart via preview, cellen buffras här och tidslinjen
/// kompileras först vid loop/stop — aldrig synkront per anslag.
public struct RecordedEvent: Sendable {
    public let order: Int
    public let row: Int
    public let channel: Int
    public let cell: TrackerCell
    public init(order: Int, row: Int, channel: Int, cell: TrackerCell) {
        self.order = order; self.row = row; self.channel = channel; self.cell = cell
    }
}

/// Högfrekvent uppspelningsklocka (60/120 Hz). Endast spelhuvud + beat-LED
/// observerar denna — ContentView, Sidebars och TrackerCellView gör det INTE.
/// Detta bryter kaskadinvalideringen där varje sextondel tvingade hela
/// appens vyträd att köras om.
public final class PlaybackClock: ObservableObject {
    /// Rå beatposition — medvetet INTE @Published. Ingen vy läser den och den
    /// ändras varje display-tick; publicering här skulle tvinga alla
    /// clock-observatörer att ritas om i 120 Hz helt i onödan.
    public var currentBeat: Double = 0
    @Published public var currentRow: Int = 0
    @Published public var orderPos: Int = 0
    @Published public var isPlaying: Bool = false
    @Published public var beatPhase: Int = 0

    public init() {}

    /// Tilldela endast vid faktisk ändring för att undvika onödiga publishes i 120 Hz.
    public func sync(beat: Double, row: Int, order: Int, playing: Bool, phase: Int) {
        if currentBeat != beat { currentBeat = beat }
        if currentRow != row { currentRow = row }
        if orderPos != order { orderPos = order }
        if isPlaying != playing { isPlaying = playing }
        if beatPhase != phase { beatPhase = phase }
    }
}

public final class TrackerEngine: ObservableObject {
    @Published public var song = SongModel() { didSet { songChanged(from: oldValue) } }
    // MARK: - Tillståndsisolering (Del 3)
    // Högfrekvent transporttillstånd bor i `clock` och observeras ENDAST av
    // spelhuvud-overlay + beat-LED. Dessa speglade accessorer behåller det
    // publika API:t (tester + logik läser/skriver tracker.isPlaying etc) men
    // publicerar via clock — aldrig via TrackerEngine.objectWillChange.
    // Därmed invalideras inte ContentView/Sidebars/Tracker-celler per rad.
    public let clock = PlaybackClock()
    public var orderPos: Int {
        get { clock.orderPos }
        set { if clock.orderPos != newValue { clock.orderPos = newValue } }
    }
    public var currentRow: Int {
        get { clock.currentRow }
        set { if clock.currentRow != newValue { clock.currentRow = newValue } }
    }
    public var isPlaying: Bool {
        get { clock.isPlaying }
        set { if clock.isPlaying != newValue { clock.isPlaying = newValue } }
    }
    public var beatPhase: Int {
        get { clock.beatPhase }
        set { if clock.beatPhase != newValue { clock.beatPhase = newValue } }
    }
    public var currentBeat: Double {
        get { clock.currentBeat }
        set { if clock.currentBeat != newValue { clock.currentBeat = newValue } }
    }
    /// Sant under pågående live-inspelning (transport rullar + Record på).
    /// Medan denna är sann är automatisk sequencer-ombyggnad AVSTÄNGD (Del 2).
    public var isLiveRecordingActive: Bool { isRecording && isPlaying }
    @Published public var isRecording: Bool = false {
        didSet {
            if oldValue && !isRecording { refreshDeferredRecordingPlayback() }
        }
    }
    @Published public var editMode: Bool = false
    @Published public var cursorRow: Int = 0
    @Published public var cursorChannel: Int = 0 {
        didSet {
            if cursorChannel != oldValue {
                syncCurrentDefinitionWithChannel(cursorChannel)
            }
        }
    }
    @Published public var stepSize: Int = 1
    @Published public var octave: Int = 4
    @Published public var quantize: Bool = true
    /// Musmarkering: ankare + aktivt hörn. nil = ingen markering.
    @Published public var selAnchor: SelPoint? = nil
    @Published public var selCursor: SelPoint? = nil
    /// Urklipp för copy/paste (rader x kanaler med celler).
    @Published public var clipboard: [[TrackerCell]]? = nil
    /// Sant medan en mus-drag-markering pågår.
    public var dragActive: Bool = false

    // MARK: - Browser Preview & Current Instrument
    @Published public var currentDefinition: InstrumentDefinition? = nil
    @Published public var previewDefinition: InstrumentDefinition?
    @Published public var favoriteIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "RetroTrakkFavorites") ?? [])
    @Published public var recentIDs: [String] = UserDefaults.standard.stringArray(forKey: "RetroTrakkRecent") ?? []
    @Published public var currentProjectURL: URL? = nil

    public var projectTitle: String {
        if let url = currentProjectURL {
            let name = url.deletingPathExtension().lastPathComponent
            return name.isEmpty ? song.title : name
        }
        return song.title.isEmpty ? "Namnlöst projekt" : song.title
    }

    public var audio: RetroTrakkAudioEngine?
    public var midi: MIDIEngine?

    private var playheadTimer: Timer?
    private var playheadDisplayLink: CVDisplayLink?
    private var playbackTimeline: PlaybackTimeline?
    /// A live key is always released on key-up. The generation also makes the
    /// short safety release harmless when the same MIDI key is retriggered.
    private var activeNotes: [UInt8: (instrumentID: Int, generation: Int)] = [:]
    private var liveNoteGeneration = 0
    /// Live notes are previewed immediately. Rewriting AVMusicTracks for every
    /// key press can stall the main thread, so one rebuild is deferred until
    /// Record is switched off (or until the next Play after Stop).
    private var recordingPlaybackNeedsRefresh = false
    private var deferredRecordingEventCount = 0
    /// Frikopplad live-inspelningsbuffer (Del 2): celler skrivs direkt till
    /// mönstret utan tidslinje-rebuild; tidslinjen kompileras samlat vid
    /// loop/stop/Record-av i bakgrunden.
    private var liveRecordBuffer: [RecordedEvent] = []
    private let playbackRebuildQueue = DispatchQueue(label: "RetroTrakk.playbackRebuild", qos: .userInitiated)

    public init() {
        syncCurrentDefinitionWithChannel(0)
    }

    // MARK: - Timing

    public var secPerRow: Double {
        let rowsPerBeat = max(1, Double(song.stepsPerBeat))
        return 60.0 / max(20, song.bpm) / rowsPerBeat
    }

    public var currentPatternID: Int? {
        guard orderPos >= 0, orderPos < song.orders.count else { return nil }
        return song.orders[orderPos]
    }

    // MARK: - Transport

    public func togglePlay(fromStart: Bool = true) {
        isPlaying ? stop() : play(fromStart: fromStart)
    }

    public func play(fromStart: Bool = true) {
        guard !isPlaying, let audio else { return }
        let timeline = PlaybackTimeline(song: song)
        guard timeline.length > 0 else { return }
        // Start from row 0 in current pattern order when requested or by default
        var startOrder = max(0, min(song.orders.count - 1, orderPos))
        let patternRows = song.pattern(id: song.orders[startOrder])?.rowCount ?? 64
        var startRow = fromStart ? 0 : cursorRow
        if startRow >= patternRows {
            startRow = 0
        }

        var start = timeline.beat(order: startOrder, row: startRow)
        if start >= timeline.length {
            startOrder = 0
            startRow = 0
            start = 0
        }

        do {
            audio.allNotesOff()
            try audio.preparePlayback(song: song, timeline: timeline)
            try audio.startPlayback(at: start)
            playbackTimeline = timeline
            liveRecordBuffer.removeAll()
            recordingPlaybackNeedsRefresh = false
            deferredRecordingEventCount = 0
            clock.sync(beat: start, row: startRow, order: startOrder, playing: true, phase: startRow % max(1, song.stepsPerBeat))
            cursorRow = startRow
            updatePlayhead()
            startPlayheadUpdates()
        } catch {
            audio.statusText = "Uppspelning misslyckades: \(error.localizedDescription)"
            stop()
        }
    }

    public func stop() {
        stopPlayheadUpdates()
        audio?.stopPlayback()
        clock.sync(beat: clock.currentBeat, row: cursorRow, order: clock.orderPos, playing: false, phase: clock.beatPhase)
        textureActive = false
        midiHeld.removeAll()
        activeNotes.removeAll()
        // Stoppad transport bygger ändå ny tidslinje vid nästa Play, så ingen
        // async rebuild behövs här — bara rensa bufferten.
        liveRecordBuffer.removeAll()
        recordingPlaybackNeedsRefresh = false
        deferredRecordingEventCount = 0
        audio?.allNotesOff()
        // När uppspelningen stoppas ligger samma rad kvar som edit cursor row
        currentRow = cursorRow
    }

    // MARK: - Display-synkroniserad playhead (Del 1/Flaskhals 5)

    private func startPlayheadUpdates() {
        stopPlayheadUpdates()
        // Primärt: CVDisplayLink synkad mot skärmens VBLANK (60/120 Hz ProMotion).
        // Fallback: 60 Hz RunLoop.main-timer (testmiljö/headless).
        if startPlayheadDisplayLink() { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updatePlayhead()
        }
        RunLoop.main.add(timer, forMode: .common)
        playheadTimer = timer
    }

    private func stopPlayheadUpdates() {
        playheadTimer?.invalidate()
        playheadTimer = nil
        if let link = playheadDisplayLink {
            CVDisplayLinkStop(link)
            playheadDisplayLink = nil
        }
    }

    private func startPlayheadDisplayLink() -> Bool {
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess,
              let created = link else { return false }
        let callback: CVDisplayLinkOutputCallback = { (_, _, _, _, _, userInfo) -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let engine = Unmanaged<TrackerEngine>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { [weak engine] in engine?.updatePlayhead() }
            return kCVReturnSuccess
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard CVDisplayLinkSetOutputCallback(created, callback, selfPtr) == kCVReturnSuccess,
              CVDisplayLinkStart(created) == kCVReturnSuccess else { return false }
        playheadDisplayLink = created
        return true
    }

    private func updatePlayhead() {
        guard isPlaying, let timeline = playbackTimeline, let audio else { return }
        let beat = audio.playbackBeat
        guard let position = timeline.position(at: beat) else {
            loopPlayback()
            return
        }
        let phase = position.row % max(1, song.stepsPerBeat)
        // Enda writers till clock under playback — granulärt, ingen TrackerEngine-publish.
        clock.sync(beat: beat, row: position.row, order: position.order, playing: true, phase: phase)
    }

    private func loopPlayback() {
        guard isPlaying, let audio, playbackTimeline != nil else { return }
        // Synkronisering vid loop (Del 2): inspelade noter hördes redan via
        // preview; kompilera samlad tidslinje i bakgrunden och starta om.
        if recordingPlaybackNeedsRefresh {
            let capturedSong = song
            let capturedCount = deferredRecordingEventCount
            playbackRebuildQueue.async { [weak self] in
                let fresh = PlaybackTimeline(song: capturedSong)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isPlaying else { return }
                    do {
                        try audio.updatePlayback(song: capturedSong, timeline: fresh)
                        self.playbackTimeline = fresh
                        self.recordingPlaybackNeedsRefresh = false
                        self.deferredRecordingEventCount = 0
                        self.liveRecordBuffer.removeAll()
                        self.clock.sync(beat: 0, row: 0, order: 0, playing: true, phase: 0)
                        self.cursorRow = 0
                        try audio.startPlayback(at: 0)
                    } catch {
                        self.stop()
                    }
                    if capturedCount > 0 {
                        CrashDiagnostics.shared.record("Live recording: loop-compiled \(capturedCount) deferred events into timeline (\(fresh.notes.count) notes).")
                    }
                }
            }
            return
        }
        do {
            clock.sync(beat: 0, row: 0, order: 0, playing: true, phase: 0)
            cursorRow = 0
            try audio.startPlayback(at: 0)
        } catch {
            stop()
        }
    }

    private func songChanged(from old: SongModel) {
        let needsChannelUpdate = old.channelVolume != song.channelVolume || old.channelPan != song.channelPan ||
              old.channelMute != song.channelMute || old.channelSolo != song.channelSolo ||
              old.channelEnabled != song.channelEnabled
        if needsChannelUpdate { audio?.applyChannelState(song: song) }
        guard isPlaying, let audio else { return }
        if old.bpm != song.bpm { audio.setPlaybackTempo(song.bpm) }
        let needsPlaybackUpdate = old.patterns != song.patterns || old.orders != song.orders ||
              old.stepsPerBeat != song.stepsPerBeat || old.instruments != song.instruments ||
              old.channelInstruments != song.channelInstruments
        guard needsPlaybackUpdate else { return }
        // Frikopplad live-inspelning (Del 2/Flaskhals 1): STÄNG AV automatisk
        // sequencer-ombyggnad medan transporten rullar. Sekvensern spelar det
        // som fanns vid Play; nya noter hörs redan via preview (0 ms latency).
        if isLiveRecordingActive {
            recordingPlaybackNeedsRefresh = true
            deferredRecordingEventCount += 1
            if deferredRecordingEventCount == 1 {
                CrashDiagnostics.shared.record("Live recording: deferred playback rebuild to prevent audio/UI stalls.")
            }
            return
        }
        rebuildPlayback(audio: audio)
    }

    private func refreshDeferredRecordingPlayback() {
        guard recordingPlaybackNeedsRefresh else { return }
        recordingPlaybackNeedsRefresh = false
        let pendingCount = deferredRecordingEventCount
        deferredRecordingEventCount = 0
        guard isPlaying, let audio else {
            liveRecordBuffer.removeAll()
            return
        }
        // Samlad ombyggnad asynkront: kompilera PlaybackTimeline i bakgrunden
        // (ren struct, ingen Core Audio), applicera sedan på main.
        let capturedSong = song
        playbackRebuildQueue.async { [weak self] in
            let fresh = PlaybackTimeline(song: capturedSong)
            let started = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                do {
                    try audio.updatePlayback(song: capturedSong, timeline: fresh)
                    self.playbackTimeline = fresh
                    self.liveRecordBuffer.removeAll()
                    let elapsed = ProcessInfo.processInfo.systemUptime - started
                    if elapsed > 0.05 || pendingCount > 16 {
                        CrashDiagnostics.shared.record(String(format: "Live recording: async rebuild %d events, %d notes in %.0f ms.", pendingCount, fresh.notes.count, elapsed * 1_000))
                    }
                } catch {
                    audio.statusText = "Kunde inte uppdatera uppspelning: \(error.localizedDescription)"
                    self.stop()
                }
            }
        }
    }

    private func rebuildPlayback(audio: RetroTrakkAudioEngine) {
        let timeline = PlaybackTimeline(song: song)
        let started = ProcessInfo.processInfo.systemUptime
        do {
            try audio.updatePlayback(song: song, timeline: timeline)
            playbackTimeline = timeline
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            if elapsed > 0.05 {
                CrashDiagnostics.shared.record(String(format: "Slow playback rebuild: %.0f ms, %d notes, %d releases.", elapsed * 1_000, timeline.notes.count, timeline.fades.count))
            }
        } catch {
            audio.statusText = "Kunde inte uppdatera uppspelning: \(error.localizedDescription)"
            stop()
        }
    }

    /// Asynkron variant för tunga ombyggnader (många instrument/spår).
    /// Tidslinjen kompileras off-main, appliceras sedan atomiskt på main.
    private func rebuildPlaybackAsync(audio: RetroTrakkAudioEngine) {
        let capturedSong = song
        playbackRebuildQueue.async { [weak self] in
            let timeline = PlaybackTimeline(song: capturedSong)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                do {
                    try audio.updatePlayback(song: capturedSong, timeline: timeline)
                    self.playbackTimeline = timeline
                } catch {
                    audio.statusText = "Kunde inte uppdatera uppspelning: \(error.localizedDescription)"
                    self.stop()
                }
            }
        }
    }

    // MARK: - Redigering

    /// Sant endast när inmatning faktiskt ska SKRIVA data.
    /// Under pågående uppspelning utan Record blir tangentbord/MIDI bara förhandslyssning.
    public func shouldWriteInput() -> Bool {
        editMode && (isRecording || !isPlaying)
    }

    public func setCell(row: Int, channel: Int, cell: TrackerCell) {
        song.setCell(orderPos: orderPos, row: row, channel: channel, cell: cell)
    }

    public func getCell(row: Int, channel: Int) -> TrackerCell {
        song.getCell(orderPos: orderPos, row: row, channel: channel)
    }

    /// Skriv in en not på cursor (Mac-tangentbordet).
    /// Skriver bara när shouldWriteInput() — annars enbart förhandslyssning.
    /// Nästan samtidiga tryck (< halva radtiden) grupperas som ACKORD på samma
    /// rad i lediga kanaler: tryck-tajming läcker aldrig in i griden.
    public func stepInput(note: UInt8, velocity: UInt8 = 100) {
        if isRecording && isPlaying {
            recordLiveNoteOn(note: note, velocity: velocity)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.recordLiveNoteOff(note: note)
            }
            return
        }
        guard shouldWriteInput() else {
            preview(note: note, velocity: velocity)
            return
        }
        guard let _ = instrumentFor(channel: cursorChannel) else {
            audio?.statusText = "Välj ett instrument i sidopanelen för kanal \(cursorChannel + 1) först."
            return
        }
        let now = Date()
        let dt = now.timeIntervalSince(lastStepTime)
        // Dublettfilter: samma not inom 10 ms = studs — svälj (tona bara)
        if let ln = lastStepNote, ln == note, dt < 0.01 {
            preview(note: note, velocity: velocity)
            return
        }
        // Ackordfönster
        let window = min(0.06, secPerRow * 0.49)
        if let lp = lastStepPoint, dt < window {
            let chordInst = instNumber(forChannel: lp.channel)
            for c in (lp.channel + 1)..<SongModel.channelCount {
                if getCell(row: lp.row, channel: c).isEmpty {
                    let cell = TrackerCell(note: note, instrument: chordInst, volume: vol64(velocity))
                    setCell(row: lp.row, channel: c, cell: cell)
                    preview(note: note, velocity: velocity)
                    lastStepNote = note; lastStepTime = now
                    lastStepPoint = SelPoint(lp.row, c)
                    return
                }
            }
        }
        let writtenRow = cursorRow
        let writtenCh = cursorChannel
        let cell = TrackerCell(note: note, instrument: instNumber(forChannel: writtenCh), volume: vol64(velocity))
        setCell(row: writtenRow, channel: writtenCh, cell: cell)
        preview(note: note, velocity: velocity)
        lastStepNote = note; lastStepTime = now
        lastStepPoint = SelPoint(writtenRow, writtenCh)
        moveCursor(rows: stepSize)
    }

    // MARK: - MIDI step-entry (release-styrd texture)

    /// Nedtryckta MIDI-noter: not -> (placerad cell, preview-instrument).
    private var midiHeld: [UInt8: (SelPoint, Int)] = [:]
    private var textureActive = false
    private var writeRow = 0
    private var writeCh = 0
    // Mac step-entry: dublett + ackordfönster
    private var lastStepNote: UInt8? = nil
    private var lastStepTime = Date.distantPast
    private var lastStepPoint: SelPoint? = nil

    private func resetComputerKeyboardChord() {
        lastStepNote = nil
        lastStepTime = .distantPast
        lastStepPoint = nil
    }

    private func lastPatternRow() -> Int {
        guard let pid = currentPatternID,
              let p = song.patterns.first(where: { $0.id == pid }) else { return 63 }
        return p.rowCount - 1
    }

    private func instNumber(forChannel ch: Int) -> UInt8 {
        guard ch >= 0, ch < SongModel.channelCount,
              let iid = song.channelInstruments[ch],
              let idx = song.instruments.firstIndex(where: { $0.id == iid }) else { return 0 }
        return UInt8(idx + 1)
    }

    private func vol64(_ velocity: UInt8) -> UInt8 {
        UInt8(max(1, min(64, Int(Double(velocity) / 127.0 * 64.0))))
    }

    private func instrumentFor(channel: Int) -> InstrumentModel? {
        guard channel >= 0, channel < SongModel.channelCount,
              let iid = song.channelInstruments[channel] else { return nil }
        return song.instruments.first(where: { $0.id == iid })
    }

    /// Starta MIDI-steginmatning.
    /// Flera tangenter som trycks inom samma "ackord-anslag" (medan minst en
    /// hålls nedtryckt) läggs på SAMMA rad i påföljande lediga kanaler.
    /// Först när ALLA tangenter släppts flyttas markören framåt `stepSize` rader.
    public func midiStepOn(note: UInt8, velocity: UInt8) {
        if isRecording && isPlaying {
            recordLiveNoteOn(note: note, velocity: velocity)
            return
        }
        guard shouldWriteInput() else {
            // Edit-läge av: bara preview-ljud
            if let inst = instrumentFor(channel: cursorChannel) {
                audio?.previewOn(inst: inst, midiNote: note, velocity: velocity)
                midiHeld[note] = (SelPoint(-1, -1), inst.id)
            }
            return
        }
        guard let currentInst = instrumentFor(channel: cursorChannel) else {
            audio?.statusText = "Välj ett instrument i sidopanelen för kanal \(cursorChannel + 1) först."
            return
        }
        let previewIID = currentInst.id
        audio?.previewOn(inst: currentInst, midiNote: note, velocity: velocity)
        if midiHeld.isEmpty {
            // Nytt anslag: förankra rad och kanal från aktuell cursor
            textureActive = true
            writeRow = cursorRow
            writeCh = cursorChannel
        }
        var target: Int? = nil
        if getCell(row: writeRow, channel: writeCh).isEmpty {
            target = writeCh
        } else {
            for c in (writeCh + 1)..<SongModel.channelCount {
                if getCell(row: writeRow, channel: c).isEmpty { target = c; break }
            }
        }
        if target == nil {
            // Raden full: fortsätt på nästa step-rad inom samma anslag
            writeRow = min(lastPatternRow(), writeRow + max(1, stepSize))
            writeCh = cursorChannel
            if getCell(row: writeRow, channel: writeCh).isEmpty {
                target = writeCh
            } else {
                for c in (writeCh + 1)..<SongModel.channelCount {
                    if getCell(row: writeRow, channel: c).isEmpty { target = c; break }
                }
            }
        }
        guard let ch = target else { return }
        let chordInst = instNumber(forChannel: writeCh)
        let cell = TrackerCell(note: note, instrument: chordInst, volume: vol64(velocity))
        setCell(row: writeRow, channel: ch, cell: cell)
        midiHeld[note] = (SelPoint(writeRow, ch), previewIID)
    }

    public func midiStepOff(note: UInt8) {
        guard let (_, iid) = midiHeld.removeValue(forKey: note) else {
            // Preview-läge (skrev inget): tysta preview-noten
            if let inst = instrumentFor(channel: cursorChannel) {
                audio?.previewOff(instrumentId: inst.id, midiNote: note)
            }
            return
        }
        if iid >= 0 { audio?.previewOff(instrumentId: iid, midiNote: note) }
        // Hela anslaget släppt: flytta cursor ett steg
        if midiHeld.isEmpty && textureActive {
            textureActive = false
            cursorRow = min(lastPatternRow(), writeRow + max(1, stepSize))
            if !isPlaying { currentRow = cursorRow }
        }
    }

    public func preview(note: UInt8, velocity: UInt8 = 100) {
        previewOn(channel: cursorChannel, note: note, velocity: velocity, autoOff: true)
    }

    /// Förhandslyssning på isolerad kanal — kan aldrig kapa pattern-noter.
    public func previewOn(channel: Int, note: UInt8, velocity: UInt8 = 100, autoOff: Bool = false) {
        guard channel >= 0, channel < SongModel.channelCount,
              song.channelEnabled[channel],
              let inst = instrumentFor(channel: channel) else { return }
        audio?.previewOn(inst: inst, midiNote: note, velocity: velocity)
        if autoOff {
            let iid = inst.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.audio?.previewOff(instrumentId: iid, midiNote: note)
            }
        }
    }

    public func previewOff(instrumentId: Int, note: UInt8) {
        audio?.previewOff(instrumentId: instrumentId, midiNote: note)
    }

    public func clearCell() {
        setCell(row: cursorRow, channel: cursorChannel, cell: .empty)
        moveCursor(rows: stepSize)
    }

    public func insertNoteOff() {
        setCell(row: cursorRow, channel: cursorChannel, cell: .noteOff)
        moveCursor(rows: stepSize)
    }

    /// TAB while recording adds F08 at the quantized playhead and releases the
    /// currently held preview notes. F08 is replayed later as a channel release,
    /// allowing the selected instrument's own envelope to fade naturally.
    public func insertLiveFadeOut() {
        guard isRecording, isPlaying, let audio, let timeline = playbackTimeline,
              let position = timeline.position(at: audio.playbackBeat, nearest: quantize) else { return }
        var cell = song.getCell(orderPos: position.order, row: position.row, channel: cursorChannel)
        cell.effect = TrackerEffect.fadeOut
        cell.param = TrackerEffect.defaultFadeParameter
        song.setCell(orderPos: position.order, row: position.row, channel: cursorChannel, cell: cell)
        for (note, active) in activeNotes {
            audio.previewOff(instrumentId: active.instrumentID, midiNote: note)
        }
        activeNotes.removeAll()
        CrashDiagnostics.shared.record("Live recording: inserted F08 release at order \(position.order), row \(position.row), channel \(cursorChannel + 1).")
    }

    public func moveCursor(rows: Int = 0, channels: Int = 0) {
        guard let pid = currentPatternID,
              let pattern = song.patterns.first(where: { $0.id == pid }) else { return }
        cursorRow = max(0, min(pattern.rowCount - 1, cursorRow + rows))
        cursorChannel = max(0, min(SongModel.channelCount - 1, cursorChannel + channels))
        if !isPlaying { currentRow = cursorRow }
        if rows != 0 || channels != 0 { clearSelection() }
    }

    // MARK: - Live recording

    public func bindMIDI() {
        midi?.onNoteOn = { [weak self] note, vel in
            guard let self else { return }
            let handler = {
                if self.isRecording && self.isPlaying {
                    self.recordLiveNoteOn(note: note, velocity: vel)
                } else {
                    self.midiStepOn(note: note, velocity: vel)
                }
            }
            if Thread.isMainThread { handler() } else { DispatchQueue.main.async(execute: handler) }
        }
        midi?.onNoteOff = { [weak self] note in
            guard let self else { return }
            let handler = {
                self.recordLiveNoteOff(note: note)
                self.midiStepOff(note: note)
            }
            if Thread.isMainThread { handler() } else { DispatchQueue.main.async(execute: handler) }
        }
    }

    private func recordLiveNoteOn(note: UInt8, velocity: UInt8) {
        guard let audio, let timeline = playbackTimeline,
              let position = timeline.position(at: audio.playbackBeat, nearest: quantize) else { return }
        // Ljudet hanteras omedelbart via direkt MIDI Note-On (0 ms latency).
        if let inst = instrumentFor(channel: cursorChannel) {
            audio.previewOn(inst: inst, midiNote: note, velocity: velocity)
            liveNoteGeneration &+= 1
            let generation = liveNoteGeneration
            activeNotes[note] = (inst.id, generation)
            // A missing MIDI Note Off must never build a wall of sustained
            // sounds. Normal key-up releases sooner; this is only a short
            // failsafe for unplugged keyboards and stuck events.
            let safetyRelease = min(0.32, max(0.18, secPerRow * 2.0))
            DispatchQueue.main.asyncAfter(deadline: .now() + safetyRelease) { [weak self] in
                guard self?.activeNotes[note]?.generation == generation else { return }
                self?.recordLiveNoteOff(note: note)
            }
        }
        // Mönsteruppdatering UTAN tidslinje-rebuild (Del 2): skriv cellen direkt
        // och buffra händelsen i minnet. songChanged() detekterar
        // isLiveRecordingActive och skjuter upp sequencer-ombyggnaden till
        // loop/stop/Record-av. Sekvensern spelar det som fanns vid Play.
        let cell = TrackerCell(note: note, instrument: instNumber(forChannel: cursorChannel), volume: vol64(velocity))
        liveRecordBuffer.append(RecordedEvent(order: position.order, row: position.row, channel: cursorChannel, cell: cell))
        song.setCell(orderPos: position.order, row: position.row, channel: cursorChannel, cell: cell)
    }

    private func recordLiveNoteOff(note: UInt8) {
        if let active = activeNotes.removeValue(forKey: note) {
            audio?.previewOff(instrumentId: active.instrumentID, midiNote: note)
        }
    }

    // MARK: - Musmarkering + urklipp

    /// Normaliserad markeringsrektangel (r0,c0,r1,c1) eller nil.
    public func selRect() -> (Int, Int, Int, Int)? {
        guard let a = selAnchor, let b = selCursor else { return nil }
        return (min(a.row, b.row), min(a.channel, b.channel),
                max(a.row, b.row), max(a.channel, b.channel))
    }

    public func isSelected(row: Int, channel: Int) -> Bool {
        guard let r = selRect() else { return false }
        return row >= r.0 && row <= r.2 && channel >= r.1 && channel <= r.3
    }

    public func isSelectionTopEdge(row: Int, channel: Int) -> Bool {
        guard let r = selRect(), isSelected(row: row, channel: channel) else { return false }
        return row == r.0
    }

    public func isSelectionBottomEdge(row: Int, channel: Int) -> Bool {
        guard let r = selRect(), isSelected(row: row, channel: channel) else { return false }
        return row == r.2
    }

    public func isSelectionLeadingEdge(row: Int, channel: Int) -> Bool {
        guard let r = selRect(), isSelected(row: row, channel: channel) else { return false }
        return channel == r.1
    }

    public func isSelectionTrailingEdge(row: Int, channel: Int) -> Bool {
        guard let r = selRect(), isSelected(row: row, channel: channel) else { return false }
        return channel == r.3
    }

    public func clearSelection() {
        selAnchor = nil; selCursor = nil; dragActive = false
    }

    /// Klick utan shift: flytta cursor och nollställ markering.
    public func tapCell(row: Int, channel: Int) {
        cursorRow = row; cursorChannel = channel
        if !isPlaying { currentRow = row }
        clearSelection()
    }

    /// Shift+klick eller drag: utgå från ankare, utöka till punkten.
    public func extendSelection(row: Int, channel: Int) {
        guard let pid = currentPatternID,
              let pattern = song.patterns.first(where: { $0.id == pid }) else { return }
        let r = max(0, min(pattern.rowCount - 1, row))
        let c = max(0, min(SongModel.channelCount - 1, channel))
        if selAnchor == nil {
            selAnchor = SelPoint(cursorRow, cursorChannel)
        }
        selCursor = SelPoint(r, c)
        cursorRow = r; cursorChannel = c
    }

    public func selectAll() {
        guard let pid = currentPatternID,
              let pattern = song.patterns.first(where: { $0.id == pid }) else { return }
        selAnchor = SelPoint(0, 0)
        selCursor = SelPoint(pattern.rowCount - 1, SongModel.channelCount - 1)
    }

    public func copySelection() {
        guard let r = selRect() else {
            // Utan markering: kopiera cellen under cursor
            let cell = getCell(row: cursorRow, channel: cursorChannel)
            clipboard = [[cell]]
            syncPasteboard(cells: [[cell]])
            return
        }
        var block: [[TrackerCell]] = []
        for row in r.0...r.2 {
            var line: [TrackerCell] = []
            for ch in r.1...r.3 { line.append(getCell(row: row, channel: ch)) }
            block.append(line)
        }
        clipboard = block
        syncPasteboard(cells: block)
    }

    public func clearRect(_ r: (Int, Int, Int, Int)) {
        var updates: [(orderPos: Int, row: Int, channel: Int, cell: TrackerCell)] = []
        updates.reserveCapacity((r.2 - r.0 + 1) * (r.3 - r.1 + 1))
        for row in r.0...r.2 {
            for ch in r.1...r.3 { updates.append((orderPos, row, ch, .empty)) }
        }
        song.setCells(updates)
    }

    public func cutSelection() {
        copySelection()
        if let r = selRect() { clearRect(r) }
        else { setCell(row: cursorRow, channel: cursorChannel, cell: .empty) }
        clearSelection()
    }

    public func deleteSelectionOrCell() {
        if let r = selRect() { clearRect(r); clearSelection() }
        else if shouldWriteInput() { clearCell() }
    }

    public func paste(atRow targetRow: Int? = nil, atChannel targetChannel: Int? = nil) {
        guard let block = clipboard else { return }
        if isPlaying && !isRecording { return }
        if !editMode { editMode = true }
        guard let pid = currentPatternID,
              let pattern = song.patterns.first(where: { $0.id == pid }) else { return }
        let baseRow = targetRow ?? cursorRow
        let baseChannel = targetChannel ?? cursorChannel
        var updates: [(orderPos: Int, row: Int, channel: Int, cell: TrackerCell)] = []
        updates.reserveCapacity(block.count * (block.first?.count ?? 0))
        for (dr, line) in block.enumerated() {
            for (dc, cell) in line.enumerated() {
                let row = baseRow + dr, ch = baseChannel + dc
                if row < pattern.rowCount && ch < SongModel.channelCount {
                    updates.append((orderPos, row, ch, cell))
                }
            }
        }
        song.setCells(updates)
        cursorRow = min(pattern.rowCount - 1, baseRow)
        cursorChannel = min(SongModel.channelCount - 1, baseChannel)
    }

    public func moveBlock(from rect: (Int, Int, Int, Int), toRow targetRow: Int, toChannel targetChannel: Int, copy: Bool = false) {
        if isPlaying && !isRecording { return }
        if !editMode { editMode = true }
        guard let pid = currentPatternID,
              let pattern = song.patterns.first(where: { $0.id == pid }) else { return }

        var block: [[TrackerCell]] = []
        for row in rect.0...rect.2 {
            var line: [TrackerCell] = []
            for ch in rect.1...rect.3 {
                line.append(getCell(row: row, channel: ch))
            }
            block.append(line)
        }

        // EN batch-skrivning för både rensning och placering (en publicering).
        var updates: [(orderPos: Int, row: Int, channel: Int, cell: TrackerCell)] = []
        updates.reserveCapacity(block.count * (block.first?.count ?? 0) * 2)
        if !copy {
            for row in rect.0...rect.2 {
                for ch in rect.1...rect.3 {
                    updates.append((orderPos, row, ch, .empty))
                }
            }
        }

        for (dr, line) in block.enumerated() {
            for (dc, cell) in line.enumerated() {
                let row = targetRow + dr, ch = targetChannel + dc
                if row < pattern.rowCount && ch < SongModel.channelCount {
                    updates.append((orderPos, row, ch, cell))
                }
            }
        }
        song.setCells(updates)

        let height = rect.2 - rect.0
        let width = rect.3 - rect.1
        selAnchor = SelPoint(targetRow, targetChannel)
        selCursor = SelPoint(min(pattern.rowCount - 1, targetRow + height),
                             min(SongModel.channelCount - 1, targetChannel + width))
        cursorRow = min(pattern.rowCount - 1, targetRow)
        cursorChannel = min(SongModel.channelCount - 1, targetChannel)
        clipboard = block
        syncPasteboard(cells: block)
    }

    private func syncPasteboard(cells: [[TrackerCell]]) {
        var lines: [String] = []
        for row in cells {
            let rowStr = row.map { c in
                let n = TrackerCell.noteName(c.note)
                let i = c.instrument == 0 ? "--" : String(format: "%02d", c.instrument)
                let v = c.volume == 255 ? "--" : String(format: "%02X", c.volume)
                let e = c.effect == 0 ? "---" : String(format: "%X%02X", c.effect, c.param)
                return "\(n) \(i) \(v) \(e)"
            }.joined(separator: "\t")
            lines.append(rowStr)
        }
        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Favoriter och Senast Använda

    public func isFavorite(_ id: String) -> Bool {
        favoriteIDs.contains(id)
    }

    public func toggleFavorite(_ id: String) {
        if favoriteIDs.contains(id) {
            favoriteIDs.remove(id)
        } else {
            favoriteIDs.insert(id)
        }
        UserDefaults.standard.set(Array(favoriteIDs), forKey: "RetroTrakkFavorites")
    }

    public func addRecent(_ id: String) {
        recentIDs.removeAll { $0 == id }
        recentIDs.insert(id, at: 0)
        if recentIDs.count > 30 { recentIDs = Array(recentIDs.prefix(30)) }
        UserDefaults.standard.set(recentIDs, forKey: "RetroTrakkRecent")
    }

    // MARK: - Instrument-tilldelning (RetroTrakk Core Library)

    public func syncCurrentDefinitionWithChannel(_ ch: Int) {
        guard ch >= 0, ch < SongModel.channelCount else { return }
        guard let iid = song.channelInstruments[ch],
              let inst = song.instruments.first(where: { $0.id == iid }) else {
            currentDefinition = nil
            return
        }
        if let match = InstrumentCatalog.all.first(where: {
            if inst.kind == .surge { return $0.sourceType == .surge && $0.sourceIdentifier == inst.surgePatchPath }
            return $0.isDrumKit == inst.isDrumKit && $0.program == UInt8(inst.gmProgram) && $0.bankMSB == UInt8(inst.bankMSB)
        }) {
            currentDefinition = match
        } else {
            currentDefinition = nil
        }
    }

    /// Tilldela ett instrument från katalogen till en kanal.
    public func assignInstrument(_ def: InstrumentDefinition, toChannel ch: Int) {
        guard ch >= 0, ch < SongModel.channelCount else { return }
        addRecent(def.id)
        currentDefinition = def
        // Tracker-celler lagrar sitt instrument som ett index. Lägg därför
        // alltid till en ny snapshot när kanalen byter ljud: redan inspelade
        // noter måste fortsätta peka på sitt ursprungliga instrument.
        let id = (song.instruments.map(\.id).max() ?? -1) + 1
        let inst = InstrumentModel(
            id: id,
            name: def.displayName,
            kind: def.sourceType == .surge ? .surge : .coreSoundFont,
            gmProgram: Int(def.program),
            bankMSB: Int(def.bankMSB),
            bankLSB: Int(def.bankLSB),
            isDrumKit: def.isDrumKit,
            soundFontIdentifier: def.sourceIdentifier,
            surgePatchPath: def.sourceType == .surge ? def.sourceIdentifier : nil,
            midiChannel: Int(def.defaultMidiChannel)
        )
        var current = song
        current.instruments.append(inst)
        current.channelInstruments[ch] = id
        song = current
        resetComputerKeyboardChord()
        NotificationCenter.default.post(name: .retroFocusTracker, object: nil)

        // Surge patches are staged when transport/preview explicitly asks for
        // audio. Selecting from the large factory list must stay instant.
        // Samplers stegar asynkront via previewOn — klicket blockeras aldrig.
        if inst.kind != .surge {
            let triggerNote: UInt8 = def.isDrumKit ? 36 : 60
            previewOn(channel: ch, note: triggerNote, velocity: 100, autoOff: true)
        }
    }

    public func setChannelInstrument(channel ch: Int, instrumentId: Int?) {
        guard ch >= 0, ch < SongModel.channelCount else { return }
        song.channelInstruments[ch] = instrumentId
        resetComputerKeyboardChord()
        if let iid = instrumentId,
           song.instruments.contains(where: { $0.id == iid }) {
            syncCurrentDefinitionWithChannel(ch)
            NotificationCenter.default.post(name: .retroFocusTracker, object: nil)
            // previewOn stegar noden asynkront vid miss — inget sync-block här.
            previewOn(channel: ch, note: 60, velocity: 100, autoOff: true)
        }
    }

    // MARK: - Äldre Patch/Ljud-tilldelning

    public func assignPatch(name: String, gmProgram: Int, midiChannel: Int, toChannel ch: Int) {
        assignSound(name: name, kind: .dls, gmProgram: gmProgram, midiChannel: midiChannel, path: nil, toChannel: ch)
    }

    public func assignSound(name: String, kind: InstrumentKind, gmProgram: Int = 0,
                            midiChannel: Int = 0, path: String?, toChannel ch: Int) {
        guard ch >= 0, ch < SongModel.channelCount else { return }
        let id = (song.instruments.map(\.id).max() ?? -1) + 1
        let inst = InstrumentModel(id: id, name: name, kind: kind, gmProgram: gmProgram,
                                   samplePath: path, midiChannel: midiChannel)
        let apply: () -> Void = { [weak self] in
            guard let self else { return }
            var current = self.song
            current.instruments.append(inst)
            current.channelInstruments[ch] = id
            self.song = current
            self.resetComputerKeyboardChord()
            self.syncCurrentDefinitionWithChannel(ch)
            NotificationCenter.default.post(name: .retroFocusTracker, object: nil)
            self.previewOn(channel: ch, note: 60, velocity: 100, autoOff: true)
        }
        if path != nil {
            audio?.prepareSample(inst) { success in if success { apply() } }
        } else {
            audio?.ensureInstrumentAsync(inst) { [weak self] node in
                if node != nil { apply() }
            }
        }
    }

    // MARK: - Pattern/order-hantering

    public func addPattern() {
        let newID = (song.patterns.map { $0.id }.max() ?? -1) + 1
        song.patterns.append(PatternModel(id: newID, name: String(format: "%02d New", newID)))
        song.orders.append(newID)
    }

    public func duplicatePattern() {
        duplicateOrderEntry(at: orderPos)
    }

    /// Duplicera patternet som order-raden `pos` pekar på, lägg kopian direkt efter.
    public func duplicateOrderEntry(at pos: Int) {
        guard pos >= 0, pos < song.orders.count else { return }
        let pid = song.orders[pos]
        guard let src = song.patterns.first(where: { $0.id == pid }) else { return }
        let newID = (song.patterns.map { $0.id }.max() ?? -1) + 1
        var copy = src
        copy.id = newID
        copy.name = src.name + " copy"
        song.patterns.append(copy)
        song.orders.insert(newID, at: min(pos + 1, song.orders.count))
    }

    /// Ta bort en order-rad (inte själva patternet). Minst en rad behålls.
    public func deleteOrderEntry(at pos: Int) {
        guard song.orders.count > 1, pos >= 0, pos < song.orders.count else { return }
        song.orders.remove(at: pos)
        orderPos = min(orderPos, song.orders.count - 1)
        cursorRow = 0; currentRow = 0
    }

    public func moveOrderEntry(from pos: Int, delta: Int) {
        let dst = pos + delta
        guard pos >= 0, pos < song.orders.count, dst >= 0, dst < song.orders.count else { return }
        song.orders.move(fromOffsets: IndexSet(integer: pos), toOffset: delta > 0 ? dst + 1 : dst)
        if orderPos == pos { orderPos = dst }
    }

    public func renamePattern(id: Int, name: String) {
        guard let idx = song.patterns.firstIndex(where: { $0.id == id }) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { song.patterns[idx].name = clean }
    }

    public func clearPattern() {
        guard let pid = currentPatternID,
              let idx = song.patterns.firstIndex(where: { $0.id == pid }) else { return }
        song.patterns[idx].clear()
    }

    public func updateChannelState() {
        audio?.applyChannelState(song: song)
    }

    // MARK: - Project File Operations (.jgx)

    public func newProject() {
        stop()
        if let audio {
            for inst in song.instruments { audio.removeInstrument(id: inst.id) }
        }
        song = SongModel()
        currentProjectURL = nil
        currentDefinition = nil
        editMode = false
        orderPos = 0
        cursorRow = 0
        currentRow = 0
        cursorChannel = 0
        selAnchor = nil
        selCursor = nil
        syncCurrentDefinitionWithChannel(0)
    }

    public func openProject(from url: URL) throws {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        let loaded = try SongModel.load(from: url)
        stop()
        if let audio {
            for inst in song.instruments { audio.removeInstrument(id: inst.id) }
        }
        song = loaded
        currentProjectURL = url
        orderPos = 0
        cursorRow = 0
        currentRow = 0
        cursorChannel = 0
        selAnchor = nil
        selCursor = nil
        syncCurrentDefinitionWithChannel(0)
        // Stega projektets instrument i bakgrunden — filöppning ska aldrig
        // hänga på disk-IO/Surge-laddning på main.
        audio?.prewarm(song: song)
    }

    public func saveProject(to url: URL) throws {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        try song.save(to: url)
        currentProjectURL = url
    }

    /// Snabbsparande: Om filen redan sparats skrivs den direkt till disken.
    /// Returnerar true om filen sparades direkt, eller false om en filväljare behövs.
    @discardableResult
    public func quickSave() throws -> Bool {
        guard let url = currentProjectURL else { return false }
        try saveProject(to: url)
        return true
    }
}
