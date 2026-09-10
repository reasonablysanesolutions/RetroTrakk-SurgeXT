import Foundation

/// Surge XT:s kompletta gratisbibliotek: factory presets, den medföljande
/// tredjepartsbanken (`patches_3rdparty`, 37 författare) samt kurerade
/// användarpack (SU-NO-XT, DanAn, New Loops, Phasor Space). IDs och lagrade
/// sökvägar är relativa per rot (`surge/…`, `surge3rd/…`, `surge-user/…`),
/// så en låt förblir portabel när RetroTrakk flyttas.
public enum SurgePresetCatalog {
    private static let factoryDirectory = "patches_factory"
    private static let thirdPartyDirectory = "patches_3rdparty"
    private static let userDirectory = "SurgeUserPatches"

    public static let all: [InstrumentDefinition] = {
        let presets = (factoryPresets + thirdPartyPresets + userPresets).sorted {
            $0.category.rawValue == $1.category.rawValue
                ? $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                : $0.category.rawValue.localizedStandardCompare($1.category.rawValue) == .orderedAscending
        }
        return presets
    }()

    /// Surge XT:s egen tredjepartsbank (community-presets som följer med Surge).
    public static let thirdPartyPresets: [InstrumentDefinition] = {
        guard let root = thirdPartyRootURL() else { return [] }
        return scan(root: root, idPrefix: "surge3rd/", namespaced: true)
    }()

    /// Kuraterade tredjepartspack — ersätter aldrig factory-ljud.
    public static let userPresets: [InstrumentDefinition] = {
        guard let root = userRootURL() else { return [] }
        return scan(root: root, idPrefix: "surge-user/", namespaced: true)
    }()

    private static let factoryPresets: [InstrumentDefinition] = {
        guard let root = factoryRootURL() else { return [] }
        return scan(root: root, idPrefix: "surge/", namespaced: false)
    }()

    private static func scan(root: URL, idPrefix: String, namespaced: Bool) -> [InstrumentDefinition] {
        let fm = FileManager.default
        guard let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var presets: [InstrumentDefinition] = []
        for case let url as URL in files where url.pathExtension.lowercased() == "fxp" {
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let folder = url.deletingLastPathComponent().lastPathComponent
            let display = url.deletingPathExtension().lastPathComponent
            // Namngiven rot (författare/pack) blir första sökvägskomponenten,
            // t.ex. "Cybersoda/Pads/Lush.fxp" eller "DanAn/Pads/80s Pad.fxp".
            let pack = namespaced ? prettyPackName(relative) : nil
            var tags = ["surge xt", folder.lowercased(), display.lowercased()]
            if let pack { tags.append(pack.lowercased()) }
            presets.append(InstrumentDefinition(
                id: idPrefix + relative,
                displayName: display,
                category: category(for: folder),
                tags: tags,
                description: pack.map { $0 + " · " + folder } ?? "Surge XT factory preset · " + folder,
                sourceType: .surge,
                sourceIdentifier: relative
            ))
        }
        return presets
    }

    /// Första sökvägskomponenten ("Cybersoda", "DanAn"…) som visningsnamn.
    private static func prettyPackName(_ relative: String) -> String? {
        guard relative.split(separator: "/").count > 1,
              let first = relative.split(separator: "/").first else { return nil }
        let name = String(first).replacingOccurrences(of: "-", with: " ")
        return name.isEmpty ? nil : name
    }

    public static func patchURL(relativePath: String) -> URL? {
        let fm = FileManager.default
        if let factory = factoryRootURL()?.appendingPathComponent(relativePath),
           fm.fileExists(atPath: factory.path) {
            return factory
        }
        if let thirdParty = thirdPartyRootURL()?.appendingPathComponent(relativePath),
           fm.fileExists(atPath: thirdParty.path) {
            return thirdParty
        }
        if let user = userRootURL()?.appendingPathComponent(relativePath),
           fm.fileExists(atPath: user.path) {
            return user
        }
        return nil
    }

    private static func factoryRootURL() -> URL? {
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("SurgeData", isDirectory: true)
            .appendingPathComponent(factoryDirectory, isDirectory: true),
            FileManager.default.fileExists(atPath: resource.path) {
            return resource
        }
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let checkout = current.lastPathComponent == "RetroTrakk" ? current.deletingLastPathComponent() : current
        let source = checkout.appendingPathComponent("Vendor/surge/resources/data/" + factoryDirectory, isDirectory: true)
        if FileManager.default.fileExists(atPath: source.path) { return source }
        return nil
    }

    /// Tredjepartsbanken: buntade `patches_3rdparty` i appen (via Vendor-
    /// submodulen, ej kopierad), annars `Vendor/surge/resources/data`
    /// i utcheckningen.
    private static func thirdPartyRootURL() -> URL? {
        if let resource = Bundle.main.resourceURL?.appendingPathComponent(thirdPartyDirectory, isDirectory: true),
           FileManager.default.fileExists(atPath: resource.path) {
            return resource
        }
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let checkout = current.lastPathComponent == "RetroTrakk" ? current.deletingLastPathComponent() : current
        let vendored = checkout.appendingPathComponent("Vendor/surge/resources/data/" + thirdPartyDirectory, isDirectory: true)
        if FileManager.default.fileExists(atPath: vendored.path) { return vendored }
        let copied = checkout.appendingPathComponent("RetroTrakk/Resources/SurgeData/" + thirdPartyDirectory, isDirectory: true)
        if FileManager.default.fileExists(atPath: copied.path) { return copied }
        return nil
    }

    /// Tredjepartspack: buntade `SurgeUserPatches` i appen, annars katalogen
    /// `RetroTrakk/Resources/SurgeUserPatches` i utcheckningen (ej i git).
    private static func userRootURL() -> URL? {
        if let resource = Bundle.main.resourceURL?.appendingPathComponent(userDirectory, isDirectory: true),
           FileManager.default.fileExists(atPath: resource.path) {
            return resource
        }
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let checkout = current.lastPathComponent == "RetroTrakk" ? current.deletingLastPathComponent() : current
        let source = checkout.appendingPathComponent("RetroTrakk/Resources/" + userDirectory, isDirectory: true)
        if FileManager.default.fileExists(atPath: source.path) { return source }
        return nil
    }

    private static func category(for folder: String) -> InstrumentCategory {
        switch folder.lowercased() {
        case "basses", "bass": return .synthBass
        case "leads", "lead": return .synthLead
        case "pads", "pad": return .synthPad
        case "keys", "key", "chords", "polysynths", "synths", "misc", "juno",
             "mpe", "splits", "templates", "tutorials", "vocoder",
             "modelled", "audio in":
            return .keys
        case "organs": return .organ
        case "guitar", "guitars": return .guitar
        case "plucks", "pluck": return .pluck
        case "drums", "drum", "percussion": return .drums
        case "strings", "string": return .strings
        case "brass": return .brass
        case "winds", "woodwinds": return .woodwinds
        case "bells", "bell", "mallets": return .mallets
        case "vox", "voices", "vocals": return .choir
        case "atmosphere", "atmospheres", "ambiance", "ambiances",
             "soundscapes", "textures", "drones", "fx", "effects":
            return .fx
        case "sequence", "sequences", "arps", "rhythms", "rythmicsynths": return .sequence
        default: return .keys
        }
    }
}
