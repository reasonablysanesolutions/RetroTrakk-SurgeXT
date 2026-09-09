import Foundation

/// Factory presets shipped with Surge XT.  IDs and stored paths are relative to
/// `patches_factory`, so a song stays portable when RetroTrakk is moved.
public enum SurgePresetCatalog {
    private static let factoryDirectory = "patches_factory"

    public static let all: [InstrumentDefinition] = {
        guard let root = factoryRootURL() else { return [] }
        let fm = FileManager.default
        guard let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var presets: [InstrumentDefinition] = []
        for case let url as URL in files where url.pathExtension.lowercased() == "fxp" {
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let folder = url.deletingLastPathComponent().lastPathComponent
            let display = url.deletingPathExtension().lastPathComponent
            presets.append(InstrumentDefinition(
                id: "surge/" + relative,
                displayName: display,
                category: category(for: folder),
                tags: ["surge xt", folder.lowercased(), display.lowercased()],
                description: "Surge XT factory preset · " + folder,
                sourceType: .surge,
                sourceIdentifier: relative
            ))
        }
        return presets.sorted {
            $0.category.rawValue == $1.category.rawValue
                ? $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                : $0.category.rawValue.localizedStandardCompare($1.category.rawValue) == .orderedAscending
        }
    }()

    public static func patchURL(relativePath: String) -> URL? {
        factoryRootURL()?.appendingPathComponent(relativePath)
    }

    private static func factoryRootURL() -> URL? {
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("data", isDirectory: true)
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

    private static func category(for folder: String) -> InstrumentCategory {
        switch folder.lowercased() {
        case "basses": return .synthBass
        case "leads": return .synthLead
        case "pads": return .synthPad
        case "keys", "organs": return .keys
        case "plucks": return .pluck
        case "drums", "percussion": return .drums
        case "strings": return .strings
        case "brass": return .brass
        case "fx", "effects": return .fx
        default: return .keys
        }
    }
}
