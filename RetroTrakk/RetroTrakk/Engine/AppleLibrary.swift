// RetroTrakk — AppleLibrary.swift
// GarageBand-likt Apple-bibliotek: kategorier med namngivna patchar.
// GarageBand-patchar exponeras INTE av macOS för tredjepartsappar, så varje
// patch mappas till ett General MIDI-program som spelas via Apple
// DLSMusicDevice (alltid tillgänglig). Trumkit använder MIDI-kanal 10.

import Foundation

public struct ApplePatch: Hashable, Identifiable, Sendable {
    public var id: String { "\(category)/\(name)" }
    public var name: String
    public var category: String
    public var gmProgram: Int
    /// MIDI-kanal (0 = melodi, 9 = trummor/kanal 10)
    public var midiChannel: Int

    public init(_ name: String, category: String, gm: Int, channel: Int = 0) {
        self.name = name; self.category = category; self.gmProgram = gm; self.midiChannel = channel
    }
}

public struct AppleCategory: Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var icon: String
    public init(_ name: String, icon: String) { self.name = name; self.icon = icon }
}

public enum AppleLibrary {
    public static let categories: [AppleCategory] = [
        AppleCategory("Pianos", icon: "pianokeys"),
        AppleCategory("Keyboards", icon: "keyboard"),
        AppleCategory("Synthesizers", icon: "waveform"),
        AppleCategory("Bass", icon: "speaker.wave.3"),
        AppleCategory("Guitars", icon: "guitar"),
        AppleCategory("Strings", icon: "music.note.list"),
        AppleCategory("Brass", icon: "megaphone"),
        AppleCategory("Woodwinds", icon: "wind"),
        AppleCategory("Drums & Percussion", icon: "drum"),
        AppleCategory("World", icon: "globe"),
    ]

    public static let patches: [ApplePatch] = [
        // MARK: Pianos (GM 0-7)
        ApplePatch("Grand Piano", category: "Pianos", gm: 0),
        ApplePatch("Upright Piano", category: "Pianos", gm: 1),
        ApplePatch("Electric Piano", category: "Pianos", gm: 4),
        ApplePatch("Classic Electric Piano", category: "Pianos", gm: 5),
        ApplePatch("Clav", category: "Pianos", gm: 7),
        ApplePatch("Harpsichord", category: "Pianos", gm: 6),
        ApplePatch("Honky-tonk Piano", category: "Pianos", gm: 3),
        ApplePatch("Stage Piano", category: "Pianos", gm: 2),
        ApplePatch("Suitcase Piano", category: "Pianos", gm: 5),
        ApplePatch("Ragtime Piano", category: "Pianos", gm: 3),
        ApplePatch("Plucked Piano", category: "Pianos", gm: 7),
        ApplePatch("Toy Piano", category: "Pianos", gm: 10),
        // MARK: Keyboards (orglar 16-23 + mallet 8-15)
        ApplePatch("Drawbar Organ", category: "Keyboards", gm: 16),
        ApplePatch("Percussive Organ", category: "Keyboards", gm: 17),
        ApplePatch("Rock Organ", category: "Keyboards", gm: 18),
        ApplePatch("Church Organ", category: "Keyboards", gm: 19),
        ApplePatch("Reed Organ", category: "Keyboards", gm: 20),
        ApplePatch("Accordion", category: "Keyboards", gm: 21),
        ApplePatch("Harmonica", category: "Keyboards", gm: 22),
        ApplePatch("Tango Accordion", category: "Keyboards", gm: 23),
        ApplePatch("Celesta", category: "Keyboards", gm: 8),
        ApplePatch("Glockenspiel", category: "Keyboards", gm: 9),
        ApplePatch("Music Box", category: "Keyboards", gm: 10),
        ApplePatch("Vibraphone", category: "Keyboards", gm: 11),
        ApplePatch("Marimba", category: "Keyboards", gm: 12),
        ApplePatch("Xylophone", category: "Keyboards", gm: 13),
        ApplePatch("Tubular Bells", category: "Keyboards", gm: 14),
        ApplePatch("Dulcimer", category: "Keyboards", gm: 15),
        // MARK: Synthesizers (80-103 + synth-varianter)
        ApplePatch("Square Lead", category: "Synthesizers", gm: 80),
        ApplePatch("Sawtooth Lead", category: "Synthesizers", gm: 81),
        ApplePatch("Calliope Lead", category: "Synthesizers", gm: 82),
        ApplePatch("Chiff Lead", category: "Synthesizers", gm: 83),
        ApplePatch("Charang Lead", category: "Synthesizers", gm: 84),
        ApplePatch("Voice Lead", category: "Synthesizers", gm: 85),
        ApplePatch("Fifths Lead", category: "Synthesizers", gm: 86),
        ApplePatch("Bass & Lead", category: "Synthesizers", gm: 87),
        ApplePatch("New Age Pad", category: "Synthesizers", gm: 88),
        ApplePatch("Warm Pad", category: "Synthesizers", gm: 89),
        ApplePatch("Polysynth Pad", category: "Synthesizers", gm: 90),
        ApplePatch("Choir Pad", category: "Synthesizers", gm: 91),
        ApplePatch("Bowed Pad", category: "Synthesizers", gm: 92),
        ApplePatch("Metallic Pad", category: "Synthesizers", gm: 93),
        ApplePatch("Halo Pad", category: "Synthesizers", gm: 94),
        ApplePatch("Sweep Pad", category: "Synthesizers", gm: 95),
        ApplePatch("Rain FX", category: "Synthesizers", gm: 96),
        ApplePatch("Soundtrack FX", category: "Synthesizers", gm: 97),
        ApplePatch("Crystal FX", category: "Synthesizers", gm: 98),
        ApplePatch("Atmosphere FX", category: "Synthesizers", gm: 99),
        ApplePatch("Sci-Fi FX", category: "Synthesizers", gm: 103),
        ApplePatch("Synth Strings", category: "Synthesizers", gm: 50),
        ApplePatch("Synth Brass", category: "Synthesizers", gm: 62),
        ApplePatch("Synth Voice", category: "Synthesizers", gm: 54),
        // MARK: Bass (32-39)
        ApplePatch("Acoustic Bass", category: "Bass", gm: 32),
        ApplePatch("Fingered Bass", category: "Bass", gm: 33),
        ApplePatch("Picked Bass", category: "Bass", gm: 34),
        ApplePatch("Fretless Bass", category: "Bass", gm: 35),
        ApplePatch("Slap Bass", category: "Bass", gm: 36),
        ApplePatch("Funk Bass", category: "Bass", gm: 37),
        ApplePatch("Synth Bass 1", category: "Bass", gm: 38),
        ApplePatch("Synth Bass 2", category: "Bass", gm: 39),
        // MARK: Guitars (24-31)
        ApplePatch("Nylon Guitar", category: "Guitars", gm: 24),
        ApplePatch("Steel-string Guitar", category: "Guitars", gm: 25),
        ApplePatch("Jazz Guitar", category: "Guitars", gm: 26),
        ApplePatch("Clean Electric Guitar", category: "Guitars", gm: 27),
        ApplePatch("Muted Electric Guitar", category: "Guitars", gm: 28),
        ApplePatch("Overdriven Guitar", category: "Guitars", gm: 29),
        ApplePatch("Distortion Guitar", category: "Guitars", gm: 30),
        ApplePatch("Guitar Harmonics", category: "Guitars", gm: 31),
        // MARK: Strings (40-55)
        ApplePatch("Violin", category: "Strings", gm: 40),
        ApplePatch("Viola", category: "Strings", gm: 41),
        ApplePatch("Cello", category: "Strings", gm: 42),
        ApplePatch("Contrabass", category: "Strings", gm: 43),
        ApplePatch("Tremolo Strings", category: "Strings", gm: 44),
        ApplePatch("Pizzicato Strings", category: "Strings", gm: 45),
        ApplePatch("Harp", category: "Strings", gm: 46),
        ApplePatch("Timpani", category: "Strings", gm: 47),
        ApplePatch("String Ensemble", category: "Strings", gm: 48),
        ApplePatch("Slow Strings", category: "Strings", gm: 49),
        ApplePatch("Choir Aahs", category: "Strings", gm: 52),
        ApplePatch("Voice Oohs", category: "Strings", gm: 53),
        ApplePatch("Orchestra Hit", category: "Strings", gm: 55),
        // MARK: Brass (56-63)
        ApplePatch("Trumpet", category: "Brass", gm: 56),
        ApplePatch("Trombone", category: "Brass", gm: 57),
        ApplePatch("Tuba", category: "Brass", gm: 58),
        ApplePatch("Muted Trumpet", category: "Brass", gm: 59),
        ApplePatch("French Horn", category: "Brass", gm: 60),
        ApplePatch("Brass Section", category: "Brass", gm: 61),
        ApplePatch("Synth Brass 1", category: "Brass", gm: 62),
        ApplePatch("Synth Brass 2", category: "Brass", gm: 63),
        // MARK: Woodwinds (64-79)
        ApplePatch("Soprano Sax", category: "Woodwinds", gm: 64),
        ApplePatch("Alto Sax", category: "Woodwinds", gm: 65),
        ApplePatch("Tenor Sax", category: "Woodwinds", gm: 66),
        ApplePatch("Baritone Sax", category: "Woodwinds", gm: 67),
        ApplePatch("Oboe", category: "Woodwinds", gm: 68),
        ApplePatch("English Horn", category: "Woodwinds", gm: 69),
        ApplePatch("Bassoon", category: "Woodwinds", gm: 70),
        ApplePatch("Clarinet", category: "Woodwinds", gm: 71),
        ApplePatch("Piccolo", category: "Woodwinds", gm: 72),
        ApplePatch("Flute", category: "Woodwinds", gm: 73),
        ApplePatch("Recorder", category: "Woodwinds", gm: 74),
        ApplePatch("Pan Flute", category: "Woodwinds", gm: 75),
        ApplePatch("Shakuhachi", category: "Woodwinds", gm: 77),
        ApplePatch("Whistle", category: "Woodwinds", gm: 78),
        ApplePatch("Ocarina", category: "Woodwinds", gm: 79),
        // MARK: Drums & Percussion (kanal 10)
        ApplePatch("Standard Kit", category: "Drums & Percussion", gm: 0, channel: 9),
        ApplePatch("Room Kit", category: "Drums & Percussion", gm: 8, channel: 9),
        ApplePatch("Power Kit", category: "Drums & Percussion", gm: 16, channel: 9),
        ApplePatch("Electronic Kit", category: "Drums & Percussion", gm: 24, channel: 9),
        ApplePatch("TR-808 Kit", category: "Drums & Percussion", gm: 25, channel: 9),
        ApplePatch("Jazz Kit", category: "Drums & Percussion", gm: 32, channel: 9),
        ApplePatch("Brush Kit", category: "Drums & Percussion", gm: 40, channel: 9),
        ApplePatch("Tinkle Bell", category: "Drums & Percussion", gm: 112),
        ApplePatch("Agogo", category: "Drums & Percussion", gm: 113),
        ApplePatch("Steel Drums", category: "Drums & Percussion", gm: 114),
        ApplePatch("Woodblock", category: "Drums & Percussion", gm: 115),
        ApplePatch("Taiko Drum", category: "Drums & Percussion", gm: 116),
        ApplePatch("Melodic Tom", category: "Drums & Percussion", gm: 117),
        ApplePatch("Reverse Cymbal", category: "Drums & Percussion", gm: 119),
        // MARK: World (104-111 + effekter)
        ApplePatch("Sitar", category: "World", gm: 104),
        ApplePatch("Banjo", category: "World", gm: 105),
        ApplePatch("Shamisen", category: "World", gm: 106),
        ApplePatch("Koto", category: "World", gm: 107),
        ApplePatch("Kalimba", category: "World", gm: 108),
        ApplePatch("Bagpipe", category: "World", gm: 109),
        ApplePatch("Fiddle", category: "World", gm: 110),
        ApplePatch("Shanai", category: "World", gm: 111),
        ApplePatch("Seashore", category: "World", gm: 122),
        ApplePatch("Bird Tweet", category: "World", gm: 123),
        ApplePatch("Telephone Ring", category: "World", gm: 124),
        ApplePatch("Helicopter", category: "World", gm: 125),
        ApplePatch("Applause", category: "World", gm: 126),
    ]

    public static func patches(in category: String) -> [ApplePatch] {
        patches.filter { $0.category == category }
    }

    // MARK: - Favoriter (UserDefaults)

    private static let favKey = "RetroTrakkFavorites"

    public static func favorites() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: favKey) ?? [])
    }

    public static func isFavorite(_ patch: ApplePatch) -> Bool {
        favorites().contains(patch.id)
    }

    public static func toggleFavorite(_ patch: ApplePatch) {
        var favs = favorites()
        if favs.contains(patch.id) { favs.remove(patch.id) } else { favs.insert(patch.id) }
        UserDefaults.standard.set(Array(favs), forKey: favKey)
    }

    public static func favoritePatches() -> [ApplePatch] {
        let favs = favorites()
        return patches.filter { favs.contains($0.id) }
    }
}

// The GM list above is kept for existing projects. This catalogue reads real
// installed instrument files, resolving relocated Sound Library symlinks.
import Combine

struct InstalledSound: Identifiable, Sendable {
    let url: URL
    let name: String
    let category: String
    let source: String
    var id: String { url.path }
    var isSampler: Bool { ["exs", "aupreset"].contains(url.pathExtension.lowercased()) }
}

final class InstalledSoundLibrary: ObservableObject {
    static let shared = InstalledSoundLibrary()
    @Published private(set) var sounds: [InstalledSound] = []
    @Published private(set) var scanning = false
    @Published private(set) var scanMessage = ""
    private var scanned = false

    func scan(force: Bool = false) {
        guard !scanning, force || !scanned else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async {
            let sounds = Self.discover()
            DispatchQueue.main.async {
                self.sounds = sounds; self.scanning = false; self.scanned = true
                let count = sounds.filter(\.isSampler).count
                self.scanMessage = "\(count) samplerinstrument · \(sounds.count - count) GarageBand-patchar"
            }
        }
    }

    static func discover() -> [InstalledSound] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots: [(String, String)] = [
            ("/Library/Application Support/GarageBand/Instrument Library/Sampler/Sampler Instruments", "GarageBand"),
            ("/Library/Application Support/Logic/Sampler Instruments", "Logic / GarageBand"),
            (home + "/Music/Audio Music Apps/Sampler Instruments", "Egna instrument"),
            (home + "/Library/Audio/Presets/Apple/AUSampler", "Egna instrument"),
            ("/Applications/GarageBand.app/Contents/Resources/Patches/Instrument", "GarageBand-patch"),
            (home + "/Music/Audio Music Apps/Patches/Instrument", "Egen patch")
        ]
        var found: [InstalledSound] = []; var visited = Set<String>()
        for (path, source) in roots {
            let root = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in files {
                let ext = url.pathExtension.lowercased()
                guard ["exs", "aupreset", "patch"].contains(ext) else { continue }
                if ext == "patch" { files.skipDescendants() }
                let canonical = url.resolvingSymlinksInPath()
                guard visited.insert(canonical.path).inserted else { continue }
                let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
                let folders = relative.split(separator: "/").dropLast()
                let category = folders.first.map(String.init) ?? "Övrigt"
                found.append(InstalledSound(url: canonical, name: url.deletingPathExtension().lastPathComponent,
                                            category: category, source: source))
            }
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
