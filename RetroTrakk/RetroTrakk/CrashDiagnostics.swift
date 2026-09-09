import AppKit
import Foundation

/// A persistent, local diagnostic journal. macOS writes native crash reports
/// after a process exits; the next app launch imports the latest RetroTrakk
/// report so both the timeline leading up to a crash and the actual crash
/// signature live in one place.
final class CrashDiagnostics {
    static let shared = CrashDiagnostics()

    private let queue = DispatchQueue(label: "RetroTrakk.crashDiagnostics")
    private let fileManager = FileManager.default
    private let importedReportKey = "RetroTrakk.lastImportedCrashReport"

    private init() {}

    static func install() { shared.install() }

    static var logDirectoryURL: URL { shared.logDirectoryURL }

    static func openLogDirectory() {
        NSWorkspace.shared.open(logDirectoryURL)
    }

    func record(_ message: String) {
        queue.async { self.append(message) }
    }

    private func install() {
        queue.sync {
            ensureLogDirectory()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            append("=== Session started | app \(version) (\(build)) ===")
            importLatestMacOSCrashReport()
        }
        NSSetUncaughtExceptionHandler { exception in
            CrashDiagnostics.shared.record("UNCAUGHT NSException: \(exception.name.rawValue) | \(exception.reason ?? "no reason")")
        }
    }

    private var logDirectoryURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: "/tmp")
        return base.appendingPathComponent("RetroTrakk/Diagnostics", isDirectory: true)
    }

    private var logURL: URL {
        logDirectoryURL.appendingPathComponent("retrotrakk.log")
    }

    private func ensureLogDirectory() {
        try? fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
    }

    private func append(_ message: String) {
        ensureLogDirectory()
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = ("[\(stamp)] \(message)\n").data(using: .utf8) else { return }
        if fileManager.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    private func importLatestMacOSCrashReport() {
        let reports = URL(fileURLWithPath: "/Users/jimmy/Library/Logs/DiagnosticReports", isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: reports, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return }
        let latest = files
            .filter { $0.lastPathComponent.hasPrefix("RetroTrakk-") && $0.pathExtension == "ips" }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            .first
        guard let latest else { return }
        let marker = latest.lastPathComponent
        guard UserDefaults.standard.string(forKey: importedReportKey) != marker,
              let report = try? String(contentsOf: latest, encoding: .utf8) else { return }

        let signature = report
            .split(whereSeparator: \.isNewline)
            .prefix(3)
            .joined(separator: " ")
        append("IMPORTED macOS crash report \(marker): \(signature.prefix(12_000))")
        UserDefaults.standard.set(marker, forKey: importedReportKey)
    }
}
