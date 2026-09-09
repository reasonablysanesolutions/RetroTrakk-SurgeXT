// RetroTrakk — InstrumentBrowser.swift
// Bläddra Apple-AU:er + tredjepart + WAV/AIFF-samples. Skapa instrument till låten.

import SwiftUI
import UniformTypeIdentifiers

struct InstrumentBrowser: View {
    @EnvironmentObject var tracker: TrackerEngine
    @EnvironmentObject var audio: RetroTrakkAudioEngine
    @Environment(\.dismiss) var dismiss

    @State private var search = ""
    @State private var sampleImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lägg till instrument")
                    .font(.title2).bold()
                Spacer()
                Button("Stäng") { dismiss() }
            }
            TextField("Sök Audio Units…", text: $search)
                .textFieldStyle(.roundedBorder)

            TabView {
                InstalledSoundBrowser()
                    .tabItem { Label("GarageBand", systemImage: "pianokeys") }
                auList(title: "Apple", items: audio.availableAUs.filter {
                    $0.manufacturer == "Apple" && matches($0)
                })
                .tabItem { Label("Apple", systemImage: "apple.logo") }

                auList(title: "Tredjepart", items: audio.availableAUs.filter {
                    $0.manufacturer != "Apple" && matches($0)
                })
                .tabItem { Label("Tredjepart", systemImage: "puzzlepiece") }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sample (WAV / AIFF)")
                        .font(.headline)
                    Text("Ladda en WAV- eller AIFF-fil. Den mappas över klaviaturen via Apple AUSampler.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Välj WAV/AIFF-fil…") { sampleImporter = true }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .padding()
                .tabItem { Label("Sample", systemImage: "waveform") }
            }

            Text("GarageBand-fliken läser installerade ljudfiler. Audio Units listas separat.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color.white)
        .onAppear { audio.rescanAUs() }
        .fileImporter(isPresented: $sampleImporter, allowedContentTypes: [.wav, .aiff, .audio]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                addSample(url: url)
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private func matches(_ au: AUInfo) -> Bool {
        guard !search.isEmpty else { return true }
        return au.name.localizedCaseInsensitiveContains(search) ||
               au.manufacturer.localizedCaseInsensitiveContains(search)
    }

    private func auList(title: String, items: [AUInfo]) -> some View {
        VStack(alignment: .leading) {
            if items.isEmpty {
                Text(title == "Apple" ? "Inga Apple-instrument hittades." : "Inga tredjeparts-AU:er hittades. Installera ett AUv2/AUv3-instrument så dyker det upp här.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                List(items) { au in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(au.name).font(.body)
                            Text(au.manufacturer).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Lägg till") { addAU(au) }
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.top, 4)
    }

    private func addAU(_ au: AUInfo) {
        let newID = (tracker.song.instruments.map { $0.id }.max() ?? -1) + 1
        let kind: InstrumentKind = au.subtype == AudioUnitManager.dlsDescription().componentSubType ? .dls : .audioUnit
        let inst = InstrumentModel(id: newID, name: String(format: "%02d %@", newID + 1, au.name),
                                   kind: kind, auName: au.name, auManufacturer: au.manufacturer)
        tracker.song.instruments.append(inst)
        audio.ensureInstrument(inst)
        dismiss()
    }

    private func addSample(url: URL) {
        let newID = (tracker.song.instruments.map { $0.id }.max() ?? -1) + 1
        let inst = InstrumentModel(id: newID,
                                   name: String(format: "%02d %@", newID + 1, url.deletingPathExtension().lastPathComponent),
                                   kind: .sample, samplePath: url.path)
        tracker.song.instruments.append(inst)
        // Se till att noden finns, ladda sedan filen
        _ = audio.ensureInstrument(inst)
        audio.loadSample(into: inst, url: url)
        dismiss()
    }
}

/// The installed catalogue is separate from the generic General MIDI sounds.
/// Unsupported channel strips remain visible, with the actual limitation.
struct InstalledSoundBrowser: View {
    @EnvironmentObject var tracker: TrackerEngine
    @EnvironmentObject var audio: RetroTrakkAudioEngine
    @ObservedObject private var library = InstalledSoundLibrary.shared
    @State private var search = ""
    @State private var samplerOnly = true

    private var visible: [InstalledSound] {
        library.sounds.filter { sound in
            (!samplerOnly || sound.isSampler) && (search.isEmpty ||
                "\(sound.name) \(sound.category) \(sound.source)".localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Sök installerade ljud", text: $search).textFieldStyle(.roundedBorder)
                Button { library.scan(force: true) } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(library.scanning).help("Läs om ljudbiblioteket")
            }
            Toggle("Endast samplerinstrument", isOn: $samplerOnly).font(.caption)
                .help("Avmarkera för att även visa patchar som kräver GarageBands egna instrument och effekter.")
            Text(library.scanning ? "Läser ljudbiblioteket…" : library.scanMessage)
                .font(.caption2).foregroundStyle(.secondary)
            if library.sounds.isEmpty && !library.scanning {
                Text("Inga installerade instrument hittades. Anslut eventuell extern ljudbiblioteksdisk och läs om.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let loading = audio.loadingInstrument {
                HStack { ProgressView().controlSize(.small); Text("Laddar \(loading)…").font(.caption) }
            }
            List(visible) { sound in
                VStack(alignment: .leading, spacing: 3) {
                    Button(sound.name) {
                        tracker.assignSound(name: sound.name, kind: .auSampler, path: sound.url.path, toChannel: tracker.cursorChannel)
                    }
                    .buttonStyle(.plain)
                    .disabled(!sound.isSampler)
                    Text("\(sound.source) · \(sound.category)").font(.caption2).foregroundStyle(.secondary)
                    if !sound.isSampler {
                        Text("Kräver GarageBands instrument/effekter").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .help(sound.url.path)
            }
            .listStyle(.plain)
            Text("EXS/AUSampler laddas som riktiga instrument. Vissa nyare EXS-format stöds inte av Apples AUSampler.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .onAppear { library.scan() }
    }
}
