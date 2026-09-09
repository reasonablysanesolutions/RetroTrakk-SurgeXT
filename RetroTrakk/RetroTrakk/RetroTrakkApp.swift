// RetroTrakk — RetroTrakkApp.swift

import SwiftUI

@main
struct RetroTrakkApp: App {
    @StateObject private var audio = RetroTrakkAudioEngine()
    @StateObject private var midi = MIDIEngine()
    @StateObject private var tracker = TrackerEngine()

    init() {
        CrashDiagnostics.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audio)
                .environmentObject(midi)
                .environmentObject(tracker)
                .frame(minWidth: 1100, minHeight: 700)
                .onAppear {
                    tracker.audio = audio
                    tracker.midi = midi
                    tracker.bindMIDI()
                    audio.start()
                    audio.rescanAUs()
                    audio.prewarm(song: tracker.song)
                }
                .onOpenURL { url in
                    do {
                        try tracker.openProject(from: url)
                    } catch {
                        audio.statusText = "Kunde inte öppna \(url.lastPathComponent): \(error.localizedDescription)"
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Om RetroTrakk") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        NSApplication.AboutPanelOptionKey(rawValue: "ApplicationName"): "RetroTrakk",
                        NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "RetroTrakk (C) 2026 Jimmy Granlund"
                    ])
                }
                Button("Open Source Licenses…") {
                    NotificationCenter.default.post(name: .retroLicenses, object: nil)
                }
                Button("Öppna diagnostikmapp") {
                    CrashDiagnostics.openLogDirectory()
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Nytt projekt") {
                    NotificationCenter.default.post(name: .retroNew, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Öppna projekt…") {
                    NotificationCenter.default.post(name: .retroOpen, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Spara projekt") {
                    NotificationCenter.default.post(name: .retroSave, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Spara som…") {
                    NotificationCenter.default.post(name: .retroSaveAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Klipp ut") {
                    tracker.cutSelection()
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Kopiera") {
                    tracker.copySelection()
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Klistra in") {
                    tracker.paste()
                }
                .keyboardShortcut("v", modifiers: .command)

                Divider()

                Button("Markera allt") {
                    tracker.selectAll()
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Ta bort") {
                    tracker.deleteSelectionOrCell()
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
        }
    }
}

extension Notification.Name {
    static let retroNew = Notification.Name("retroNew")
    static let retroSave = Notification.Name("retroSave")
    static let retroSaveAs = Notification.Name("retroSaveAs")
    static let retroOpen = Notification.Name("retroOpen")
    static let retroLicenses = Notification.Name("retroLicenses")
}
