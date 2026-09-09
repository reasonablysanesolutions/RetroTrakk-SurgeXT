// RetroTrakk — TransportBar.swift
// Topp-toolbar: Record / Play / Stop / Edit + BPM / Steps / Pattern + MIDI + kvantisering.

import SwiftUI

struct TransportBar: View {
    @EnvironmentObject var tracker: TrackerEngine
    @EnvironmentObject var midi: MIDIEngine
    @Binding var statusMessage: String
    /// BPM-textfält med live-tillämpning: giltiga värden 40–300 slår igenom direkt,
    /// även mitt under spelning. Ogiltiga mellantillstånd ignoreras (ingen tvångs­omskrivning).
    @State private var bpmText = ""

    var body: some View {
        HStack(spacing: 14) {
            // Transport
            HStack(spacing: 8) {
                transportButton(
                    title: "Record", icon: "circle.fill",
                    color: tracker.isRecording ? .red : .secondary,
                    active: tracker.isRecording
                ) {
                    tracker.isRecording.toggle()
                    if tracker.isRecording && !tracker.isPlaying { tracker.play() }
                    statusMessage = tracker.isRecording ? "Spelar in — spela på MIDI-keyboard eller Mac-tangenter." : "Inspelning av."
                }
                transportButton(title: tracker.isPlaying ? "Stop" : "Play",
                                icon: tracker.isPlaying ? "stop.fill" : "play.fill",
                                color: .accentColor, active: tracker.isPlaying) {
                    tracker.togglePlay(fromStart: !tracker.isPlaying)
                    statusMessage = tracker.audio?.statusText ?? (tracker.isPlaying ? "Spelar…" : "Stoppad.")
                }
                transportButton(title: "Edit", icon: "pencil",
                                color: tracker.editMode ? .orange : .secondary,
                                active: tracker.editMode) {
                    tracker.editMode.toggle()
                }
            }

            Divider().frame(height: 28)

            // BPM / Steps / Pattern
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("BPM").font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        TextField("BPM", text: $bpmText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)
                            .monospacedDigit()
                            .onChange(of: bpmText) { _, t in
                                if let v = Double(t), v >= 40, v <= 300 {
                                    tracker.song.bpm = v
                                }
                            }
                        Stepper("", value: $tracker.song.bpm, in: 40...300, step: 1)
                            .labelsHidden()
                    }
                }
                .onAppear { bpmText = String(Int(tracker.song.bpm)) }
                .onChange(of: tracker.song.bpm) { _, v in
                    let s = String(Int(v))
                    if bpmText != s { bpmText = s }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Step").font(.caption2).foregroundStyle(.secondary)
                    Picker("", selection: $tracker.stepSize) {
                        ForEach([1, 2, 4, 8], id: \.self) { s in Text("\(s)").tag(s) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Steps/beat").font(.caption2).foregroundStyle(.secondary)
                    Picker("", selection: $tracker.song.stepsPerBeat) {
                        Text("1").tag(1); Text("2").tag(2); Text("4").tag(4); Text("8").tag(8)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pattern").font(.caption2).foregroundStyle(.secondary)
                    Text(tracker.currentPatternID.map { String(format: "%02d", $0) } ?? "--")
                        .font(.title3).bold().monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Oktav").font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 2) {
                        Button("−") { tracker.octave = max(0, tracker.octave - 1) }
                        Text("\(tracker.octave)").font(.body).monospacedDigit().frame(width: 20)
                        Button("+") { tracker.octave = min(8, tracker.octave + 1) }
                    }
                    .buttonStyle(.plain)
                }
                VStack(alignment: .center, spacing: 2) {
                    Text("Beat").font(.caption2).foregroundStyle(.secondary)
                    Circle()
                        .fill(tracker.isPlaying && tracker.beatPhase == 0 ? Color.green : Color.gray.opacity(0.25))
                        .frame(width: 14, height: 14)
                        .padding(.top, 5)
                }
                .help("Blinkar på varje taktslag — visar att tempot följer BPM")
            }

            Divider().frame(height: 28)

            // MIDI + kvantisering
            VStack(alignment: .leading, spacing: 2) {
                Text("MIDI-input").font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Picker("", selection: Binding(
                        get: { midi.selectedSource ?? -1 },
                        set: { midi.connect(index: $0) }
                    )) {
                        Text("Ingen").tag(-1)
                        ForEach(midi.sources.indices, id: \.self) { i in
                            Text(midi.sources[i]).tag(i)
                        }
                    }
                    .frame(width: 150)
                    Button(action: { midi.rescan() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Sök MIDI-enheter igen")
                }
                Toggle("Kvantisera live-inspelning", isOn: $tracker.quantize)
                    .font(.caption)
                    .toggleStyle(.checkbox)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func transportButton(title: String, icon: String, color: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Group {
            if title == "Play" || title == "Stop" {
                Button(action: action) {
                    buttonLabel(title: title, icon: icon, color: color, active: active)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
            } else {
                Button(action: action) {
                    buttonLabel(title: title, icon: icon, color: color, active: active)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func buttonLabel(title: String, icon: String, color: Color, active: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 34, height: 30)
                .background(active ? color.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
