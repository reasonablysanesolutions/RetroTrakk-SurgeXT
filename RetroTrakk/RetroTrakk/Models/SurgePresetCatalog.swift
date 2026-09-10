import Foundation

/// Factory presets shipped with Surge XT plus curated third-party user packs
/// (SU-NO-XT, DanAn, New Loops, Phasor Space). IDs and stored paths are
/// relative to `patches_factory` (`surge/…`) or `SurgeUserPatches` (`surge-user/…`),
/// so a song stays portable when RetroTrakk is moved.
public enum SurgePresetCatalog {
    private static let factoryDirectory = "patches_factory"
    private static let userDirectory = "SurgeUserPatches"

    public static let all: [InstrumentDefinition] = {
        let presets = (factoryPresets + userPresets).sorted {
            $0.category.rawValue == $1.category.rawValue
                ? $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                : $0.category.rawValue.localizedStandardCompare($1.category.rawValue) == .orderedAscending
        }
        return presets
    }()

    /// Tredjepartspack ( AVLÄGSNAS aldrig factory-ljud; visas under egna kategorier).
    public static let userPresets: [InstrumentDefinition] = {
        guard let root = userRootURL() else { return [] }
        return scan(root: root, idPrefix: "surge-user/")
    }()

    private static let factoryPresets: [InstrumentDefinition] = {
        guard let root = factoryRootURL() else { return [] }
        return scan(root: root, idPrefix: "surge/")
    }()

    private static func scan(root: URL, idPrefix: String) -> [InstrumentDefinition] {
        let fm = FileManager.default
        guard let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var presets: [InstrumentDefinition] = []
        for case let url as URL in files where url.pathExtension.lowercased() == "fxp" {
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let folder = url.deletingLastPathComponent().lastPathComponent
            let display = url.deletingPathExtension().lastPathComponent
            let pack = idPrefix == "surge-user/" ? prettyPackName(relative) : nil
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

    /// Första sökvägskomponenten ("DanAn", "SU-NO-XT"…) som visningsnamn.
    private static func prettyPackName(_ relative: String) -> String? {
        guard let first = relative.split(separator: "/").first else { return nil }
        let name = String(first).replacingOccurrences(of: "-", with: " ")
        return name.isEmpty ? nil : name
    }

    public static func patchURL(relativePath: String) -> URL? {
        if let factory = factoryRootURL()?.appendingPathComponent(relativePath),
           FileManager.default.fileExists(atPath: factory.path) {
            return factory
        }
        if let user = userRootURL()?.appendingPathComponent(relativePath),
           FileManager.default.fileExists(atPath: user.path) {
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
        case "basses": return .synthBass
        case "leads": return .synthLead
        case "pads": return .synthPad
        case "keys", "chords", "polysynths", "misc", "juno",
             "mpe", "splits", "templates", "tutorials", "vocoder":
            return .keys
        case "organs": return .organ
        case "guitar": return .guitar
        case "plucks": return .pluck
        case "drums", "percussion": return .drums
        case "strings": return .strings
        case "brass": return .brass
        case "winds": return .woodwinds
        case "bells": return .mallets
        case "atmosphere", "fx", "effects": return .fx
        case "sequence", "sequences", "rythmicsynths": return .sequence
        default: return .keys
        }
    }
}
