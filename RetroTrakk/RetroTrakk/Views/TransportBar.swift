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
            // Transport: granulära subvyer observerar clock/tracker separat.
            // Denna förälder observerar ENDAST tracker+midi (lågfrekvent) —
            // aldrig clock (60/120 Hz). Se TransportButtonsView/BeatIndicatorView.
            TransportButtonsView(statusMessage: $statusMessage)
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
                    PatternIndicatorView()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Oktav").font(.caption2).foregroundStyle(.secondary)
                    Stepper(value: $tracker.octave, in: 0...8) {
                        Text("\(tracker.octave)").font(.body).monospacedDigit()
                    }
                    .labelsHidden()
                    .frame(width: 62)
                    .help("Väljer oktav för Mac-tangentbordet (Z = C i vald oktav)")
                }
                VStack(alignment: .center, spacing: 2) {
                    Text("Beat").font(.caption2).foregroundStyle(.secondary)
                    BeatIndicatorView()
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

            // Master-FX (echo/cutoff/effekt): syns när ett instrument är valt.
            // Isolerad subvy med lokal @State — motorn publicerar aldrig.
            MasterFXPanel()

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

// MARK: - Granulära transportsubvyer (Del 3: isolerad observation)

// Endast transportknapparna observerar clock.isPlaying — resten av
// TransportBar (BPM/Step/MIDI) påverkas inte av 60/120 Hz playhead-ticks.
struct TransportButtonsView: View {
    @EnvironmentObject var tracker: TrackerEngine
    @EnvironmentObject var clock: PlaybackClock
    @Binding var statusMessage: String

    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                tracker.isRecording.toggle()
                if tracker.isRecording && !clock.isPlaying { tracker.play() }
                statusMessage = tracker.isRecording ? "Spelar in — spela på MIDI-keyboard eller Mac-tangenter." : "Inspelning av."
            }) {
                transportLabel(title: "Record", icon: "circle.fill",
                               color: tracker.isRecording ? .red : .secondary,
                               active: tracker.isRecording)
            }
            .buttonStyle(.plain)
            Button(action: {
                let wasPlaying = clock.isPlaying
                tracker.togglePlay(fromStart: !wasPlaying)
                statusMessage = tracker.audio?.statusText ?? (clock.isPlaying ? "Spelar…" : "Stoppad.")
            }) {
                transportLabel(title: clock.isPlaying ? "Stop" : "Play",
                               icon: clock.isPlaying ? "stop.fill" : "play.fill",
                               color: .accentColor, active: clock.isPlaying)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            Button(action: { tracker.editMode.toggle() }) {
                transportLabel(title: "Edit", icon: "pencil",
                               color: tracker.editMode ? .orange : .secondary,
                               active: tracker.editMode)
            }
            .buttonStyle(.plain)
        }
    }

    private func transportLabel(title: String, icon: String, color: Color, active: Bool) -> some View {
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

/// Beat-lysdioden observerar ENDAST clock (isPlaying + beatPhase).
/// Hela TransportBar körs därmed inte om per sextondel.
struct BeatIndicatorView: View {
    @EnvironmentObject var clock: PlaybackClock

    var body: some View {
        Circle()
            .fill(clock.isPlaying && clock.beatPhase == 0 ? Color.green : Color.gray.opacity(0.25))
            .frame(width: 14, height: 14)
            .padding(.top, 5)
    }
}

/// Mönsterindikatorn observerar order (lågfrekvent: byter endast per pattern).
/// Föräldern TransportBar påverkas därmed inte av per-rad ticks.
struct PatternIndicatorView: View {
    @EnvironmentObject var tracker: TrackerEngine
    @EnvironmentObject var clock: PlaybackClock

    var body: some View {
        Text(patternText)
            .font(.title3).bold().monospacedDigit()
    }

    private var patternText: String {
        let orders = tracker.song.orders
        guard clock.orderPos >= 0, clock.orderPos < orders.count else { return "--" }
        return String(format: "%02d", orders[clock.orderPos])
    }
}

// MARK: - Master-FX (Del 3: isolerad observation, Del 5: förvärmda noder)

/// Enkla master-kontroller (echo/cutoff/effekt) höger om MIDI-input.
/// Syns endast när ett instrument är valt. All state är lokal @State och
/// motorns värden är vanliga (icke-publicerade) egenskaper — dragningar i
/// sliders skriver direkt till AU-parametrar utan att invalidera en enda
/// annan vy. Noderna skapas i motorns init; här flippas endast bypass/mix.
struct MasterFXPanel: View {
    @EnvironmentObject var tracker: TrackerEngine
    @EnvironmentObject var audio: RetroTrakkAudioEngine
    @State private var echo: Double = 0
    @State private var cutoff: Double = 100
    @State private var reverb: MasterFXReverb = .off

    /// Exponentiell mappning 0...100 -> 400...20 000 Hz (musikalisk svepning).
    private func cutoffHz(_ v: Double) -> Float {
        Float(400 * pow(20_000.0 / 400.0, v / 100.0))
    }

    private var cutoffLabel: String {
        let hz = cutoffHz(cutoff)
        if hz >= 19_900 { return "Öppen" }
        if hz >= 1000 { return String(format: "%.1fk", hz / 1000) }
        return String(format: "%.0f", hz)
    }

    var body: some View {
        if tracker.currentDefinition != nil {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Echo").font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Slider(value: $echo, in: 0...100)
                            .frame(width: 90)
                            .onChange(of: echo) { _, v in audio.setEchoMix(Float(v)) }
                            .help("Ekomängd (master delay, 0.34 s)")
                        Text("\(Int(echo))").font(.caption2).monospacedDigit()
                            .frame(width: 22, alignment: .trailing)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Cutoff").font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Slider(value: $cutoff, in: 0...100)
                            .frame(width: 90)
                            .onChange(of: cutoff) { _, v in audio.setCutoff(cutoffHz(v)) }
                            .help("Master lågpassfilter (fullt öppet = bypass)")
                        Text(cutoffLabel).font(.caption2).monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Effekt").font(.caption2).foregroundStyle(.secondary)
                    Picker("", selection: $reverb) {
                        ForEach(MasterFXReverb.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .frame(width: 96)
                    .onChange(of: reverb) { _, p in audio.setReverb(p) }
                    .help("Master-reverb (bypassas vid Av)")
                }
            }
            .onAppear {
                echo = Double(audio.echoMix)
                reverb = audio.reverbPreset
                // Återsynk cutoff-slidern mot motorns Hz-värde.
                let hz = max(400, audio.cutoffHz)
                cutoff = 100 * log(Double(hz) / 400) / log(20_000.0 / 400.0)
            }
        }
    }
}
