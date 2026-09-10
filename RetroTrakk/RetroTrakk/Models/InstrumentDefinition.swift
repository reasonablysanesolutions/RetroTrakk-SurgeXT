// RetroTrakk — InstrumentDefinition.swift
// Universell instrumentmodell och komplett Core Library-katalog.
// "Välj ljud, inte plugin." Döljer tekniska detaljer som bank, program och samplertyp.

import Foundation

// MARK: - InstrumentCategory

public enum InstrumentCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case piano = "Piano"
    case electricPiano = "Electric Piano"
    case keys = "Keys"
    case organ = "Organ"
    case guitar = "Guitar"
    case bass = "Bass"
    case strings = "Strings"
    case choir = "Choir"
    case brass = "Brass"
    case woodwinds = "Woodwinds"
    case synthBass = "Synth Bass"
    case synthLead = "Synth Lead"
    case synthPad = "Synth Pad"
    case pluck = "Pluck"
    case sequence = "Sequences"
    case mallets = "Mallets"
    case drums = "Drums"
    case percussion = "Percussion"
    case fx = "FX"

    public var id: String { rawValue }
    public var name: String { rawValue }

    public var icon: String {
        switch self {
        case .piano: return "pianokeys"
        case .electricPiano: return "pianokeys"
        case .keys: return "keyboard"
        case .organ: return "pianokeys"
        case .guitar: return "guitars"
        case .bass: return "speaker.wave.3"
        case .strings: return "music.note.list"
        case .choir: return "person.3"
        case .brass: return "horn"
        case .woodwinds: return "wind"
        case .synthBass: return "waveform.badge.plus"
        case .synthLead: return "waveform"
        case .synthPad: return "sparkles"
        case .pluck: return "tuningfork"
        case .sequence: return "repeat"
        case .mallets: return "circle.grid.2x2"
        case .drums: return "drum"
        case .percussion: return "circle.hexagongrid"
        case .fx: return "wand.and.stars"
        }
    }
}

// MARK: - InstrumentSourceType

public enum InstrumentSourceType: String, Codable, Sendable {
    case surge
    case coreSoundFont
    case internalSynth
    case audioUnit
    case auSampler
    case sample
}

// MARK: - InstrumentDefinition

public struct InstrumentDefinition: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let category: InstrumentCategory
    public let tags: [String]
    public let description: String
    public let sourceType: InstrumentSourceType
    public let sourceIdentifier: String
    public let bankMSB: UInt8
    public let bankLSB: UInt8
    public let program: UInt8
    public let isDrumKit: Bool
    public let defaultMidiChannel: UInt8
    public let metadata: [String: String]

    public init(
        id: String,
        displayName: String,
        category: InstrumentCategory,
        tags: [String] = [],
        description: String = "",
        sourceType: InstrumentSourceType = .coreSoundFont,
        sourceIdentifier: String = "MuseScore_General.sf2",
        bankMSB: UInt8 = 121,
        bankLSB: UInt8 = 0,
        program: UInt8 = 0,
        isDrumKit: Bool = false,
        defaultMidiChannel: UInt8 = 0,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.tags = tags
        self.description = description
        self.sourceType = sourceType
        self.sourceIdentifier = sourceIdentifier
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.program = program
        self.isDrumKit = isDrumKit
        self.defaultMidiChannel = defaultMidiChannel
        self.metadata = metadata
    }

    /// Matchar en söksträng mot namn, kategori, taggar och beskrivning.
    public func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        if displayName.localizedCaseInsensitiveContains(q) { return true }
        if category.name.localizedCaseInsensitiveContains(q) { return true }
        if description.localizedCaseInsensitiveContains(q) { return true }
        return tags.contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

// MARK: - InstrumentCatalog

public enum InstrumentCatalog {
    private static func melodic(
        _ id: String, _ name: String, _ cat: InstrumentCategory,
        program: UInt8, tags: [String], desc: String = ""
    ) -> InstrumentDefinition {
        InstrumentDefinition(
            id: id, displayName: name, category: cat,
            tags: tags, description: desc,
            sourceType: .coreSoundFont,
            sourceIdentifier: "MuseScore_General.sf2",
            bankMSB: 121, bankLSB: 0, program: program,
            isDrumKit: false, defaultMidiChannel: 0
        )
    }

    private static func drumKit(
        _ id: String, _ name: String, program: UInt8,
        tags: [String], desc: String = ""
    ) -> InstrumentDefinition {
        InstrumentDefinition(
            id: id, displayName: name, category: .drums,
            tags: tags + ["drums", "kit", "drum kit", "percussion"], description: desc,
            sourceType: .coreSoundFont,
            sourceIdentifier: "MuseScore_General.sf2",
            bankMSB: 120, bankLSB: 0, program: program,
            isDrumKit: true, defaultMidiChannel: 9
        )
    }

    private static let legacyCoreSoundFontDefinitions: [InstrumentDefinition] = [
        // MARK: Piano
        melodic("piano_grand", "Grand Piano", .piano, program: 0,
                tags: ["acoustic", "grand", "piano", "keyboard", "classical", "concert"],
                desc: "Klassisk akustisk konsertflygel med varmt och fylligt anslag."),
        melodic("piano_bright", "Bright Piano", .piano, program: 1,
                tags: ["acoustic", "bright", "piano", "pop", "rock", "punchy"],
                desc: "Akustiskt piano med framhävd diskant för pop och rock."),
        melodic("piano_electric_grand", "Electric Grand", .piano, program: 2,
                tags: ["electric", "grand", "80s", "stage", "rock", "piano"],
                desc: "Klassiskt 80-tals elektroakustiskt scenpiano."),
        melodic("piano_honky_tonk", "Honky-tonk Piano", .piano, program: 3,
                tags: ["vintage", "ragtime", "piano", "saloon", "detuned"],
                desc: "Lätt avstämt salongspiano i klassisk ragtime-stil."),
        melodic("piano_harpsichord", "Harpsichord", .piano, program: 6,
                tags: ["keyboard", "baroque", "classical", "plucked", "cembalo"],
                desc: "Barockens cembalo med distinkt knäppande klang."),
        melodic("piano_clavinet", "Clavinet", .piano, program: 7,
                tags: ["funk", "vintage", "keyboard", "70s", "clav", "groove"],
                desc: "Klassisk elektrodynamisk clavinet för funk och soul."),

        // MARK: Electric Piano
        melodic("ep_stage", "Electric Piano", .electricPiano, program: 4,
                tags: ["rhodes", "vintage", "smooth", "keys", "jazz", "soul", "soft", "warm"],
                desc: "Varmt klassiskt tines-elbass/Rhodes-piano med mjuk dynamik."),
        melodic("ep_fm", "FM Electric Piano", .electricPiano, program: 5,
                tags: ["dx7", "80s", "bright", "ballad", "bell", "digital", "keys"],
                desc: "Kristallklart 80-tals FM-syntpiano med karakteristisk klockklang."),

        // MARK: Keys
        melodic("keys_accordion", "Accordion", .keys, program: 21,
                tags: ["folk", "traditional", "french", "keys", "squeeze"],
                desc: "Europeiskt dragspel med fyllig stämma."),
        melodic("keys_bandoneon", "Bandoneon", .keys, program: 23,
                tags: ["tango", "accordion", "argentina", "keys"],
                desc: "Traditionellt tango-dragspel med innerlig ton."),
        melodic("keys_harmonica", "Harmonica", .keys, program: 22,
                tags: ["blues", "mouth organ", "folk", "acoustic"],
                desc: "Klassiskt munspel för blues och roots."),

        // MARK: Organ
        melodic("organ_drawbar", "Drawbar Organ", .organ, program: 16,
                tags: ["hammond", "vintage", "rock", "jazz", "soul", "b3", "warm"],
                desc: "Klassisk tonhjulsorgel med fyllig drawbar-klang."),
        melodic("organ_percussive", "Percussive Organ", .organ, program: 17,
                tags: ["organ", "attack", "jazz", "percussion", "vintage"],
                desc: "Tonhjulsorgel med perkussiv attack för jazz och blues."),
        melodic("organ_rock", "Rock Organ", .organ, program: 18,
                tags: ["rock", "overdrive", "organ", "distorted", "energy"],
                desc: "Kraftfull rockorgel med karakteristisk saturation."),
        melodic("organ_church", "Church Organ", .organ, program: 19,
                tags: ["pipe", "cathedral", "sacred", "majestic", "classical"],
                desc: "Stor piporgel med sakral katedralakustik."),
        melodic("organ_reed", "Reed Organ", .organ, program: 20,
                tags: ["pump", "harmonium", "vintage", "nostalgic"],
                desc: "Tramp- eller kammarorgel med personlig ton."),

        // MARK: Guitar
        melodic("gtr_nylon", "Nylon Guitar", .guitar, program: 24,
                tags: ["classical", "spanish", "acoustic", "soft", "gentle", "guitar"],
                desc: "Klassisk spansk gitarr med mjuka nylonträngar."),
        melodic("gtr_steel", "Steel-string Guitar", .guitar, program: 25,
                tags: ["acoustic", "folk", "strum", "bright", "guitar"],
                desc: "Akustisk stålsträngad westerngitarr."),
        melodic("gtr_jazz", "Jazz Guitar", .guitar, program: 26,
                tags: ["clean", "hollow", "warm", "electric", "jazz", "smooth"],
                desc: "Ihålig halvakustisk jazzgitarr med mjuk halspickup."),
        melodic("gtr_clean", "Clean Electric Guitar", .guitar, program: 27,
                tags: ["electric", "strat", "bright", "pop", "clean"],
                desc: "Klar elektrisk gitarr med dynamisk strängklang."),
        melodic("gtr_muted", "Muted Electric Guitar", .guitar, program: 28,
                tags: ["electric", "funk", "palm mute", "tight", "rhythm"],
                desc: "Palmmutad elgitarr för funk och rytmiska fills."),
        melodic("gtr_overdrive", "Overdriven Guitar", .guitar, program: 29,
                tags: ["rock", "drive", "blues", "crunch"],
                desc: "Rörförstärkt elgitarr med varm overdrive."),
        melodic("gtr_distortion", "Distortion Guitar", .guitar, program: 30,
                tags: ["heavy", "metal", "power", "rock", "lead", "sustain"],
                desc: "Distad elgitarr för powerackord och solon."),
        melodic("gtr_harmonics", "Guitar Harmonics", .guitar, program: 31,
                tags: ["harmonics", "electric", "bell", "ethereal"],
                desc: "Flageoletter med klocklikt skimmer."),

        // MARK: Bass
        melodic("bass_upright", "Upright Bass", .bass, program: 32,
                tags: ["acoustic", "double bass", "jazz", "woody", "bass"],
                desc: "Akustisk kontrabas med träig kropp och varm botten."),
        melodic("bass_finger", "Finger Bass", .bass, program: 33,
                tags: ["electric", "warm", "groove", "funk", "bass", "soft"],
                desc: "Fingerspelad elbas med rund och fyllig ton för alla stilar."),
        melodic("bass_picked", "Picked Bass", .bass, program: 34,
                tags: ["electric", "attack", "rock", "bass", "bright"],
                desc: "Plektrumspelad elbas med tydlig attack och definition."),
        melodic("bass_fretless", "Fretless Bass", .bass, program: 35,
                tags: ["smooth", "jazz", "fusion", "mwah", "bass"],
                desc: "Bandlös elbas med karaktäristiskt sjungande sustain."),
        melodic("bass_slap", "Slap Bass", .bass, program: 36,
                tags: ["funk", "slap", "thumb", "pop", "bass", "punch"],
                desc: "Klassisk perkussiv slap-bas med tumslag och snärt."),
        melodic("bass_pop_slap", "Pop Slap Bass", .bass, program: 37,
                tags: ["funk", "bright", "slap", "pop", "bass"],
                desc: "Snärtig slap-bas med framhävd diskant."),

        // MARK: Synth Bass
        melodic("synbass_resonant", "Resonant Synth Bass", .synthBass, program: 38,
                tags: ["synth", "bass", "moog", "analog", "punch", "resonant", "electro"],
                desc: "Analog synthbas med resonant filter och kraftfull botten."),
        melodic("synbass_warm", "Warm Synth Bass", .synthBass, program: 39,
                tags: ["synth", "bass", "warm", "80s", "dance", "sub", "analog"],
                desc: "Varm och fyllig 80-tals synthbas med mjuk subbas."),

        // MARK: Strings
        melodic("str_violin", "Violin", .strings, program: 40,
                tags: ["solo", "bowed", "classical", "strings", "expressive"],
                desc: "Soloviolin med uttrycksfull vibrato."),
        melodic("str_viola", "Viola", .strings, program: 41,
                tags: ["solo", "warm", "classical", "strings"],
                desc: "Altfiol med fyllig mellanregisterklang."),
        melodic("str_cello", "Cello", .strings, program: 42,
                tags: ["solo", "deep", "classical", "warm", "strings", "soft"],
                desc: "Solocello med varm, djup och sjungande ton."),
        melodic("str_contrabass", "Contrabass", .strings, program: 43,
                tags: ["solo", "orchestral", "low", "strings"],
                desc: "Stråkad kontrabas med djup orkesterbotten."),
        melodic("str_tremolo", "Tremolo Strings", .strings, program: 44,
                tags: ["suspense", "orchestral", "cinematic", "tremolo"],
                desc: "Spännande och filmisk tremolo-stråksektion."),
        melodic("str_pizzicato", "Pizzicato Strings", .strings, program: 45,
                tags: ["plucked", "short", "orchestral", "playful", "staccato"],
                desc: "Knäppta stråkar med lekfull staccatoklang."),
        melodic("str_harp", "Concert Harp", .strings, program: 46,
                tags: ["harp", "plucked", "classical", "gentle", "soft"],
                desc: "Klassisk konsertharpa med skimrande klang."),
        melodic("str_ensemble", "String Ensemble", .strings, program: 48,
                tags: ["orchestral", "strings", "cinematic", "legato", "warm", "soft"],
                desc: "Full symfonisk stråksektion med varm och bred stereobild."),
        melodic("str_slow", "Slow Strings", .strings, program: 49,
                tags: ["pad", "slow", "ambient", "soft", "warm", "orchestral"],
                desc: "Långsamt svällande stråkar för stämningsfulla melodier."),
        melodic("str_synth", "Synth Strings", .strings, program: 50,
                tags: ["80s", "analog", "vintage", "pad", "warm", "strings"],
                desc: "Klassiska analoga 80-tals syntstråkar."),
        melodic("str_analog", "Analog Strings", .strings, program: 51,
                tags: ["pad", "lush", "filter", "80s", "retro"],
                desc: "Breda retrostråkar med svagt filter-svep."),

        // MARK: Choir
        melodic("choir_aahs", "Choir Aahs", .choir, program: 52,
                tags: ["voice", "vocal", "choral", "majestic", "choir"],
                desc: "Klassisk kör med öppna vokaler."),
        melodic("choir_oohs", "Voice Oohs", .choir, program: 53,
                tags: ["vocal", "soft", "ambient", "gentle", "choir"],
                desc: "Mjuk och intim röstklang för bakgrunder."),
        melodic("choir_synth", "Synth Choir", .choir, program: 54,
                tags: ["vocoder", "ambient", "ethereal", "80s", "space"],
                desc: "Eterisk syntetisk röstpad i 80-talsstil."),

        // MARK: Brass
        melodic("brass_trumpet", "Trumpet", .brass, program: 56,
                tags: ["brass", "lead", "bright", "jazz", "fanfare"],
                desc: "Klar och distinkt solotrumpet."),
        melodic("brass_trombone", "Trombone", .brass, program: 57,
                tags: ["brass", "warm", "orchestral", "jazz"],
                desc: "Fyllig trombon med varm orkesterklang."),
        melodic("brass_tuba", "Tuba", .brass, program: 58,
                tags: ["brass", "deep", "low", "orchestral"],
                desc: "Djup bastuba för orkesterfundament."),
        melodic("brass_muted_trumpet", "Muted Trumpet", .brass, program: 59,
                tags: ["miles", "jazz", "brass", "harmon", "vintage"],
                desc: "Dämpad trumpet i klassisk cool jazz-stil."),
        melodic("brass_french_horn", "French Horn", .brass, program: 60,
                tags: ["orchestral", "cinematic", "warm", "brass", "horn"],
                desc: "Filmiskt valthorn med mjuk och majestätisk ton."),
        melodic("brass_section", "Brass Section", .brass, program: 61,
                tags: ["horn", "brass", "fanfare", "funk", "punchy"],
                desc: "Tajt blåsarsektion med kraftfull dynamik."),
        melodic("brass_synth", "Synth Brass", .brass, program: 62,
                tags: ["80s", "jump", "analog", "punchy", "synth", "brass"],
                desc: "Klassiskt 80-tals syntblås med punchigt anslag."),
        melodic("brass_warm_synth", "Warm Synth Brass", .brass, program: 63,
                tags: ["analog", "filter", "vintage", "pad", "warm", "brass"],
                desc: "Mjukt analogt syntblås med filtrerad ton."),

        // MARK: Woodwinds
        melodic("ww_soprano_sax", "Soprano Sax", .woodwinds, program: 64,
                tags: ["woodwind", "reed", "jazz", "sax"],
                desc: "Sopransaxofon med ljus och lyrisk stämma."),
        melodic("ww_alto_sax", "Alto Sax", .woodwinds, program: 65,
                tags: ["woodwind", "reed", "jazz", "blues", "sax"],
                desc: "Klassisk altsaxofon för jazz, pop och solo."),
        melodic("ww_tenor_sax", "Tenor Sax", .woodwinds, program: 66,
                tags: ["woodwind", "reed", "rock", "jazz", "sax", "warm"],
                desc: "Varm och fyllig tenorsaxofon."),
        melodic("ww_baritone_sax", "Baritone Sax", .woodwinds, program: 67,
                tags: ["woodwind", "reed", "deep", "funk", "sax"],
                desc: "Djup barytonsaxofon med kraftfull attack."),
        melodic("ww_oboe", "Oboe", .woodwinds, program: 68,
                tags: ["woodwind", "classical", "expressive", "reed"],
                desc: "Soloboe med resonant dubbelrörsklang."),
        melodic("ww_english_horn", "English Horn", .woodwinds, program: 69,
                tags: ["woodwind", "warm", "melancholy", "reed"],
                desc: "Engelskt horn med vemodig och varm ton."),
        melodic("ww_bassoon", "Bassoon", .woodwinds, program: 70,
                tags: ["woodwind", "deep", "orchestral", "bass"],
                desc: "Fagott med karaktäristisk bas- och mellanregisterton."),
        melodic("ww_clarinet", "Clarinet", .woodwinds, program: 71,
                tags: ["woodwind", "smooth", "classical", "jazz"],
                desc: "Klarinett med mjukt och runt register."),
        melodic("ww_piccolo", "Piccolo", .woodwinds, program: 72,
                tags: ["woodwind", "high", "bright", "flute"],
                desc: "Piccoloflöjt med skarp och hög stämma."),
        melodic("ww_flute", "Concert Flute", .woodwinds, program: 73,
                tags: ["woodwind", "soft", "airy", "classical", "flute"],
                desc: "Akustisk konsertflöjt med luftig ton."),
        melodic("ww_recorder", "Recorder", .woodwinds, program: 74,
                tags: ["woodwind", "vintage", "baroque", "blockflute"],
                desc: "Blockflöjt i renässans- och barocktradition."),
        melodic("ww_pan_flute", "Pan Flute", .woodwinds, program: 75,
                tags: ["ethnic", "breath", "ambient", "pan"],
                desc: "Panflöjt med mjuk andningskaraktär."),
        melodic("ww_shakuhachi", "Shakuhachi", .woodwinds, program: 77,
                tags: ["japanese", "breath", "ambient", "meditative"],
                desc: "Traditionell japansk bambuflöjt med meditationston."),
        melodic("ww_whistle", "Tin Whistle", .woodwinds, program: 78,
                tags: ["folk", "celtic", "airy", "whistle"],
                desc: "Irländsk tin whistle för snabba folkmelodier."),
        melodic("ww_ocarina", "Ocarina", .woodwinds, program: 79,
                tags: ["woodwind", "pure", "zelda", "folk"],
                desc: "Lergök/ocarina med ren och klar visselton."),

        // MARK: Synth Lead
        melodic("lead_square", "Square Lead", .synthLead, program: 80,
                tags: ["chiptune", "retro", "8bit", "sharp", "lead", "synth"],
                desc: "Klassisk fyrkantsvåg för chiptune, 8-bit och arkadleds."),
        melodic("lead_saw", "Saw Lead", .synthLead, program: 81,
                tags: ["analog", "bright", "dance", "synth", "lead", "80s"],
                desc: "Kraftfull sågtandsled för dansmusik och synthwave."),
        melodic("lead_calliope", "Calliope Lead", .synthLead, program: 82,
                tags: ["chiff", "whistle", "retro", "fairground"],
                desc: "Visslande ångorgelsynt med vintage-känsla."),
        melodic("lead_chiff", "Chiff Lead", .synthLead, program: 83,
                tags: ["attack", "airy", "vintage", "synth"],
                desc: "Syntled med luftig attack och distinkt transient."),
        melodic("lead_charang", "Charang Lead", .synthLead, program: 84,
                tags: ["guitar-like", "sharp", "drive", "rock"],
                desc: "Gitarrliknande syntled med distorsionskaraktär."),
        melodic("lead_voice", "Voice Lead", .synthLead, program: 85,
                tags: ["vocal", "synth", "smooth", "soft"],
                desc: "Mjuk sångliknande synthled."),
        melodic("lead_fifths", "Fifths Lead", .synthLead, program: 86,
                tags: ["interval", "harmony", "power", "lead"],
                desc: "Parallell kvintled för maffiga rymdmelodier."),
        melodic("lead_bass_and_lead", "Bass & Lead", .synthLead, program: 87,
                tags: ["heavy", "dual", "electro", "punch"],
                desc: "Kombinerad bas och sololjud i ett och samma ljud."),

        // MARK: Synth Pad
        melodic("pad_new_age", "New Age Pad", .synthPad, program: 88,
                tags: ["ambient", "ethereal", "soft", "meditative", "warm", "pad"],
                desc: "Lugnande och eterisk new age-pad."),
        melodic("pad_warm", "Warm Pad", .synthPad, program: 89,
                tags: ["warm", "soft", "lush", "analog", "ambient", "pad"],
                desc: "Bred analog pad med fylligt filter och sammetslen värme."),
        melodic("pad_polysynth", "Polysynth Pad", .synthPad, program: 90,
                tags: ["80s", "bright", "analog", "chorus", "pad"],
                desc: "Klassisk 80-tals polyfonisk pad med chorusglans."),
        melodic("pad_choir", "Space Choir Pad", .synthPad, program: 91,
                tags: ["choir", "space", "pad", "ambient", "ethereal"],
                desc: "Rymdkör-pad för storslagna kosmiska harmonier."),
        melodic("pad_bowed", "Bowed Glass Pad", .synthPad, program: 92,
                tags: ["glass", "slow", "mystical", "pad", "ambient"],
                desc: "Mystisk pad med klang av stråkat kristallglas."),
        melodic("pad_metallic", "Metallic Pad", .synthPad, program: 93,
                tags: ["bell", "sheen", "digital", "fm", "pad"],
                desc: "Skimrande metallisk digitalpad."),
        melodic("pad_halo", "Halo Pad", .synthPad, program: 94,
                tags: ["reverb", "sacred", "ambient", "soft", "pad"],
                desc: "Luftig och sakral pad omgiven av generös rymd."),
        melodic("pad_sweep", "Sweep Pad", .synthPad, program: 95,
                tags: ["filter", "sweep", "motion", "analog", "pad"],
                desc: "Svepande analogpad med mjuk filterrörelse."),

        // MARK: Pluck
        melodic("pluck_sitar", "Sitar", .pluck, program: 104,
                tags: ["indian", "drone", "plucked", "world", "sitar"],
                desc: "Klassisk indisk sitar med resonanssträngar."),
        melodic("pluck_banjo", "Banjo", .pluck, program: 105,
                tags: ["bluegrass", "folk", "plucked", "country", "banjo"],
                desc: "Snabb och resonant 5-strängad banjo."),
        melodic("pluck_shamisen", "Shamisen", .pluck, program: 106,
                tags: ["japanese", "percussive", "plucked", "shamisen"],
                desc: "Japansk tresträngad luta med perkussivt anslag."),
        melodic("pluck_koto", "Koto", .pluck, program: 107,
                tags: ["japanese", "traditional", "harp", "plucked"],
                desc: "Traditionell japansk koto med graciös ton."),
        melodic("pluck_kalimba", "Kalimba", .pluck, program: 108,
                tags: ["thumb piano", "african", "bell", "plucked", "gentle"],
                desc: "Afrikanskt tumpiano med mjuk metallisk klang."),
        melodic("pluck_fiddle", "Fiddle", .pluck, program: 110,
                tags: ["folk", "celtic", "country", "fiddle"],
                desc: "Folkmusikfiol med rustik och levande klang."),

        // MARK: Mallets
        melodic("mallet_celesta", "Celesta", .mallets, program: 8,
                tags: ["bell", "magical", "orchestral", "celesta"],
                desc: "Klockspel i pianomekanik med sagolik klang."),
        melodic("mallet_glockenspiel", "Glockenspiel", .mallets, program: 9,
                tags: ["bell", "metallic", "bright", "orchestral"],
                desc: "Ljusa metallstavar med kristallklart anslag."),
        melodic("mallet_music_box", "Music Box", .mallets, program: 10,
                tags: ["toy", "vintage", "gentle", "bell", "soft"],
                desc: "Speldosa med charmig och nostalgisk mekanik."),
        melodic("mallet_vibraphone", "Vibraphone", .mallets, program: 11,
                tags: ["jazz", "warm", "motor", "tremolo", "vibes"],
                desc: "Jazzvibrafon med varm motordriven tremolo."),
        melodic("mallet_marimba", "Marimba", .mallets, program: 12,
                tags: ["wooden", "warm", "percussive", "marimba", "soft"],
                desc: "Djupa trästavar med fyllig resonans."),
        melodic("mallet_xylophone", "Xylophone", .mallets, program: 13,
                tags: ["wooden", "sharp", "orchestral", "staccato"],
                desc: "Ljusa och skarpa trästavar med snabbt utdöende."),
        melodic("mallet_tubular_bells", "Tubular Bells", .mallets, program: 14,
                tags: ["chimes", "cathedral", "church", "bell", "majestic"],
                desc: "Klassiska orkesterrörklockor för fest och dramatik."),
        melodic("mallet_dulcimer", "Dulcimer", .mallets, program: 15,
                tags: ["hammered", "folk", "acoustic", "strings"],
                desc: "Stränginstrument spelat med små trähammare."),
        melodic("mallet_steel_drums", "Steel Drums", .mallets, program: 114,
                tags: ["caribbean", "tropical", "island", "steelpan"],
                desc: "Västindiska oljefatsfat med karaktäristisk feststämning."),

        // MARK: Drums (Percussion Bank 120, MIDI Channel 9 / index 10)
        drumKit("drums_acoustic", "Acoustic Kit", program: 0,
                tags: ["acoustic", "rock", "pop", "standard", "natural"],
                desc: "Mångsidigt akustiskt trumset för rock, pop och jazz."),
        drumKit("drums_room", "Room Kit", program: 8,
                tags: ["room", "ambient", "rock", "live"],
                desc: "Akustiskt trumset med naturlig rumsklang."),
        drumKit("drums_power", "Power Kit", program: 16,
                tags: ["heavy", "power", "gated", "80s", "rock"],
                desc: "Kraftfullt 80-tals trumset med komprimerad klang."),
        drumKit("drums_electronic", "Electronic Kit", program: 24,
                tags: ["electronic", "synth", "dance", "techno"],
                desc: "Elektroniskt trumset för synthpop och dansmusik."),
        drumKit("drums_tr808", "TR-808 Kit", program: 25,
                tags: ["808", "hiphop", "trap", "vintage", "electro"],
                desc: "Legendarisk analog trummaskin med djup sub-kick och distinkt virvel."),
        drumKit("drums_jazz", "Jazz Kit", program: 32,
                tags: ["jazz", "swing", "warm", "bop"],
                desc: "Akustiskt jazztrumset med stämd bastrumma och dynamiska cymbaler."),
        drumKit("drums_brush", "Brush Kit", program: 40,
                tags: ["brush", "ballad", "jazz", "soft"],
                desc: "Visptrumpaket för intima ballader och jazz."),
        drumKit("drums_orchestral", "Orchestra Kit", program: 48,
                tags: ["classical", "timpani", "cymbals", "concert"],
                desc: "Klassiska konserttrummor och bäcknar för symfoniska verk."),

        // MARK: Percussion
        melodic("perc_timpani", "Timpani", .percussion, program: 47,
                tags: ["kettle drum", "orchestral", "dramatic", "classical"],
                desc: "Stämda pukor för orkestrala crescendon och accenter."),
        melodic("perc_woodblock", "Woodblock", .percussion, program: 115,
                tags: ["percussion", "wooden", "click", "short"],
                desc: "Träblock med torr och exakt perkussiv klang."),
        melodic("perc_taiko", "Taiko Drum", .percussion, program: 116,
                tags: ["japanese", "heavy", "percussion", "cinematic", "power"],
                desc: "Japansk stor trumma med dånande kraft."),
        melodic("perc_melodic_tom", "Melodic Tom", .percussion, program: 117,
                tags: ["tom", "synthesizer", "percussion", "electronic"],
                desc: "Stämbar syntetisk pukklang."),
        melodic("perc_synth_drum", "Synth Drum", .percussion, program: 118,
                tags: ["electronic", "80s", "percussion", "disco"],
                desc: "Klassisk 80-tals syndrum med tonfall."),
        melodic("perc_reverse_cymbal", "Reverse Cymbal", .percussion, program: 119,
                tags: ["fx", "transition", "riser", "cymbal"],
                desc: "Omvänd cymbal för svepande övergångar och drops."),
        melodic("perc_tinkle_bell", "Tinkle Bell", .percussion, program: 112,
                tags: ["bell", "percussion", "high", "bright"],
                desc: "Liten ljus bjällra med kort ton."),
        melodic("perc_agogo", "Agogo", .percussion, program: 113,
                tags: ["latin", "bell", "samba", "brazil"],
                desc: "Brasiliansk dubbelklocka för sambarytmer."),

        // MARK: FX
        melodic("fx_orchestra_hit", "Orchestra Hit", .fx, program: 55,
                tags: ["80s", "hit", "retro", "stab", "dramatic"],
                desc: "Ikonisk 80-tals orkesterstöt för accenter."),
        melodic("fx_rain", "Rain FX", .fx, program: 96,
                tags: ["nature", "weather", "ambient", "sfx", "rain"],
                desc: "Lugnande regnljud."),
        melodic("fx_soundtrack", "Soundtrack FX", .fx, program: 97,
                tags: ["cinematic", "pad", "evolving", "ambient"],
                desc: "Filmiskt ljudelement med långsam klangfärg."),
        melodic("fx_crystal", "Crystal FX", .fx, program: 98,
                tags: ["sparkle", "bell", "magical", "crystal"],
                desc: "Magiskt skimrande kristalljud."),
        melodic("fx_atmosphere", "Atmosphere FX", .fx, program: 99,
                tags: ["ambient", "sci-fi", "drone", "space"],
                desc: "Djupt atmosfäriskt bakgrundsbrus."),
        melodic("fx_scifi", "Sci-Fi FX", .fx, program: 103,
                tags: ["alien", "space", "laser", "futuristic"],
                desc: "Futuristiskt syntljud för science fiction."),
        melodic("fx_seashore", "Seashore FX", .fx, program: 122,
                tags: ["ocean", "waves", "nature", "ambient"],
                desc: "Vågskvalp mot strand."),
        melodic("fx_bird", "Bird Tweet FX", .fx, program: 123,
                tags: ["nature", "birds", "outdoor", "forest"],
                desc: "Naturtroget fågelkvitter."),
        melodic("fx_phone", "Telephone Ring FX", .fx, program: 124,
                tags: ["retro", "vintage", "phone", "sfx"],
                desc: "Klassisk analog telefonsignal."),
        melodic("fx_helicopter", "Helicopter FX", .fx, program: 125,
                tags: ["chopper", "motor", "sfx", "military"],
                desc: "Roterande helikopterblad."),
        melodic("fx_applause", "Applause FX", .fx, program: 126,
                tags: ["clapping", "crowd", "cheer", "live"],
                desc: "Publikens applåder och jubel."),
        melodic("fx_gunshot", "Gunshot FX", .fx, program: 127,
                tags: ["explosion", "shot", "military", "action"],
                desc: "Kraftfullt pistolskott.")
    ]

    /// Surge XT is the built-in library for this fork. The legacy General MIDI
    /// table remains private only so old project files can still be identified.
    public static let all: [InstrumentDefinition] = SurgePresetCatalog.all

    public static var availableCategories: [InstrumentCategory] {
        InstrumentCategory.allCases.filter { category in all.contains { $0.category == category } }
    }

    /// Hämta instrument i en viss kategori.
    public static func inCategory(_ cat: InstrumentCategory) -> [InstrumentDefinition] {
        all.filter { $0.category == cat }
    }

    /// Sök i hela katalogen med fritext.
    public static func search(_ query: String) -> [InstrumentDefinition] {
        all.filter { $0.matches(query: query) }
    }

    /// Hitta instrument efter dess ID.
    public static func find(id: String) -> InstrumentDefinition? {
        all.first { $0.id == id }
    }

    /// Hitta instrument efter dess GM-egenskaper.
    public static func find(program: UInt8, isDrumKit: Bool) -> InstrumentDefinition? {
        all.first { $0.program == program && $0.isDrumKit == isDrumKit }
    }
}
