// RetroTrakk — Sidebars.swift
// Vänster: Apple-bibliotek à la GarageBand (kategorier + patchar + favoriter).
// Höger: song/order-lista (byt namn, lägg till, duplicera, ta bort) + kanaler.

import SwiftUI

// MARK: - InstrumentSidebar: RetroTrakk Core Library (vänster)

enum SidebarCategorySelection: Hashable {
    case category(InstrumentCategory)
    case favorites
    case recentlyUsed
}

struct InstrumentSidebar: View {
    @EnvironmentObject var tracker: TrackerEngine
    @EnvironmentObject var audio: RetroTrakkAudioEngine
    @Binding var showPicker: Bool

    @State private var selection: SidebarCategorySelection = .category(.synthBass)
    @State private var search = ""
    /// Memoizerat sökresultat: `visibleInstruments` beräknas vid varje
    /// body-körning — utan cache skulle varje låtredigering söka om över
    /// 4000+ preset helt i onödan. Söks endast vid faktisk frågeändring.
    @State private var cachedSearch = ""
    @State private var cachedResults: [InstrumentDefinition] = []

    var body: some View {
        VStack(spacing: 0) {
            // Huvudrubrik
            HStack {
                Text("INSTRUMENTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showPicker = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Lägg till Audio Unit / externt sample")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Sökfält
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search instruments…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider()

            // Tvåkolumns split: Kategorier till vänster, Instrument till höger
            HStack(spacing: 0) {
                categoryColumn
                    .frame(width: 110)

                Divider()

                instrumentColumn
            }

            Divider()

            detailCard
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            syncCategoryToSelection()
        }
        .onChange(of: tracker.cursorChannel) { _, _ in
            syncCategoryToSelection()
        }
        .onChange(of: search) { _, q in
            // Progressiv narrowing: vid framåttypning söks endast i förra
            // resultatet (krympande mängd) i stället för alla 4000+ preset.
            if !q.isEmpty && !cachedSearch.isEmpty && q.hasPrefix(cachedSearch) {
                cachedResults = cachedResults.filter { $0.matches(query: q) }
            } else {
                cachedResults = q.isEmpty ? [] : InstrumentCatalog.search(q)
            }
            cachedSearch = q
        }
    }

    private func syncCategoryToSelection() {
        if let current = tracker.currentDefinition, search.isEmpty {
            selection = .category(current.category)
        }
    }

    // MARK: - Kategorikolumn

    private var categoryColumn: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                // Favorites
                categoryRow(
                    title: "Favorites",
                    icon: "star.fill",
                    color: Color.yellow,
                    isSelected: isCurrent(.favorites)
                ) {
                    selection = .favorites
                }

                // Recently Used
                categoryRow(
                    title: "Recent",
                    icon: "clock",
                    color: Color.secondary,
                    isSelected: isCurrent(.recentlyUsed)
                ) {
                    selection = .recentlyUsed
                }

                Divider()
                    .padding(.vertical, 4)

                ForEach(InstrumentCatalog.availableCategories) { cat in
                    categoryRow(
                        title: cat.name,
                        icon: cat.icon,
                        color: Color.secondary,
                        isSelected: isCurrent(.category(cat))
                    ) {
                        selection = .category(cat)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }

    private func isCurrent(_ target: SidebarCategorySelection) -> Bool {
        if !search.isEmpty { return false }
        return selection == target
    }

    private func categoryRow(
        title: String, icon: String, color: Color, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.accentColor : color)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Instrumentkolumn

    private var visibleInstruments: [InstrumentDefinition] {
        if !search.isEmpty {
            // Cachet per fråga (uppdateras i onChange) — aldrig omsökning
            // vid orelaterade body-körningar (t.ex. varje notinmatning).
            if search != cachedSearch {
                return InstrumentCatalog.search(search)
            }
            return cachedResults
        }
        switch selection {
        case .category(let cat):
            return InstrumentCatalog.inCategory(cat)
        case .favorites:
            return InstrumentCatalog.all.filter { tracker.isFavorite($0.id) }
        case .recentlyUsed:
            let recentOrder = tracker.recentIDs
            let map = Dictionary(uniqueKeysWithValues: InstrumentCatalog.all.map { ($0.id, $0) })
            return recentOrder.compactMap { map[$0] }
        }
    }

    private var instrumentColumn: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                if visibleInstruments.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Text(emptyStateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                        Spacer()
                    }
                } else {
                    ForEach(visibleInstruments) { inst in
                        instrumentRow(inst)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }

    private var emptyStateText: String {
        if !search.isEmpty {
            return "Inga instrument matchar \"\(search)\"."
        }
        switch selection {
        case .favorites:
            return "Inga favoriter ännu.\nKlicka på stjärnan för att favoritmarkera."
        case .recentlyUsed:
            return "Inga nyligen använda instrument ännu."
        case .category(let cat):
            return "Inga instrument i \(cat.name)."
        }
    }

    private func instrumentRow(_ inst: InstrumentDefinition) -> some View {
        let isSelected = tracker.currentDefinition?.id == inst.id
        let isFav = tracker.isFavorite(inst.id)

        return HStack(spacing: 4) {
            Button {
                assignToCurrentChannel(inst)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(inst.displayName)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.9))
                        .lineLimit(1)
                    Text(inst.category.name)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Klicka för att välja ljud för kanal \(tracker.cursorChannel + 1).")

            // Favorit-stjärna
            Button {
                tracker.toggleFavorite(inst.id)
            } label: {
                Image(systemName: isFav ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundStyle(isFav ? Color.yellow : Color.secondary.opacity(0.5))
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Favoritmarkera")
        }
    }

    private func assignToCurrentChannel(_ inst: InstrumentDefinition) {
        let ch = tracker.cursorChannel
        tracker.assignInstrument(inst, toChannel: ch)
    }

    // MARK: - Detaljkort

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let inst = tracker.currentDefinition {
                HStack(spacing: 8) {
                    Image(systemName: inst.category.icon)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(inst.displayName)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                        Text(inst.category.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        audio.auditionTrigger(definition: inst)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Provlyssna")
                }

                if !inst.description.isEmpty {
                    Text(inst.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Button("Lägg på kanal \(tracker.cursorChannel + 1)") {
                        assignToCurrentChannel(inst)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "pianokeys")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Inget instrument valt")
                            .font(.system(size: 12, weight: .bold))
                        Text("Välj ett instrument i listan för kanal \(tracker.cursorChannel + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            ChannelVolumeRow(channel: tracker.cursorChannel)
        }
        .padding(10)
    }
}

/// Volymrad för aktuell kanals låtinstrument
struct ChannelVolumeRow: View {
    @EnvironmentObject var tracker: TrackerEngine
    let channel: Int
    /// Lokal drag-state: modellen skrivs ENDAST vid släpp, så volymdrag
    /// aldrig tvingar hela appen att ritas om i sliders takt.
    @State private var volume: Double = 0.8

    var body: some View {
        if instrumentIndex != nil {
            HStack {
                Text("Volym").font(.caption).foregroundStyle(.secondary)
                Slider(value: $volume, in: 0...1) { editing in
                    if !editing { commit() }
                }
            }
            .onAppear { resync() }
            .onChange(of: tracker.song.instruments.map(\.volume)) { _, _ in resync() }
        }
    }

    private var instrumentIndex: Int? {
        tracker.song.instruments.firstIndex(where: { $0.id == tracker.song.channelInstruments[channel] })
    }

    private func resync() {
        if let idx = instrumentIndex {
            let v = tracker.song.instruments[idx].volume
            if abs(volume - v) > 0.001 { volume = v }
        }
    }

    private func commit() {
        if let idx = instrumentIndex {
            tracker.song.instruments[idx].volume = volume
        }
    }
}

// MARK: - Kanalstrip (volymdrag utan UI-storm)

/// En kanals reglage. Volym-slidern skriver till mixern DIREKT under drag
/// (hörbar återkoppling, noll SwiftUI-publiceringar) och committar till
/// modellen först vid släpp. Knappar/togglar är diskreta och skriver direkt.
struct ChannelStripView: View {
    @EnvironmentObject var tracker: TrackerEngine
    let channel: Int
    @State private var volume: Double = 0.8

    var body: some View {
        HStack(spacing: 4) {
            Text("\(channel + 1)").font(.caption).monospacedDigit()
                .frame(width: 14)
                .foregroundStyle(.secondary)
            Toggle("", isOn: Binding(
                get: { tracker.song.channelEnabled[channel] },
                set: {
                    tracker.song.channelEnabled[channel] = $0
                    tracker.updateChannelState()
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .frame(width: 30)
            .help("Slå av/på kanal \(channel + 1)")
            Slider(value: $volume, in: 0...1) { editing in
                if !editing { commit() }
            }
            .frame(width: 56)
            .onChange(of: volume) { _, v in liveApply(v) }
            .help("Kanalvolym (committas vid släpp)")
            Button(tracker.song.channelMute[channel] ? "M" : "m") {
                tracker.song.channelMute[channel].toggle()
                tracker.updateChannelState()
            }
            .buttonStyle(.plain).font(.caption2)
            .foregroundStyle(tracker.song.channelMute[channel] ? .red : .secondary)
            .frame(width: 16)
            Button(tracker.song.channelSolo[channel] ? "S" : "s") {
                tracker.song.channelSolo[channel].toggle()
                tracker.updateChannelState()
            }
            .buttonStyle(.plain).font(.caption2)
            .foregroundStyle(tracker.song.channelSolo[channel] ? .green : .secondary)
            .frame(width: 16)
        }
        .opacity(tracker.song.channelEnabled[channel] ? 1 : 0.45)
        .onAppear { resync() }
        .onChange(of: tracker.song.channelVolume[channel]) { _, v in
            if abs(volume - v) > 0.001 { volume = v }
        }
    }

    /// Hörbar återkoppling utan publicering — aldrig genom mutade kanaler.
    private func liveApply(_ v: Double) {
        guard isAudible else { return }
        tracker.audio?.channelMixers[channel].outputVolume = Float(v)
    }

    private var isAudible: Bool {
        let song = tracker.song
        let solo = song.channelSolo.contains(true)
        return song.channelEnabled[channel] && !song.channelMute[channel] &&
            (!solo || song.channelSolo[channel])
    }

    private func resync() {
        let v = tracker.song.channelVolume[channel]
        if abs(volume - v) > 0.001 { volume = v }
    }

    private func commit() {
        tracker.song.channelVolume[channel] = volume
        tracker.updateChannelState()
    }
}

// MARK: - OrderSidebar (höger)

struct OrderSidebar: View {
    @EnvironmentObject var tracker: TrackerEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Song")
                    .font(.headline)
                Spacer()
                Button { tracker.addPattern() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("Ny pattern")
                Button { tracker.duplicateOrderEntry(at: tracker.orderPos) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).help("Duplicera pattern")
                Button { tracker.deleteOrderEntry(at: tracker.orderPos) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("Ta bort order-rad")
                    .disabled(tracker.song.orders.count <= 1)
            }
            .padding(12)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(0..<tracker.song.orders.count, id: \.self) { pos in
                        OrderRowView(pos: pos)
                    }
                }
            }
            .padding(.horizontal, 8)

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Kanaler").font(.subheadline).bold()
                ForEach(0..<SongModel.channelCount, id: \.self) { ch in
                    ChannelStripView(channel: ch)
                }
                HStack {
                    Button("Rensa pattern") { tracker.clearPattern() }
                        .buttonStyle(.link).font(.caption)
                    Spacer()
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Order-rad (välj, dubbelklick = byt namn)

struct OrderRowView: View {
    @EnvironmentObject var tracker: TrackerEngine
    @EnvironmentObject var clock: PlaybackClock
    let pos: Int
    @State private var renaming = false
    @State private var draft = ""

    var body: some View {
        Button {
            tracker.orderPos = pos
            tracker.cursorRow = 0
            tracker.currentRow = 0
        } label: {
            HStack {
                Text(String(format: "%02d", pos))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                if renaming {
                    TextField("Namn", text: $draft, onCommit: commitRename)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .onExitCommand { renaming = false }
                } else {
                    Text(rowName()).font(.body).lineLimit(1)
                }
                Spacer()
                if pos == clock.orderPos {
                    Image(systemName: "play.fill").font(.caption).foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(pos == clock.orderPos ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onTapGesture(count: 2) {
            draft = rowName()
            renaming = true
        }
        .contextMenu {
            Button("Byt namn") { draft = rowName(); renaming = true }
            Button("Duplicera pattern") { tracker.duplicateOrderEntry(at: pos) }
            Divider()
            Button("Flytta upp") { tracker.moveOrderEntry(from: pos, delta: -1) }
            Button("Flytta ned") { tracker.moveOrderEntry(from: pos, delta: 1) }
            Divider()
            Button("Ta bort från order-listan", role: .destructive) {
                tracker.deleteOrderEntry(at: pos)
            }
            .disabled(tracker.song.orders.count <= 1)
        }
    }

    private func commitRename() {
        if pos < tracker.song.orders.count {
            tracker.renamePattern(id: tracker.song.orders[pos], name: draft)
        }
        renaming = false
    }

    private func rowName() -> String {
        guard pos < tracker.song.orders.count else { return "?" }
        let pid = tracker.song.orders[pos]
        return tracker.song.patterns.first(where: { $0.id == pid })?.name ?? "?"
    }
}
