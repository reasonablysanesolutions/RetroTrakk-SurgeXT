// RetroTrakk — ContentView.swift
// Huvudfönster: toolbar, instrument-lista vänster, tracker mitten, order-lista höger.

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var tracker: TrackerEngine
    @EnvironmentObject var audio: RetroTrakkAudioEngine
    @EnvironmentObject var midi: MIDIEngine

    @State private var showInstrumentPicker = false
    @State private var showLicenses = false
    @State private var statusMessage = "Välj ett instrument, skriv noter, tryck Play."

    var body: some View {
        VStack(spacing: 0) {
            TransportBar(statusMessage: $statusMessage)
            Divider()
            HStack(spacing: 0) {
                InstrumentSidebar(showPicker: $showInstrumentPicker)
                    .frame(width: 280)
                Divider()
                TrackerView()
                    .environmentObject(tracker)
                    .frame(minWidth: 760)
                Divider()
                OrderSidebar()
                    .environmentObject(tracker)
                    .frame(width: 230)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            StatusBar(message: statusMessage)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("RetroTrakk — \(tracker.projectTitle)")
        .sheet(isPresented: $showInstrumentPicker) {
            InstrumentBrowser()
                .environmentObject(tracker)
                .environmentObject(audio)
                .frame(minWidth: 560, minHeight: 480)
        }
        .sheet(isPresented: $showLicenses) {
            OpenSourceLicensesView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .retroNew)) { _ in
            tracker.newProject()
            statusMessage = "Nytt tomt projekt skapat."
        }
        .onReceive(NotificationCenter.default.publisher(for: .retroSave)) { _ in
            handleSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: .retroSaveAs)) { _ in
            handleSaveAs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .retroOpen)) { _ in
            handleOpen()
        }
        .onReceive(NotificationCenter.default.publisher(for: .retroLicenses)) { _ in
            showLicenses = true
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Nytt") {
                    tracker.newProject()
                    statusMessage = "Nytt tomt projekt skapat."
                }
                .help("Nytt tomt projekt (Cmd+N)")

                Button("Öppna") { handleOpen() }
                    .help("Öppna projekt… (Cmd+O)")

                Button("Spara") { handleSave() }
                    .help("Spara projekt (Cmd+S)")

                Button("Rendera WAV") { handleRenderWAV() }
                    .help("Rendera till WAV-fil")
            }
        }
    }

    private func handleSave() {
        do {
            if try tracker.quickSave() {
                statusMessage = "Sparade till \(tracker.currentProjectURL?.lastPathComponent ?? "projekt")"
            } else {
                handleSaveAs()
            }
        } catch {
            statusMessage = "Kunde inte spara: \(error.localizedDescription)"
        }
    }

    private func handleSaveAs() {
        let panel = NSSavePanel()
        panel.title = "Spara RetroTrakk-projekt"
        panel.prompt = "Spara"
        panel.canCreateDirectories = true
        if let jgxType = UTType(filenameExtension: "jgx") {
            panel.allowedContentTypes = [jgxType]
        }
        let baseName = tracker.projectTitle.replacingOccurrences(of: ".jgx", with: "")
        panel.nameFieldStringValue = "\(baseName).jgx"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try tracker.saveProject(to: url)
                statusMessage = "Sparade till \(url.lastPathComponent)"
            } catch {
                statusMessage = "Kunde inte spara: \(error.localizedDescription)"
            }
        }
    }

    private func handleOpen() {
        let panel = NSOpenPanel()
        panel.title = "Öppna RetroTrakk-projekt"
        panel.prompt = "Öppna"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let jgxType = UTType(filenameExtension: "jgx") {
            panel.allowedContentTypes = [jgxType, .json]
        } else {
            panel.allowedContentTypes = [.json]
        }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try tracker.openProject(from: url)
                statusMessage = "Öppnade \(url.lastPathComponent)"
            } catch {
                statusMessage = "Kunde inte öppna: \(error.localizedDescription)"
            }
        }
    }

    private func handleRenderWAV() {
        let panel = NSSavePanel()
        panel.title = "Rendera WAV"
        panel.prompt = "Rendera"
        panel.canCreateDirectories = true
        if let wavType = UTType(filenameExtension: "wav") {
            panel.allowedContentTypes = [wavType]
        }
        let baseName = tracker.projectTitle.replacingOccurrences(of: ".jgx", with: "")
        panel.nameFieldStringValue = "\(baseName).wav"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try audio.renderToWAV(song: tracker.song, url: url)
                statusMessage = "Renderade \(url.lastPathComponent)"
            } catch {
                statusMessage = "Render misslyckades: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Statusrad

struct StatusBar: View {
    @EnvironmentObject var tracker: TrackerEngine
    @EnvironmentObject var midi: MIDIEngine
    @ObservedObject private var waveform = WaveformManager.shared
    @EnvironmentObject var audio: RetroTrakkAudioEngine
    let message: String

    /// Synlig versionsstämpel — så man alltid kan se vilken build som körs.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(marketing) (\(build))"
    }

    var body: some View {
        HStack(spacing: 16) {
            Text("RetroTrakk \(Self.appVersion)")
                .font(.caption).bold().foregroundStyle(.secondary)
            Label(message, systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Label(midi.isConnected ? (midi.sources[safe: midi.selectedSource ?? -1] ?? "MIDI") : "Ingen MIDI",
                  systemImage: midi.isConnected ? "pianokeys" : "pianokeys.inverse")
                .font(.caption).foregroundStyle(.secondary)
            if tracker.isPlaying {
                Label(waveform.signalPeak > 0.001 ? String(format: "Signal %.3f", waveform.signalPeak) : "Ingen patternsignal",
                      systemImage: waveform.signalPeak > 0.001 ? "waveform" : "speaker.slash")
                    .font(.caption)
                    .foregroundStyle(waveform.signalPeak > 0.001 ? Color.green : Color.red)
            }
            Label(audio.statusText, systemImage: "speaker.wave.2")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}



struct WavPlaceholder: FileDocument {
    static var readableContentTypes: [UTType] { [.wav] }
    init() {}
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data())
    }
}
