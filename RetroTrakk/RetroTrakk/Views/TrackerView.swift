// RetroTrakk — TrackerView.swift
// Sammanhängande vertikala kanalmoduler inspirerade av FastTracker 2:
// kanalhuvud → realtidsoscilloskop → kontroller → pattern-data.
// Tydlig 1.5 px kanalseparation, mjuk kanaltoning, 2 px accentram runt vald kanal.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Drag-payload för att flytta ett markerat område med musen.
struct BlockDragData: Codable, Transferable {
    var startRow: Int
    var startChannel: Int
    var endRow: Int
    var endChannel: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

/// Fast radhöjd — all hit-testning för musmarkering räknas fram utan
/// per-cell-geometri (512 GeometryReaders mättade tidigare huvudtråden).
private let trackerRowHeight: CGFloat = 26
private let trackerGutterWidth: CGFloat = 44
private let channelHeaderHeight: CGFloat = 110
private let minChannelWidth: CGFloat = 92

// MARK: - Kanal-färgpalett

struct ChannelPalette {
    struct ChannelColor {
        let accent: Color
        let headerBadge: Color
        let backgroundTint: Color
        let selectedTint: Color
    }

    static let colors: [ChannelColor] = [
        // Ch 1: Piano (Soft Blue)
        ChannelColor(
            accent: Color(red: 0.18, green: 0.52, blue: 0.95),
            headerBadge: Color(red: 0.18, green: 0.52, blue: 0.95),
            backgroundTint: Color(red: 0.18, green: 0.52, blue: 0.95).opacity(0.035),
            selectedTint: Color(red: 0.18, green: 0.52, blue: 0.95).opacity(0.09)
        ),
        // Ch 2: Bass (Purple / Magenta)
        ChannelColor(
            accent: Color(red: 0.72, green: 0.28, blue: 0.92),
            headerBadge: Color(red: 0.72, green: 0.28, blue: 0.92),
            backgroundTint: Color(red: 0.72, green: 0.28, blue: 0.92).opacity(0.035),
            selectedTint: Color(red: 0.72, green: 0.28, blue: 0.92).opacity(0.09)
        ),
        // Ch 3: Pad (Warm Amber / Gold)
        ChannelColor(
            accent: Color(red: 0.94, green: 0.64, blue: 0.18),
            headerBadge: Color(red: 0.94, green: 0.64, blue: 0.18),
            backgroundTint: Color(red: 0.94, green: 0.64, blue: 0.18).opacity(0.035),
            selectedTint: Color(red: 0.94, green: 0.64, blue: 0.18).opacity(0.09)
        ),
        // Ch 4: Drums (Teal / Cyan)
        ChannelColor(
            accent: Color(red: 0.12, green: 0.70, blue: 0.75),
            headerBadge: Color(red: 0.12, green: 0.70, blue: 0.75),
            backgroundTint: Color(red: 0.12, green: 0.70, blue: 0.75).opacity(0.035),
            selectedTint: Color(red: 0.12, green: 0.70, blue: 0.75).opacity(0.09)
        ),
        // Ch 5: Lead (Coral / Red)
        ChannelColor(
            accent: Color(red: 0.92, green: 0.36, blue: 0.36),
            headerBadge: Color(red: 0.92, green: 0.36, blue: 0.36),
            backgroundTint: Color(red: 0.92, green: 0.36, blue: 0.36).opacity(0.035),
            selectedTint: Color(red: 0.92, green: 0.36, blue: 0.36).opacity(0.09)
        ),
        // Ch 6: Strings (Emerald Green)
        ChannelColor(
            accent: Color(red: 0.22, green: 0.70, blue: 0.40),
            headerBadge: Color(red: 0.22, green: 0.70, blue: 0.40),
            backgroundTint: Color(red: 0.22, green: 0.70, blue: 0.40).opacity(0.035),
            selectedTint: Color(red: 0.22, green: 0.70, blue: 0.40).opacity(0.09)
        ),
        // Ch 7: FX (Violet / Indigo)
        ChannelColor(
            accent: Color(red: 0.58, green: 0.36, blue: 0.90),
            headerBadge: Color(red: 0.58, green: 0.36, blue: 0.90),
            backgroundTint: Color(red: 0.58, green: 0.36, blue: 0.90).opacity(0.035),
            selectedTint: Color(red: 0.58, green: 0.36, blue: 0.90).opacity(0.09)
        ),
        // Ch 8: Chiptune (Deep Steel Blue)
        ChannelColor(
            accent: Color(red: 0.28, green: 0.48, blue: 0.78),
            headerBadge: Color(red: 0.28, green: 0.48, blue: 0.78),
            backgroundTint: Color(red: 0.28, green: 0.48, blue: 0.78).opacity(0.035),
            selectedTint: Color(red: 0.28, green: 0.48, blue: 0.78).opacity(0.09)
        ),
    ]

    static func color(for channel: Int) -> ChannelColor {
        colors[channel % colors.count]
    }
}

// MARK: - TrackerView

struct TrackerView: View {
    @EnvironmentObject var tracker: TrackerEngine
    @FocusState private var focused: Bool
    @State private var gridWidth: CGFloat = 800

    private var channelWidth: CGFloat {
        let available = max(CGFloat(SongModel.channelCount) * minChannelWidth, gridWidth - trackerGutterWidth)
        return available / CGFloat(SongModel.channelCount)
    }

    // Piano-layout: undre raden = aktuell oktav, övre = oktav+1
    private func noteForKey(_ key: String, octave: Int) -> UInt8? {
        let base = 12 * (octave + 1)
        let lower: [String: Int] = ["z": 0, "s": 1, "x": 2, "d": 3, "c": 4, "v": 5, "g": 6, "h": 7,
                                    "b": 8, "n": 9, "j": 10, "m": 11, ",": 12]
        let upper: [String: Int] = ["q": 12, "2": 13, "w": 14, "3": 15, "e": 16, "r": 17, "5": 18,
                                    "t": 19, "6": 20, "y": 21, "7": 22, "u": 23, "i": 24]
        if let s = lower[key] { return UInt8(max(0, min(127, base + s))) }
        if let s = upper[key] { return UInt8(max(0, min(127, base + s))) }
        return nil
    }

    private var activeRow: Int {
        tracker.isPlaying ? tracker.currentRow : tracker.cursorRow
    }

    var body: some View {
        VStack(spacing: 0) {
            channelHeaders
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.6))
                .frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<rowCount, id: \.self) { row in
                            rowView(row)
                                .id(row)
                        }
                    }
                    .coordinateSpace(name: "trackerGrid")
                    .background(gridSizeReader)
                    .gesture(selectionDrag)
                }
                .onChange(of: tracker.currentRow) { _, newRow in
                    if tracker.isPlaying {
                        proxy.scrollTo(newRow, anchor: .center)
                    }
                }
                .onChange(of: tracker.cursorRow) { _, newRow in
                    if !tracker.isPlaying {
                        proxy.scrollTo(newRow, anchor: .center)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .focusable()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress { press in
            handleKey(press)
        }
        .onTapGesture { focused = true }
    }

    // MARK: - Mätning av rutnätsbredd

    private var gridSizeReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { gridWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in gridWidth = w }
        }
    }

    private func hitTest(_ loc: CGPoint) -> SelPoint? {
        let chW = channelWidth
        guard chW > 0 else { return nil }
        let row = min(rowCount - 1, max(0, Int(loc.y / trackerRowHeight)))
        let rawCh = Int((loc.x - trackerGutterWidth) / chW)
        let ch = min(SongModel.channelCount - 1, max(0, rawCh))
        return SelPoint(row, ch)
    }

    private var selectionDrag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("trackerGrid"))
            .onChanged { value in
                guard let hit = hitTest(value.location) else { return }
                if !tracker.dragActive {
                    tracker.selAnchor = SelPoint(hit.row, hit.channel)
                    tracker.dragActive = true
                }
                tracker.selCursor = SelPoint(hit.row, hit.channel)
                tracker.cursorRow = hit.row
                tracker.cursorChannel = hit.channel
            }
            .onEnded { _ in
                tracker.dragActive = false
            }
    }

    private var rowCount: Int {
        guard let pid = tracker.currentPatternID,
              let p = tracker.song.patterns.first(where: { $0.id == pid }) else { return 64 }
        return p.rowCount
    }

    // MARK: - Kanalhuvuden (Modulär kolumntopp: namn, oscilloskop, kontroller)

    private var channelHeaders: some View {
        HStack(spacing: 0) {
            VStack {
                Spacer()
                Text("ROW")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 6)
            }
            .frame(width: trackerGutterWidth, height: channelHeaderHeight)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))

            ForEach(0..<SongModel.channelCount, id: \.self) { ch in
                ChannelHeaderView(channel: ch)
                    .frame(width: channelWidth, height: channelHeaderHeight)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.8))
                            .frame(width: 1)
                    }
            }

            Spacer(minLength: 0)
        }
        .frame(height: channelHeaderHeight)
        .clipped()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Mönsterrader (00–63)

    // MARK: - Mönsterrader (00–63)

    private func rowGutter(row: Int, isActiveRow: Bool, isFourth: Bool) -> some View {
        Text(String(format: "%02d", row))
            .font(.system(size: 11, weight: isActiveRow || isFourth ? .bold : .regular, design: .monospaced))
            .foregroundStyle(isActiveRow ? .white : (isFourth ? Color.accentColor : .secondary))
            .frame(width: trackerGutterWidth, height: trackerRowHeight)
            .background(isActiveRow ? Color.accentColor : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func rowCell(row: Int, channel: Int, isLast: Bool) -> some View {
        TrackerCellView(
            tracker: tracker,
            row: row,
            channel: channel,
            cell: tracker.getCell(row: row, channel: channel),
            enabled: tracker.song.channelEnabled[channel],
            isCursor: row == tracker.cursorRow && channel == tracker.cursorChannel,
            selected: tracker.isSelected(row: row, channel: channel),
            isTopEdge: tracker.isSelectionTopEdge(row: row, channel: channel),
            isBottomEdge: tracker.isSelectionBottomEdge(row: row, channel: channel),
            isLeadingEdge: tracker.isSelectionLeadingEdge(row: row, channel: channel),
            isTrailingEdge: tracker.isSelectionTrailingEdge(row: row, channel: channel),
            isActiveChannel: channel == tracker.cursorChannel,
            palette: ChannelPalette.color(for: channel),
            isLastRow: isLast,
            onTap: { cellTapped(row: row, channel: channel) }
        )
        .equatable()
        .frame(width: channelWidth, height: trackerRowHeight)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.8))
                .frame(width: 1)
        }
    }

    private func rowBackground(isActiveRow: Bool, isBar: Bool, isFourth: Bool) -> Color {
        if isActiveRow { return Color.accentColor.opacity(0.15) }
        if isBar { return Color.primary.opacity(0.04) }
        if isFourth { return Color.primary.opacity(0.02) }
        return Color.clear
    }

    private func rowView(_ row: Int) -> some View {
        let isActiveRow = row == activeRow
        let isFourth = row % 4 == 3
        let isBar = row % 16 == 15
        let isLast = row == rowCount - 1

        return HStack(spacing: 0) {
            rowGutter(row: row, isActiveRow: isActiveRow, isFourth: isFourth)

            ForEach(0..<SongModel.channelCount, id: \.self) { ch in
                rowCell(row: row, channel: ch, isLast: isLast)
            }
        }
        .frame(height: trackerRowHeight)
        .background(rowBackground(isActiveRow: isActiveRow, isBar: isBar, isFourth: isFourth))
        .overlay(alignment: .top) {
            if isActiveRow {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(height: 1.5)
            }
        }
        .overlay(alignment: .bottom) {
            if isActiveRow {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(height: 1.5)
            }
        }
    }

    private func cellTapped(row: Int, channel: Int) {
        tracker.cursorChannel = channel
        if NSEvent.modifierFlags.contains(.shift) {
            tracker.extendSelection(row: row, channel: channel)
        } else {
            tracker.tapCell(row: row, channel: channel)
        }
        focused = true
    }

    // MARK: - Tangentbordsnavigering & inmatning

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let chars = press.characters.lowercased()
        if press.modifiers.contains(.command) {
            switch chars {
            case "c": tracker.copySelection(); return .handled
            case "x": tracker.cutSelection(); return .handled
            case "v": tracker.paste(); return .handled
            case "a": tracker.selectAll(); return .handled
            default: break
            }
        }
        let shift = press.modifiers.contains(.shift)
        switch press.key {
        case .upArrow:
            if shift { tracker.extendSelection(row: tracker.cursorRow - 1, channel: tracker.cursorChannel) }
            else { tracker.moveCursor(rows: -1) }
            return .handled
        case .downArrow:
            if shift { tracker.extendSelection(row: tracker.cursorRow + 1, channel: tracker.cursorChannel) }
            else { tracker.moveCursor(rows: 1) }
            return .handled
        case .leftArrow:
            if shift { tracker.extendSelection(row: tracker.cursorRow, channel: tracker.cursorChannel - 1) }
            else { tracker.moveCursor(channels: -1) }
            return .handled
        case .rightArrow:
            if shift { tracker.extendSelection(row: tracker.cursorRow, channel: tracker.cursorChannel + 1) }
            else { tracker.moveCursor(channels: 1) }
            return .handled
        case .tab: tracker.moveCursor(channels: press.modifiers.contains(.shift) ? -1 : 1); return .handled
        case .escape: tracker.clearSelection(); return .handled
        case .delete, .deleteForward:
            tracker.deleteSelectionOrCell()
            return .handled
        default: break
        }
        if chars == "." || chars == ";" {
            if tracker.shouldWriteInput() { tracker.insertNoteOff() }
            return .handled
        }
        if chars == " " {
            tracker.togglePlay()
            return .handled
        }
        if let note = noteForKey(chars, octave: tracker.octave) {
            tracker.stepInput(note: note)
            return .handled
        }
        if chars == "-" { tracker.octave = max(0, tracker.octave - 1); return .handled }
        if chars == "+" || chars == "=" { tracker.octave = min(8, tracker.octave + 1); return .handled }
        return .ignored
    }
}

// MARK: - Realtidsoscilloskop (Kanalwaveform + Snabb-Mute/Unmute)

struct WaveformShape: Shape {
    var points: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let w = rect.width
        let h = rect.height
        let midY = h / 2.0
        let dx = w / CGFloat(points.count - 1)
        let amp = h * 0.42

        for i in 0..<points.count {
            let x = CGFloat(i) * dx
            let val = CGFloat(max(-1.0, min(1.0, points[i])))
            let y = midY - (val * amp)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

struct ChannelOscilloscopeView: View {
    @ObservedObject private var waveformManager = WaveformManager.shared
    let channel: Int
    let color: Color
    let isEnabled: Bool
    let isSelected: Bool
    let onToggle: () -> Void

    private var currentWaveform: [Float] {
        if channel >= 0 && channel < waveformManager.waveforms.count {
            return waveformManager.waveforms[channel]
        }
        return Array(repeating: 0, count: 32)
    }

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                // Mörk neutral bakgrund
                RoundedRectangle(cornerRadius: 5)
                    .fill(isEnabled ? Color(white: 0.10) : Color(white: 0.05))

                // Baslinje i centrum
                Rectangle()
                    .fill(Color.white.opacity(isEnabled ? 0.08 : 0.02))
                    .frame(height: 1)

                // Vågformsritning via Shape (ingen GeometryReader)
                WaveformShape(points: isEnabled ? currentWaveform : Array(repeating: 0, count: 32))
                    .stroke(
                        isEnabled ? color : color.opacity(0.20),
                        style: StrokeStyle(lineWidth: isEnabled ? 1.8 : 1.0, lineCap: .round, lineJoin: .round)
                    )

                // Diskret statusindikator uppe till höger: ● ON / ○ OFF
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 3) {
                            Circle()
                                .fill(isEnabled ? color : Color.gray.opacity(0.5))
                                .frame(width: 5, height: 5)
                            Text(isEnabled ? "ON" : "OFF")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(isEnabled ? Color.white.opacity(0.85) : Color.white.opacity(0.35))
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(3)
            }
            .frame(height: 54)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? color.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Klicka för att slå av/på kanalens ljud (ON / OFF)")
    }
}

// MARK: - Kanalhuvud (Kanalnamn, Oscilloskop, Kontroller)

struct ChannelHeaderView: View {
    @EnvironmentObject var tracker: TrackerEngine
    let channel: Int
    @State private var showPicker = false

    private var palette: ChannelPalette.ChannelColor {
        ChannelPalette.color(for: channel)
    }

    private var isSelected: Bool {
        channel == tracker.cursorChannel
    }

    private var isEnabled: Bool {
        tracker.song.channelEnabled[channel]
    }

    private var instrumentName: String {
        if let iid = tracker.song.channelInstruments[channel],
           let inst = tracker.song.instruments.first(where: { $0.id == iid }) {
            return inst.name
        }
        return "—"
    }

    var body: some View {
        VStack(spacing: 3) {
            // Topprad: CH 0X + Instrumentnamn
            HStack(spacing: 4) {
                Text(String(format: "CH %02d", channel + 1))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? palette.accent : (isEnabled ? Color.secondary : Color.secondary.opacity(0.4)))

                Button {
                    tracker.cursorChannel = channel
                    showPicker = true
                } label: {
                    Text(instrumentName)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isEnabled ? (isSelected ? .primary : Color.primary.opacity(0.85)) : .secondary)
                }
                .buttonStyle(.plain)
                .help("Klicka för att byta instrument för kanal \(channel + 1)")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)

            // Realtidsoscilloskop (isolerat)
            ChannelOscilloscopeView(
                channel: channel,
                color: palette.accent,
                isEnabled: isEnabled,
                isSelected: isSelected,
                onToggle: {
                    tracker.cursorChannel = channel
                    tracker.song.channelEnabled[channel].toggle()
                    tracker.updateChannelState()
                }
            )
            .padding(.horizontal, 4)

            // Kontroller under oscilloskopet: Toggle + Mute + Solo
            HStack(spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { tracker.song.channelEnabled[channel] },
                    set: { val in
                        tracker.cursorChannel = channel
                        tracker.song.channelEnabled[channel] = val
                        tracker.updateChannelState()
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help("Kanal av/på")

                Spacer(minLength: 0)

                Button(tracker.song.channelMute[channel] ? "M" : "m") {
                    tracker.cursorChannel = channel
                    tracker.song.channelMute[channel].toggle()
                    tracker.updateChannelState()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(tracker.song.channelMute[channel] ? Color.red.opacity(0.2) : Color.clear)
                .foregroundStyle(tracker.song.channelMute[channel] ? .red : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .help("Mute")

                Button(tracker.song.channelSolo[channel] ? "S" : "s") {
                    tracker.cursorChannel = channel
                    tracker.song.channelSolo[channel].toggle()
                    tracker.updateChannelState()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(tracker.song.channelSolo[channel] ? Color.green.opacity(0.2) : Color.clear)
                .foregroundStyle(tracker.song.channelSolo[channel] ? .green : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .help("Solo")
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .background(isSelected ? palette.selectedTint : palette.backgroundTint)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(palette.accent).frame(width: 2)
            }
        }
        .overlay(alignment: .trailing) {
            if isSelected {
                Rectangle().fill(palette.accent).frame(width: 2)
            }
        }
        .overlay(alignment: .top) {
            if isSelected {
                Rectangle().fill(palette.accent).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            tracker.cursorChannel = channel
        }
        .popover(isPresented: $showPicker) {
            ChannelInstrumentPicker(channel: channel)
                .environmentObject(tracker)
                .frame(width: 260, height: 340)
        }
    }
}

// MARK: - TrackerCellView (Enskild cell med sammanhängande kanalram)

struct TrackerCellView: View, Equatable {
    let tracker: TrackerEngine
    let row: Int
    let channel: Int
    @State private var isTargeted = false

    let cell: TrackerCell
    let enabled: Bool
    let isCursor: Bool
    let selected: Bool
    let isTopEdge: Bool
    let isBottomEdge: Bool
    let isLeadingEdge: Bool
    let isTrailingEdge: Bool
    let isActiveChannel: Bool
    let palette: ChannelPalette.ChannelColor
    let isLastRow: Bool
    let onTap: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.channel == rhs.channel && lhs.cell == rhs.cell &&
        lhs.enabled == rhs.enabled && lhs.isCursor == rhs.isCursor &&
        lhs.selected == rhs.selected &&
        lhs.isTopEdge == rhs.isTopEdge && lhs.isBottomEdge == rhs.isBottomEdge &&
        lhs.isLeadingEdge == rhs.isLeadingEdge && lhs.isTrailingEdge == rhs.isTrailingEdge &&
        lhs.isActiveChannel == rhs.isActiveChannel &&
        lhs.isLastRow == rhs.isLastRow
    }

    var body: some View {
        Group {
            if selected, let r = tracker.selRect() {
                cellContent
                    .draggable(BlockDragData(startRow: r.0, startChannel: r.1, endRow: r.2, endChannel: r.3))
            } else {
                cellContent
            }
        }
        .dropDestination(for: BlockDragData.self, action: { items, _ in
            handleDrop(items: items)
        }, isTargeted: { isTargeted = $0 })
        .contextMenu {
            Button("Kopiera") {
                tracker.copySelection()
            }
            Button("Klipp ut") {
                tracker.cutSelection()
            }
            Button("Klistra in") {
                tracker.paste(atRow: row, atChannel: channel)
            }
            Divider()
            Button("Ta bort") {
                tracker.deleteSelectionOrCell()
            }
            Button("Markera allt") {
                tracker.selectAll()
            }
        }
    }

    private var cellContent: some View {
        HStack(spacing: 2) {
            Text(TrackerCell.noteName(cell.note))
                .font(.system(size: 11, weight: cell.note <= 127 ? .bold : .medium, design: .monospaced))
                .foregroundStyle(cell.note <= 127 ? .primary : .secondary)
                .frame(width: 28, alignment: .leading)
            Text(cell.instrument == 0 ? "--" : String(format: "%02d", cell.instrument))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(cell.volume == 255 ? "--" : String(format: "%02X", cell.volume))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Text(cell.effect == 0 ? "---" : String(format: "%X%02X", cell.effect, cell.param))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 24)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            selected ? palette.accent.opacity(0.35) :
            (isActiveChannel ? palette.selectedTint : palette.backgroundTint)
        )
        .overlay(alignment: .top) {
            if selected && isTopEdge {
                Rectangle().fill(palette.accent).frame(height: 2)
            }
        }
        .overlay(alignment: .bottom) {
            if selected && isBottomEdge {
                Rectangle().fill(palette.accent).frame(height: 2)
            } else if isActiveChannel && isLastRow {
                Rectangle().fill(palette.accent).frame(height: 2)
            }
        }
        .overlay(alignment: .leading) {
            if selected && isLeadingEdge {
                Rectangle().fill(palette.accent).frame(width: 2)
            } else if isActiveChannel {
                Rectangle().fill(palette.accent).frame(width: 1.5)
            }
        }
        .overlay(alignment: .trailing) {
            if selected && isTrailingEdge {
                Rectangle().fill(palette.accent).frame(width: 2)
            } else if isActiveChannel {
                Rectangle().fill(palette.accent).frame(width: 1.5)
            }
        }
        .overlay {
            if isCursor && !selected {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(palette.accent, lineWidth: 1.5)
            } else if isTargeted {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.green, lineWidth: 2)
            }
        }
        .opacity(enabled ? 1.0 : 0.45)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .help("Klicka för cursor. Dra med musen för att markera block. ⌘C/⌘X/⌘V kopiera/klipp/klistra.")
    }

    private func handleDrop(items: [BlockDragData]) -> Bool {
        guard let item = items.first else { return false }
        let rect = (item.startRow, item.startChannel, item.endRow, item.endChannel)
        let copy = NSEvent.modifierFlags.contains(.option)
        tracker.moveBlock(from: rect, toRow: row, toChannel: channel, copy: copy)
        return true
    }
}

// MARK: - ChannelInstrumentPicker

struct ChannelInstrumentPicker: View {
    @EnvironmentObject var tracker: TrackerEngine
    let channel: Int
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kanal \(channel + 1) — instrument")
                .font(.headline)
            Divider()
            Text("Välj bland projektets instrument (eller välj i instrumentbiblioteket till vänster):")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(tracker.song.instruments) { inst in
                Button {
                    tracker.setChannelInstrument(channel: channel, instrumentId: inst.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(inst.name)
                        Spacer()
                        if tracker.song.channelInstruments[channel] == inst.id {
                            Image(systemName: "checkmark")
                        }
                    }
                    .padding(6)
                    .background(tracker.song.channelInstruments[channel] == inst.id ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Button("Inget instrument") {
                tracker.setChannelInstrument(channel: channel, instrumentId: nil)
                dismiss()
            }
            .buttonStyle(.link)
            .padding(.top, 4)
            Spacer()
        }
        .padding()
    }
}
