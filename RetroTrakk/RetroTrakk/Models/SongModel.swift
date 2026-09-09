// RetroTrakk — SongModel.swift
// Codable song/pattern/track/instrument-modell. Ljus MVP: 8 kanaler, 64 rader.

import Foundation

// MARK: - TrackerCell

/// Tracker-effekter som är gemensamma för griden, uppspelningen och WAV-export.
/// Fxx betyder att kanalen skickar en release/all-notes-off på den raden. Det
/// låter instrumentets egen envelope tona ut i stället för att kapa signalen.
public enum TrackerEffect {
    public static let fadeOut: UInt8 = 0xF
    public static let defaultFadeParameter: UInt8 = 0x08
}

/// En cell i trackern. note: 0...127 MIDI, 254 = Note Off (===), 255 = tom (---)
/// instrument: 0 = tom (--), annars 1-baserat index. volume: 0...64, 255 = tom.
public struct TrackerCell: Codable, Hashable, Sendable {
    public var note: UInt8       // 255 tom, 254 off
    public var instrument: UInt8 // 0 tom
    public var volume: UInt8     // 255 tom, 0...64
    public var effect: UInt8     // 0 = ingen
    public var param: UInt8

    public static let empty = TrackerCell(note: 255, instrument: 0, volume: 255, effect: 0, param: 0)
    public static let noteOff = TrackerCell(note: 254, instrument: 0, volume: 255, effect: 0, param: 0)

    public init(note: UInt8 = 255, instrument: UInt8 = 0, volume: UInt8 = 255, effect: UInt8 = 0, param: UInt8 = 0) {
        self.note = note
        self.instrument = instrument
        self.volume = volume
        self.param = param
        self.effect = effect
    }

    public var isEmpty: Bool { note == 255 && instrument == 0 && volume == 255 && effect == 0 }

    public static func noteName(_ midi: UInt8) -> String {
        if midi == 255 { return "---" }
        if midi == 254 { return "===" }
        let names = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]
        let n = Int(midi)
        return "\(names[n % 12])\(n / 12 - 1)"
    }
}

// MARK: - PatternModel

public struct PatternModel: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var rowCount: Int
    public var channelCount: Int
    /// cells[row][channel]
    public var cells: [[TrackerCell]]

    public init(id: Int, name: String, rows: Int = 64, channels: Int = 8) {
        self.id = id
        self.name = name
        self.rowCount = rows
        self.channelCount = channels
        let row = Array(repeating: TrackerCell.empty, count: channels)
        self.cells = Array(repeating: row, count: rows)
    }

    public subscript(row: Int, channel: Int) -> TrackerCell {
        get {
            guard row >= 0, row < cells.count, channel >= 0, channel < channelCount, channel < cells[row].count else { return .empty }
            return cells[row][channel]
        }
        set {
            guard row >= 0, row < cells.count, channel >= 0, channel < channelCount, channel < cells[row].count else { return }
            cells[row][channel] = newValue
        }
    }

    mutating func ensureSize(rows: Int, channels: Int) {
        rowCount = rows; channelCount = channels
        if cells.count != rows {
            let blank = Array(repeating: TrackerCell.empty, count: channels)
            if cells.count < rows {
                cells += Array(repeating: blank, count: rows - cells.count)
            } else {
                cells = Array(cells.prefix(rows))
            }
        }
        for r in 0..<cells.count {
            if cells[r].count < channels {
                cells[r] += Array(repeating: TrackerCell.empty, count: channels - cells[r].count)
            } else if cells[r].count > channels {
                cells[r] = Array(cells[r].prefix(channels))
            }
        }
    }

    mutating func clear() {
        let row = Array(repeating: TrackerCell.empty, count: channelCount)
        cells = Array(repeating: row, count: rowCount)
    }
}

// MARK: - InstrumentModel

public enum InstrumentKind: String, Codable, Sendable {
    case surge         // Inbyggda Surge XT-presets (.fxp)
    case coreSoundFont // Inbyggt Core SoundFont-bibliotek (MuseScore General via AUSampler)
    case dls           // Apple DLSMusicDevice (GM)
    case auSampler     // Apple AUSampler (EXS / aupreset)
    case audioUnit     // Tredjeparts AU MusicDevice
    case sample        // WAV/AIFF via AUSampler
}

public struct InstrumentModel: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var kind: InstrumentKind
    /// GM-program 0...127
    public var gmProgram: Int
    /// Bank MSB (121 för melodiskt SoundFont, 120 för trumset)
    public var bankMSB: Int
    /// Bank LSB (normalt 0)
    public var bankLSB: Int
    public var isDrumKit: Bool
    /// Resursidentifierare för SoundFont (t.ex. "MuseScore_General.sf2")
    public var soundFontIdentifier: String?
    /// Relativ sökväg under Surge XT:s patches_factory-katalog.
    public var surgePatchPath: String?
    /// För audioUnit: komponentnamn + manufacturer för återupplösning
    public var auName: String?
    public var auManufacturer: String?
    /// För sample: filsökväg (bokmärke förenklas till path i MVP)
    public var samplePath: String?
    public var volume: Double // 0...1
    public var pan: Double    // -1...1
    /// MIDI-kanal 0...15. Trumkit (GM) kräver kanal 10 = index 9.
    public var midiChannel: Int

    public init(id: Int, name: String, kind: InstrumentKind = .coreSoundFont, gmProgram: Int = 0,
                bankMSB: Int = 121, bankLSB: Int = 0, isDrumKit: Bool = false,
                soundFontIdentifier: String? = nil, surgePatchPath: String? = nil,
                auName: String? = nil, auManufacturer: String? = nil, samplePath: String? = nil,
                volume: Double = 0.8, pan: Double = 0, midiChannel: Int = 0) {
        self.id = id; self.name = name; self.kind = kind; self.gmProgram = gmProgram
        self.bankMSB = bankMSB; self.bankLSB = bankLSB; self.isDrumKit = isDrumKit
        self.soundFontIdentifier = soundFontIdentifier
        self.surgePatchPath = surgePatchPath
        self.auName = auName; self.auManufacturer = auManufacturer; self.samplePath = samplePath
        self.volume = volume; self.pan = pan; self.midiChannel = midiChannel
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, gmProgram, bankMSB, bankLSB, isDrumKit, soundFontIdentifier,
             surgePatchPath, auName, auManufacturer, samplePath, volume, pan, midiChannel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Instrument"
        kind = try c.decodeIfPresent(InstrumentKind.self, forKey: .kind) ?? .coreSoundFont
        gmProgram = try c.decodeIfPresent(Int.self, forKey: .gmProgram) ?? 0
        let ch = try c.decodeIfPresent(Int.self, forKey: .midiChannel) ?? 0
        midiChannel = ch
        let drum = try c.decodeIfPresent(Bool.self, forKey: .isDrumKit) ?? (ch == 9)
        isDrumKit = drum
        bankMSB = try c.decodeIfPresent(Int.self, forKey: .bankMSB) ?? (drum ? 120 : 121)
        bankLSB = try c.decodeIfPresent(Int.self, forKey: .bankLSB) ?? 0
        soundFontIdentifier = try c.decodeIfPresent(String.self, forKey: .soundFontIdentifier)
        surgePatchPath = try c.decodeIfPresent(String.self, forKey: .surgePatchPath)
        auName = try c.decodeIfPresent(String.self, forKey: .auName)
        auManufacturer = try c.decodeIfPresent(String.self, forKey: .auManufacturer)
        samplePath = try c.decodeIfPresent(String.self, forKey: .samplePath)
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 0.8
        pan = try c.decodeIfPresent(Double.self, forKey: .pan) ?? 0
    }
}

// MARK: - SongModel

public struct SongModel: Codable, Sendable {
    public static let channelCount = 8
    public static let defaultRows = 64

    public var title: String
    public var bpm: Double
    /// steps per beat för kvantisering: 1, 2, 4 eller 8
    public var stepsPerBeat: Int
    public var patterns: [PatternModel]
    /// order-lista: pattern-id per position
    public var orders: [Int]
    public var instruments: [InstrumentModel]
    /// kanal -> instrument-id (index i instruments), nil = inget
    public var channelInstruments: [Int?]
    public var channelVolume: [Double]
    public var channelPan: [Double]
    public var channelMute: [Bool]
    public var channelSolo: [Bool]
    /// Kanal av/på (power). Avstängd kanal låter inte och tonas ned i UI.
    public var channelEnabled: [Bool]

    public init(title: String = "Untitled") {
        self.title = title
        self.bpm = 125
        self.stepsPerBeat = 4
        self.patterns = [PatternModel(id: 0, name: "00 Intro"),
                         PatternModel(id: 1, name: "01 Verse")]
        self.orders = [0, 1]
        self.instruments = []
        self.channelInstruments = Array(repeating: nil, count: SongModel.channelCount)
        self.channelVolume = Array(repeating: 0.8, count: 8)
        self.channelPan = Array(repeating: 0.0, count: 8)
        self.channelMute = Array(repeating: false, count: 8)
        self.channelSolo = Array(repeating: false, count: 8)
        self.channelEnabled = Array(repeating: true, count: 8)
    }

    public func pattern(id: Int) -> PatternModel? {
        patterns.first(where: { $0.id == id })
    }

    public mutating func setCell(orderPos: Int, row: Int, channel: Int, cell: TrackerCell) {
        guard orderPos >= 0, orderPos < orders.count else { return }
        let pid = orders[orderPos]
        guard let idx = patterns.firstIndex(where: { $0.id == pid }) else { return }
        patterns[idx][row, channel] = cell
    }

    public func getCell(orderPos: Int, row: Int, channel: Int) -> TrackerCell {
        guard orderPos >= 0, orderPos < orders.count else { return .empty }
        let pid = orders[orderPos]
        guard let p = patterns.first(where: { $0.id == pid }) else { return .empty }
        return p[row, channel]
    }

    // MARK: Persistence

    enum CodingKeys: String, CodingKey {
        case title, bpm, stepsPerBeat, patterns, orders, instruments,
             channelInstruments, channelVolume, channelPan, channelMute, channelSolo, channelEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        bpm = try c.decodeIfPresent(Double.self, forKey: .bpm) ?? 125
        stepsPerBeat = try c.decodeIfPresent(Int.self, forKey: .stepsPerBeat) ?? 4
        patterns = try c.decodeIfPresent([PatternModel].self, forKey: .patterns) ?? []
        if patterns.isEmpty { patterns = [PatternModel(id: 0, name: "00 Intro")] }
        orders = try c.decodeIfPresent([Int].self, forKey: .orders) ?? [0]
        instruments = try c.decodeIfPresent([InstrumentModel].self, forKey: .instruments) ?? []
        let n = SongModel.channelCount
        channelInstruments = try c.decodeIfPresent([Int?].self, forKey: .channelInstruments) ?? Array(repeating: nil, count: n)
        channelVolume = try c.decodeIfPresent([Double].self, forKey: .channelVolume) ?? Array(repeating: 0.8, count: n)
        channelPan = try c.decodeIfPresent([Double].self, forKey: .channelPan) ?? Array(repeating: 0.0, count: n)
        channelMute = try c.decodeIfPresent([Bool].self, forKey: .channelMute) ?? Array(repeating: false, count: n)
        channelSolo = try c.decodeIfPresent([Bool].self, forKey: .channelSolo) ?? Array(repeating: false, count: n)
        channelEnabled = try c.decodeIfPresent([Bool].self, forKey: .channelEnabled) ?? Array(repeating: true, count: n)
        // Fyll ut om gammal fil har kortare arrayer
        channelInstruments += Array(repeating: nil, count: max(0, n - channelInstruments.count))
        channelVolume += Array(repeating: 0.8, count: max(0, n - channelVolume.count))
        channelPan += Array(repeating: 0.0, count: max(0, n - channelPan.count))
        channelMute += Array(repeating: false, count: max(0, n - channelMute.count))
        channelSolo += Array(repeating: false, count: max(0, n - channelSolo.count))
        channelEnabled += Array(repeating: true, count: max(0, n - channelEnabled.count))
    }

    public func save(to url: URL) throws {
        try JGXProject.save(song: self, to: url)
    }

    public static func load(from url: URL) throws -> SongModel {
        try JGXProject.load(from: url)
    }
}

/// Playback has exactly one source of truth: cells at absolute grid positions.
/// No key-down timestamps or UI playhead state are stored in this timeline.
struct PlaybackTimeline {
    struct Voice: Hashable {
        let channel: Int
        let instrumentID: Int
    }
    struct Note: Equatable {
        let voice: Voice
        let key: UInt8
        let velocity: UInt8
        let midiChannel: UInt8
        let beat: Double
        let duration: Double
    }
    struct Fade: Equatable {
        let voice: Voice
        let midiChannel: UInt8
        let beat: Double
    }
    let notes: [Note]
    let fades: [Fade]
    let orderStarts: [Double]
    let orderRows: [Int]
    let stepsPerBeat: Double
    let length: Double

    init(song: SongModel) {
        stepsPerBeat = Double(max(1, song.stepsPerBeat))
        var notes: [Note] = []
        var fades: [Fade] = []
        var starts: [Double] = []
        var rows: [Int] = []
        var offset = 0.0
        for pid in song.orders {
            starts.append(offset)
            let pattern = song.pattern(id: pid)
            let count = max(0, pattern?.rowCount ?? 0)
            rows.append(count)
            if let pattern {
                for row in 0..<count {
                    for ch in 0..<SongModel.channelCount {
                        let cell = pattern[row, ch]
                        let beat = offset + Double(row) / stepsPerBeat
                        let instrument: InstrumentModel?
                        if cell.instrument > 0 {
                            let index = Int(cell.instrument) - 1
                            instrument = song.instruments.indices.contains(index) ? song.instruments[index] : nil
                        } else if let chInstID = song.channelInstruments[ch], let match = song.instruments.first(where: { $0.id == chInstID }) {
                            instrument = match
                        } else {
                            instrument = nil
                        }
                        guard let instrument else { continue }
                        let voice = Voice(channel: ch, instrumentID: instrument.id)
                        let midiChannel = UInt8(instrument.midiChannel & 15)
                        if cell.note <= 127 {
                            let velocity = cell.volume == 255 ? 100 : Int((Double(cell.volume) / 64 * 127).rounded())
                            notes.append(Note(voice: voice, key: cell.note,
                                              velocity: UInt8(max(0, min(127, velocity))),
                                              midiChannel: midiChannel,
                                              beat: beat,
                                              duration: 0.95 / stepsPerBeat))
                        }
                        if cell.effect == TrackerEffect.fadeOut {
                            fades.append(Fade(voice: voice, midiChannel: midiChannel, beat: beat))
                        }
                    }
                }
            }
            offset += Double(count) / stepsPerBeat
        }
        self.notes = notes; self.fades = fades; orderStarts = starts; orderRows = rows; length = offset
    }

    func beat(order: Int, row: Int) -> Double {
        guard orderStarts.indices.contains(order) else { return 0 }
        return orderStarts[order] + Double(max(0, min(max(0, orderRows[order] - 1), row))) / stepsPerBeat
    }

    func position(at beat: Double, nearest: Bool = false) -> (order: Int, row: Int)? {
        let grid = nearest ? (beat * stepsPerBeat).rounded() : floor(beat * stepsPerBeat + 0.000001)
        let quantizedBeat = max(0, grid / stepsPerBeat)
        guard quantizedBeat < length else { return nil }
        for order in orderStarts.indices.reversed() where orderRows[order] > 0 {
            if quantizedBeat >= orderStarts[order] {
                return (order, min(orderRows[order] - 1, Int(((quantizedBeat - orderStarts[order]) * stepsPerBeat).rounded())))
            }
        }
        return nil
    }
}
