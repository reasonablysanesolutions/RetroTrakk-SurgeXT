// RetroTrakk — TrackerEngine.swift
// Uppspelning, cursor, step input och live-inspelning (kvantiserad).

import Foundation
import SwiftUI
import Combine

/// En punkt i tracker-griden (rad, kanal). Används för musmarkering.
public struct SelPoint: Hashable, Sendable {
    public var row: Int
    public var channel: Int
    public init(_ row: Int, _ channel: Int) { self.row = row; self.channel = channel }
}

public final class TrackerEngine: ObservableObject {
    @Published public var song = SongModel() { didSet { songChanged(from: oldValue) } }
    @Published public var orderPos: Int = 0
    @Published public var currentRow: Int = 0
    @Published public var isPlaying: Bool = false
    @Published public var isRecording: Bool = false
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
    /// Slagposition inom takten (0 = taktslag). Driver beat-LED i toolbaren.
    @Published public var beatPhase: Int = 0
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
    private var playbackTimeline: PlaybackTimeline?
    private var activeNotes: [UInt8: Int] = [:]

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
        guard !timeline.notes.isEmpty else {
            audio.statusText = "Pattern/order-listan innehåller inga noter att spela."
            return
        }

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
            orderPos = startOrder
            currentRow = startRow
            cursorRow = startRow
            isPlaying = true
            updatePlayhead()
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.updatePlayhead()
            }
            RunLoop.main.add(timer, forMode: .common)
            playheadTimer = timer
        } catch {
            audio.statusText = "Uppspelning misslyckades: \(error.localizedDescription)"
            stop()
        }
    }

    public func stop() {
        playheadTimer?.invalidate()
        playheadTimer = nil
        audio?.stopPlayback()
        isPlaying = false
        textureActive = false
        midiHeld.removeAll()
        activeNotes.removeAll()
        audio?.allNotesOff()
        // När uppspelningen stoppas ligger samma rad kvar som edit cursor row
        currentRow = cursorRow
    }

    private func updatePlayhead() {
        guard isPlaying, let timeline = playbackTimeline, let audio else { return }
        guard let position = timeline.position(at: audio.playbackBeat) else {
            loopPlayback()
            return
        }
        if orderPos != position.order { orderPos = position.order }
        if currentRow != position.row { currentRow = position.row }
        let phase = position.row % max(1, song.stepsPerBeat)
        if beatPhase != phase { beatPhase = phase }
    }

    private func loopPlayback() {
        guard isPlaying, let audio, playbackTimeline != nil else { return }
        do {
            orderPos = 0
            currentRow = 0
            cursorRow = 0
            beatPhase = 0
            try audio.startPlayback(at: 0)
        } catch {
            stop()
        }
    }

    private func songChanged(from old: SongModel) {
        audio?.applyChannelState(song: song)
        guard isPlaying, let audio else { return }
        if old.bpm != song.bpm { audio.setPlaybackTempo(song.bpm) }
        guard old.patterns != song.patterns || old.orders != song.orders ||
              old.stepsPerBeat != song.stepsPerBeat || old.instruments != song.instruments ||
              old.channelInstruments != song.channelInstruments else { return }
        let timeline = PlaybackTimeline(song: song)
        do {
            try audio.updatePlayback(song: song, timeline: timeline)
            playbackTimeline = timeline
        } catch {
            audio.statusText = "Kunde inte uppdatera uppspelning: \(error.localizedDescription)"
            stop()
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
        if let inst = instrumentFor(channel: cursorChannel) {
            audio.previewOn(inst: inst, midiNote: note, velocity: velocity)
            activeNotes[note] = inst.id
        }
        let cell = TrackerCell(note: note, instrument: instNumber(forChannel: cursorChannel), volume: vol64(velocity))
        song.setCell(orderPos: position.order, row: position.row, channel: cursorChannel, cell: cell)
    }

    private func recordLiveNoteOff(note: UInt8) {
        if let iid = activeNotes.removeValue(forKey: note) {
            audio?.previewOff(instrumentId: iid, midiNote: note)
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
        for row in r.0...r.2 {
            for ch in r.1...r.3 { setCell(row: row, channel: ch, cell: .empty) }
        }
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
        for (dr, line) in block.enumerated() {
            for (dc, cell) in line.enumerated() {
                let row = baseRow + dr, ch = baseChannel + dc
                if row < pattern.rowCount && ch < SongModel.channelCount {
                    setCell(row: row, channel: ch, cell: cell)
                }
            }
        }
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

        if !copy {
            for row in rect.0...rect.2 {
                for ch in rect.1...rect.3 {
                    setCell(row: row, channel: ch, cell: .empty)
                }
            }
        }

        for (dr, line) in block.enumerated() {
            for (dc, cell) in line.enumerated() {
                let row = targetRow + dr, ch = targetChannel + dc
                if row < pattern.rowCount && ch < SongModel.channelCount {
                    setCell(row: row, channel: ch, cell: cell)
                }
            }
        }

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
            $0.isDrumKit == inst.isDrumKit && $0.program == UInt8(inst.gmProgram) && $0.bankMSB == UInt8(inst.bankMSB)
        }) {
            currentDefinition = match
        } else {
            currentDefinition = nil
        }
    }

    private func updateChannelCells(channel ch: Int, toInstrumentIndex newIdx: Int) {
        let newInstNum = UInt8(newIdx + 1)
        for pIdx in song.patterns.indices {
            for rIdx in 0..<song.patterns[pIdx].rowCount {
                let cell = song.patterns[pIdx].cells[rIdx][ch]
                if !cell.isEmpty {
                    var updatedCell = cell
                    updatedCell.instrument = newInstNum
                    song.patterns[pIdx].cells[rIdx][ch] = updatedCell
                }
            }
        }
    }

    /// Tilldela ett instrument från katalogen till en kanal.
    public func assignInstrument(_ def: InstrumentDefinition, toChannel ch: Int) {
        guard ch >= 0, ch < SongModel.channelCount else { return }
        addRecent(def.id)
        currentDefinition = def
        let updated = song
        let existing = updated.instruments.firstIndex { $0.id == updated.channelInstruments[ch] }
        let id = existing.map { updated.instruments[$0].id } ?? ((updated.instruments.map(\.id).max() ?? -1) + 1)
        let inst = InstrumentModel(
            id: id,
            name: def.displayName,
            kind: .coreSoundFont,
            gmProgram: Int(def.program),
            bankMSB: Int(def.bankMSB),
            bankLSB: Int(def.bankLSB),
            isDrumKit: def.isDrumKit,
            soundFontIdentifier: def.sourceIdentifier,
            midiChannel: Int(def.defaultMidiChannel)
        )
        var current = song
        var instIndex: Int
        if let index = current.instruments.firstIndex(where: { $0.id == id }) {
            current.instruments[index] = inst
            instIndex = index
        } else {
            current.instruments.append(inst)
            instIndex = current.instruments.count - 1
        }
        current.channelInstruments[ch] = id
        song = current

        updateChannelCells(channel: ch, toInstrumentIndex: instIndex)

        _ = audio?.ensureInstrument(inst)
        let triggerNote: UInt8 = def.isDrumKit ? 36 : 60
        previewOn(channel: ch, note: triggerNote, velocity: 100, autoOff: true)
    }

    public func setChannelInstrument(channel ch: Int, instrumentId: Int?) {
        guard ch >= 0, ch < SongModel.channelCount else { return }
        song.channelInstruments[ch] = instrumentId
        if let iid = instrumentId,
           let instIdx = song.instruments.firstIndex(where: { $0.id == iid }) {
            updateChannelCells(channel: ch, toInstrumentIndex: instIdx)
            _ = audio?.ensureInstrument(song.instruments[instIdx])
            syncCurrentDefinitionWithChannel(ch)
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
        let updated = song
        let existing = updated.instruments.firstIndex { $0.id == updated.channelInstruments[ch] }
        let id = existing.map { updated.instruments[$0].id } ?? ((updated.instruments.map(\.id).max() ?? -1) + 1)
        let inst = InstrumentModel(id: id, name: name, kind: kind, gmProgram: gmProgram,
                                   samplePath: path, midiChannel: midiChannel)
        let apply: () -> Void = { [weak self] in
            guard let self else { return }
            var current = self.song
            var instIndex: Int
            if let index = current.instruments.firstIndex(where: { $0.id == id }) {
                current.instruments[index] = inst
                instIndex = index
            } else {
                current.instruments.append(inst)
                instIndex = current.instruments.count - 1
            }
            current.channelInstruments[ch] = id
            self.song = current
            self.updateChannelCells(channel: ch, toInstrumentIndex: instIndex)
            self.syncCurrentDefinitionWithChannel(ch)
            self.previewOn(channel: ch, note: 60, velocity: 100, autoOff: true)
        }
        if path != nil {
            audio?.prepareSample(inst) { success in if success { apply() } }
        } else if audio?.ensureInstrument(inst) != nil { apply() }
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
        if let audio {
            for inst in song.instruments { _ = audio.ensureInstrument(inst) }
        }
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
