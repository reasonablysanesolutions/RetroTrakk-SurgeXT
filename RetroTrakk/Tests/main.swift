import Foundation
import AVFoundation
import Darwin
setbuf(stdout, nil)

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
    print("PASS: \(message)")
}
let brandNewSong = SongModel()
check(brandNewSong.instruments.isEmpty, "Brand new SongModel starts with empty instruments")
check(brandNewSong.channelInstruments.allSatisfy { $0 == nil }, "Brand new SongModel starts with all channel instruments unassigned")
let emptyTransportTimeline = PlaybackTimeline(song: brandNewSong)
check(emptyTransportTimeline.length > 0 && emptyTransportTimeline.notes.isEmpty,
      "An empty project still has a valid transport timeline for live recording")
let emptyRecordingAudio = RetroTrakkAudioEngine()
let emptyRecordingEngine = TrackerEngine()
emptyRecordingEngine.audio = emptyRecordingAudio
emptyRecordingEngine.play()
check(emptyRecordingEngine.isPlaying, "Play starts an empty project so live recording can begin")
emptyRecordingEngine.stop()
emptyRecordingAudio.stopEngine()

var song = SongModel()
song.bpm = 120; song.stepsPerBeat = 4
song.patterns = [PatternModel(id: 7, name: "A", rows: 8), PatternModel(id: 9, name: "B", rows: 12)]
song.orders = [7, 9]
song.instruments = [InstrumentModel(id: 42, name: "Test")]
song.channelInstruments = [42, 42, nil, nil, nil, nil, nil, nil]
song.setCell(orderPos: 0, row: 3, channel: 0, cell: TrackerCell(note: 60, instrument: 1))
song.setCell(orderPos: 1, row: 2, channel: 1, cell: TrackerCell(note: 64))
let timeline = PlaybackTimeline(song: song)
check(timeline.notes.map(\.beat) == [0.75, 2.5], "Only grid rows determine note times, with non-64-row patterns")
check(timeline.notes[0].voice.instrumentID == 42, "Instrument column resolves one-based index, not ID")
// A channel change must create a new instrument snapshot. Earlier tracker
// cells keep their one-based instrument index and therefore their old sound.
var switchedInstrumentSong = SongModel()
switchedInstrumentSong.orders = [0]
switchedInstrumentSong.patterns = [PatternModel(id: 0, name: "Snapshots", rows: 4)]
switchedInstrumentSong.instruments = [
    InstrumentModel(id: 10, name: "First sound", kind: .dls, gmProgram: 0),
    InstrumentModel(id: 11, name: "Second sound", kind: .dls, gmProgram: 40)
]
switchedInstrumentSong.channelInstruments = [11, nil, nil, nil, nil, nil, nil, nil]
switchedInstrumentSong.setCell(orderPos: 0, row: 0, channel: 0, cell: TrackerCell(note: 60, instrument: 1))
switchedInstrumentSong.setCell(orderPos: 0, row: 1, channel: 0, cell: TrackerCell(note: 64, instrument: 2))
check(PlaybackTimeline(song: switchedInstrumentSong).notes.map(\.voice.instrumentID) == [10, 11],
      "Changing a channel sound preserves the instruments of existing notes")

// The Mac-keyboard route calls stepInput. Switching sounds must append a new
// snapshot, so the note written before the switch keeps its original voice.
let computerKeyboardEngine = TrackerEngine()
computerKeyboardEngine.editMode = true
let firstSurgeSound = InstrumentDefinition(
    id: "test-surge-first", displayName: "First Surge", category: .synthBass,
    sourceType: .surge, sourceIdentifier: "Basses/Attacky.fxp"
)
let secondSurgeSound = InstrumentDefinition(
    id: "test-surge-second", displayName: "Second Surge", category: .synthLead,
    sourceType: .surge, sourceIdentifier: "Leads/Bass 1.fxp"
)
computerKeyboardEngine.assignInstrument(firstSurgeSound, toChannel: 0)
computerKeyboardEngine.stepInput(note: 60)
computerKeyboardEngine.assignInstrument(secondSurgeSound, toChannel: 0)
computerKeyboardEngine.stepInput(note: 64)
check(computerKeyboardEngine.song.instruments.map(\.name) == ["First Surge", "Second Surge"],
      "Sound selection appends immutable instrument snapshots")
check([computerKeyboardEngine.getCell(row: 0, channel: 0).instrument,
       computerKeyboardEngine.getCell(row: 1, channel: 0).instrument] == [1, 2],
      "Computer-keyboard notes retain the selected instrument snapshot")
check(PlaybackTimeline(song: computerKeyboardEngine.song).notes.map(\.voice.instrumentID) == [0, 1],
      "Computer-keyboard notes play their original sounds after a channel switch")
check(ComputerKeyboardPiano.midiNote(for: "z", octave: 3) == 48 &&
      ComputerKeyboardPiano.midiNote(for: "z", octave: 5) == 72,
      "Octave selector changes the Mac keyboard's MIDI note")
check(timeline.beat(order: 1, row: 5) == 3.25, "Playback can start at a nonzero row and order")
check(timeline.position(at: 1.99, nearest: true)?.order == 1, "Live quantization crosses an order boundary")
check(timeline.position(at: 3.26)?.row == 5, "Recording uses actual playback position")
check(timeline.notes[0].voice != timeline.notes[1].voice, "Same instrument in two tracker channels has separate voices")
song.setCell(orderPos: 0, row: 4, channel: 0, cell: TrackerCell(effect: TrackerEffect.fadeOut, param: TrackerEffect.defaultFadeParameter))
let fadeTimeline = PlaybackTimeline(song: song)
check(fadeTimeline.fades.count == 1 && fadeTimeline.fades[0].beat == 1.0,
      "F08 creates a quantized channel release in the playback timeline")
song.setCell(orderPos: 0, row: 3, channel: 0, cell: .empty)
song.setCell(orderPos: 0, row: 6, channel: 0, cell: TrackerCell(note: 60, instrument: 1))
check(PlaybackTimeline(song: song).notes[0].beat == 1.5, "Moved notes play at their new row")

// Render impulses through the actual sampler and audio engine, then measure
// output onset spacing independently of the timeline implementation.
let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("retrotrakk-tests")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let clickURL = dir.appendingPathComponent("click.wav")
let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
let click = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
click.frameLength = 4410
for i in 0..<4410 { click.floatChannelData![0][i] = i < 100 ? Float(sin(Double(i) * 0.6) * 0.9) : 0 }
do { let file = try AVAudioFile(forWriting: clickURL, settings: format.settings); try file.write(from: click) }
song = SongModel(); song.orders = [0]; song.patterns = [PatternModel(id: 0, name: "Timing", rows: 16)]
song.instruments = [InstrumentModel(id: 0, name: "Click", kind: .sample, samplePath: clickURL.path)]
song.channelInstruments = [0, nil, nil, nil, nil, nil, nil, nil]
for row in [0, 4, 8, 12] { song.setCell(orderPos: 0, row: row, channel: 0, cell: TrackerCell(note: 60, instrument: 1)) }
let audio = RetroTrakkAudioEngine()
for bpm in [60.0, 125, 240] {
    song.bpm = bpm
    let output = dir.appendingPathComponent("\(Int(bpm)).wav")
    try audio.renderToWAV(song: song, url: output)
    let file = try AVAudioFile(forReading: output)
    let data = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: data)
    var onsets: [Int] = []; var last = -44100
    for i in 0..<Int(data.frameLength) where abs(data.floatChannelData![0][i]) > 0.001 {
        if i - last > 4410 { onsets.append(i) }
        last = i
    }
    check(onsets.count == 4, "\(Int(bpm)) BPM WAV contains exactly four audible notes")
    let expected = 44100 * 60 / bpm
    check(zip(onsets, onsets.dropFirst()).allSatisfy { abs(Double($1 - $0) - expected) <= 2 }, "\(Int(bpm)) BPM audible spacing accurate within two samples")
}
// Native playback must keep time even when the main thread is blocked.
song.bpm = 120
try audio.preparePlayback(song: song, timeline: PlaybackTimeline(song: song))
try audio.startPlayback(at: 0)
let start = ProcessInfo.processInfo.systemUptime
Thread.sleep(forTimeInterval: 0.7)
let elapsed = ProcessInfo.processInfo.systemUptime - start
check(abs(audio.playbackBeat - elapsed * 2) < 0.05, "Audio clock continues while the UI thread is blocked for 700 ms")
let before = audio.playbackBeat
audio.setPlaybackTempo(240)
Thread.sleep(forTimeInterval: 0.25)
check(abs(audio.playbackBeat - before - 1) < 0.06, "Live tempo change to 240 BPM follows the native clock")
audio.stopPlayback()
let stopped = audio.playbackBeat
Thread.sleep(forTimeInterval: 0.1)
check(abs(audio.playbackBeat - stopped) < 0.001, "Stop cancels native playback")
// Capture actual real-time audio while moving a future note during playback.
audio.stopEngine()
let liveAudio = audio
let captured = NSMutableData()
let lock = NSLock()
liveAudio.master.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
    lock.lock()
    captured.append(buffer.floatChannelData![0], length: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    lock.unlock()
}
song.bpm = 120
try liveAudio.preparePlayback(song: song, timeline: PlaybackTimeline(song: song))
try liveAudio.startPlayback(at: 0)
Thread.sleep(forTimeInterval: 0.2)
song.setCell(orderPos: 0, row: 4, channel: 0, cell: .empty)
song.setCell(orderPos: 0, row: 6, channel: 0, cell: TrackerCell(note: 60, instrument: 1))
try liveAudio.updatePlayback(song: song, timeline: PlaybackTimeline(song: song))
Thread.sleep(forTimeInterval: 1.7)
liveAudio.stopPlayback(); liveAudio.master.removeTap(onBus: 0)
lock.lock(); let bytes = captured.copy() as! NSData; lock.unlock()
let samples = bytes.bytes.assumingMemoryBound(to: Float.self)
var liveOnsets: [Int] = []; var previous = -44100
for i in 0..<(bytes.length / 4) where abs(samples[i]) > 0.001 {
    if i - previous > 4410 { liveOnsets.append(i) }
    previous = i
}
print("Real-time onset samples:", liveOnsets, "frames", bytes.length / 4)
check(liveOnsets.count == 4, "Native audio produces four notes after a live grid edit")
let expectedGaps = [0.75, 0.25, 0.5]
let sampleRate = liveAudio.master.outputFormat(forBus: 0).sampleRate
check(zip(zip(liveOnsets, liveOnsets.dropFirst()), expectedGaps).allSatisfy {
    abs(Double($0.1 - $0.0) / sampleRate - $1) < 0.015
}, "Real-time audio follows the moved cell while the main thread is blocked")
audio.stopEngine()

// Reproduce app startup: the hardware engine is already running before Play,
// but unused instrument previews are not eagerly attached.
let appAudio = RetroTrakkAudioEngine()
appAudio.start()
let appCaptured = NSMutableData()
let appLock = NSLock()
appAudio.master.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
    appLock.lock()
    appCaptured.append(buffer.floatChannelData![0], length: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    appLock.unlock()
}
try appAudio.preparePlayback(song: song, timeline: PlaybackTimeline(song: song))
try appAudio.startPlayback(at: 0)
Thread.sleep(forTimeInterval: 1.8)
appAudio.stopPlayback()
appAudio.master.removeTap(onBus: 0)
appLock.lock()
let appBytes = appCaptured.copy() as! NSData
appLock.unlock()
let appSamples = appBytes.bytes.assumingMemoryBound(to: Float.self)
check((0..<(appBytes.length / MemoryLayout<Float>.size)).contains { abs(appSamples[$0]) > 0.001 },
      "App launch lifecycle produces audible realtime playback")
appAudio.stopEngine()

// DLSMusicDevice regression: this is the default instrument path used by the app.
var dlsSong = SongModel()
dlsSong.orders = [0]
dlsSong.patterns = [PatternModel(id: 0, name: "DLS live", rows: 16)]
dlsSong.instruments = [InstrumentModel(id: 0, name: "Grand Piano", kind: .dls, gmProgram: 0)]
dlsSong.channelInstruments = [0, nil, nil, nil, nil, nil, nil, nil]
for row in [0, 4, 8, 12] {
    dlsSong.setCell(orderPos: 0, row: row, channel: 0, cell: TrackerCell(note: 60, instrument: 1))
}
let dlsAudio = RetroTrakkAudioEngine()
let dlsCaptured = NSMutableData(); let dlsLock = NSLock()
dlsAudio.master.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
    dlsLock.lock()
    dlsCaptured.append(buffer.floatChannelData![0], length: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    dlsLock.unlock()
}
try dlsAudio.preparePlayback(song: dlsSong, timeline: PlaybackTimeline(song: dlsSong))
try dlsAudio.startPlayback(at: 0)
Thread.sleep(forTimeInterval: 1.8)
dlsAudio.stopPlayback(); dlsAudio.master.removeTap(onBus: 0)
dlsLock.lock(); let dlsBytes = dlsCaptured.copy() as! NSData; dlsLock.unlock()
let dlsSamples = dlsBytes.bytes.assumingMemoryBound(to: Float.self)
let dlsPeak = (0..<(dlsBytes.length / 4)).reduce(Float(0)) { max($0, abs(dlsSamples[$1])) }
print("DLS realtime peak:", dlsPeak, "frames:", dlsBytes.length / 4)
check(dlsPeak > 0.001, "DLS piano produces audible realtime playback through Play")
dlsAudio.stopEngine()

// Exact user flow: keyboard preview works, then Play must use the same live DLS.
let previewPlayAudio = RetroTrakkAudioEngine()
previewPlayAudio.previewOn(inst: dlsSong.instruments[0], midiNote: 60, velocity: 100)
Thread.sleep(forTimeInterval: 0.1)
previewPlayAudio.previewOff(instrumentId: dlsSong.instruments[0].id, midiNote: 60)
let previewPlayData = NSMutableData(); let previewPlayLock = NSLock()
previewPlayAudio.master.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
    previewPlayLock.lock()
    previewPlayData.append(buffer.floatChannelData![0], length: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    previewPlayLock.unlock()
}
try previewPlayAudio.preparePlayback(song: dlsSong, timeline: PlaybackTimeline(song: dlsSong))
try previewPlayAudio.startPlayback(at: 0)
Thread.sleep(forTimeInterval: 1.8)
previewPlayAudio.stopPlayback(); previewPlayAudio.master.removeTap(onBus: 0)
previewPlayLock.lock(); let previewPlayBytes = previewPlayData.copy() as! NSData; previewPlayLock.unlock()
let previewPlaySamples = previewPlayBytes.bytes.assumingMemoryBound(to: Float.self)
let previewPlayPeak = (0..<(previewPlayBytes.length / 4)).reduce(Float(0)) { max($0, abs(previewPlaySamples[$1])) }
print("Keyboard-then-Play DLS peak:", previewPlayPeak)
check(previewPlayPeak > 0.001, "Keyboard preview followed by Play remains audible")
previewPlayAudio.stopEngine()

// Reproduce the real eight-channel default DLS graph used by the app.
var multiDLSSong = SongModel()
multiDLSSong.instruments = (0..<8).map { InstrumentModel(id: $0, name: "DLS \($0)", kind: .dls, gmProgram: $0) }
multiDLSSong.channelInstruments = Array(0..<8)
multiDLSSong.orders = [0]
multiDLSSong.patterns = [PatternModel(id: 0, name: "8 DLS", rows: 16)]
for ch in 0..<SongModel.channelCount {
    multiDLSSong.setCell(orderPos: 0, row: ch * 2, channel: ch,
                         cell: TrackerCell(note: UInt8(60 + ch), instrument: UInt8(ch + 1)))
}
let multiDLSAudio = RetroTrakkAudioEngine()
let multiDLSData = NSMutableData(); let multiDLSLock = NSLock()
multiDLSAudio.master.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
    multiDLSLock.lock()
    multiDLSData.append(buffer.floatChannelData![0], length: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    multiDLSLock.unlock()
}
try multiDLSAudio.preparePlayback(song: multiDLSSong, timeline: PlaybackTimeline(song: multiDLSSong))
try multiDLSAudio.startPlayback(at: 0)
Thread.sleep(forTimeInterval: 2.0)
multiDLSAudio.stopPlayback(); multiDLSAudio.master.removeTap(onBus: 0)
multiDLSLock.lock(); let multiDLSBytes = multiDLSData.copy() as! NSData; multiDLSLock.unlock()
let multiDLSSamples = multiDLSBytes.bytes.assumingMemoryBound(to: Float.self)
let multiDLSPeak = (0..<(multiDLSBytes.length / 4)).reduce(Float(0)) { max($0, abs(multiDLSSamples[$1])) }
print("Eight-channel DLS realtime peak:", multiDLSPeak)
check(multiDLSPeak > 0.001, "Eight simultaneous DLS voices produce audible realtime Play output")
multiDLSAudio.stopEngine()

let installed = InstalledSoundLibrary.discover()
print("Catalogue:", installed.filter(\.isSampler).count, "sampler instruments,", installed.filter { !$0.isSampler }.count, "GarageBand patches")
check(installed.contains { $0.name == "Grand Piano" && $0.isSampler }, "Discovers installed EXS instruments through external-disk symlinks")
check(installed.contains { $0.name == "Steinway Grand Piano" && !$0.isSampler }, "Includes GarageBand channel strips with an explicit compatibility distinction")
var realSong = song
realSong.instruments[0] = InstrumentModel(id: 0, name: "Grand Piano", kind: .auSampler,
    samplePath: "/Library/Application Support/Logic/Sampler Instruments/01 Acoustic Pianos/Grand Piano.exs")
// Installed EXS regression through the actual Play/sequencer path.
let exsAudio = RetroTrakkAudioEngine()
let exsCaptured = NSMutableData(); let exsLock = NSLock()
exsAudio.master.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
    exsLock.lock()
    exsCaptured.append(buffer.floatChannelData![0], length: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    exsLock.unlock()
}
try exsAudio.preparePlayback(song: realSong, timeline: PlaybackTimeline(song: realSong))
try exsAudio.startPlayback(at: 0)
Thread.sleep(forTimeInterval: 1.8)
exsAudio.stopPlayback(); exsAudio.master.removeTap(onBus: 0)
exsLock.lock(); let exsBytes = exsCaptured.copy() as! NSData; exsLock.unlock()
let exsSamples = exsBytes.bytes.assumingMemoryBound(to: Float.self)
let exsPeak = (0..<(exsBytes.length / 4)).reduce(Float(0)) { max($0, abs(exsSamples[$1])) }
print("EXS realtime peak:", exsPeak, "frames:", exsBytes.length / 4)
check(exsPeak > 0.001, "Installed EXS Grand Piano produces audible realtime Play output")
exsAudio.stopEngine()

// Exact EXS user flow: preview the loaded sound, then Play the pattern.
let exsPreviewAudio = RetroTrakkAudioEngine()
exsPreviewAudio.previewOn(inst: realSong.instruments[0], midiNote: 60, velocity: 100)
Thread.sleep(forTimeInterval: 0.15)
exsPreviewAudio.previewOff(instrumentId: realSong.instruments[0].id, midiNote: 60)
let exsPreviewData = NSMutableData(); let exsPreviewLock = NSLock()
exsPreviewAudio.master.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
    exsPreviewLock.lock()
    exsPreviewData.append(buffer.floatChannelData![0], length: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    exsPreviewLock.unlock()
}
try exsPreviewAudio.preparePlayback(song: realSong, timeline: PlaybackTimeline(song: realSong))
try exsPreviewAudio.startPlayback(at: 0)
Thread.sleep(forTimeInterval: 1.8)
exsPreviewAudio.stopPlayback(); exsPreviewAudio.master.removeTap(onBus: 0)
exsPreviewLock.lock(); let exsPreviewBytes = exsPreviewData.copy() as! NSData; exsPreviewLock.unlock()
let exsPreviewSamples = exsPreviewBytes.bytes.assumingMemoryBound(to: Float.self)
let exsPreviewPeak = (0..<(exsPreviewBytes.length / 4)).reduce(Float(0)) { max($0, abs(exsPreviewSamples[$1])) }
print("Keyboard-then-Play EXS peak:", exsPreviewPeak)
check(exsPreviewPeak > 0.001, "EXS keyboard preview followed by Play remains audible")
exsPreviewAudio.stopEngine()

let realURL = dir.appendingPathComponent("installed-grand-piano.wav")
try audio.renderToWAV(song: realSong, url: realURL)
let realFile = try AVAudioFile(forReading: realURL)
let realPCM = AVAudioPCMBuffer(pcmFormat: realFile.processingFormat, frameCapacity: AVAudioFrameCount(realFile.length))!
try realFile.read(into: realPCM)
check((0..<Int(realPCM.frameLength)).contains { abs(realPCM.floatChannelData![0][$0]) > 0.001 }, "Actual installed EXS Grand Piano produces audible output")

// MARK: - Surge XT Catalog Tests
print("--- Starting Surge XT Catalog Tests ---")
check(InstrumentCatalog.all.count > 100, "Surge XT factory catalog is available")
check(InstrumentCatalog.all.allSatisfy { $0.sourceType == .surge }, "Standard SoundFont presets are replaced by Surge XT")
let bassResults = InstrumentCatalog.search("bass")
check(!bassResults.isEmpty, "Surge XT bass presets are searchable")
let firstPreset = InstrumentCatalog.all.first!
check(SurgePresetCatalog.patchURL(relativePath: firstPreset.sourceIdentifier) != nil, "Surge XT preset path resolves")
var fullSong = SongModel()
fullSong.instruments = [InstrumentModel(id: 0, name: firstPreset.displayName, kind: .surge, surgePatchPath: firstPreset.sourceIdentifier)]
fullSong.channelInstruments[0] = 0
fullSong.setCell(orderPos: 0, row: 0, channel: 0, cell: TrackerCell(note: 60, instrument: 1))
fullSong.setCell(orderPos: 0, row: 2, channel: 1, cell: TrackerCell(note: 61, instrument: 1))
let songJSON = try JSONEncoder().encode(fullSong)
let restoredSong = try JSONDecoder().decode(SongModel.self, from: songJSON)
check(restoredSong.instruments[0].kind == .surge && restoredSong.instruments[0].surgePatchPath == firstPreset.sourceIdentifier, "Surge XT preset persists in project JSON")

// 8. JGX Project File Format (.jgx) Tests
print("--- Starting JGX Project Format (.jgx) Tests ---")
let jgxURL = dir.appendingPathComponent("test-project.jgx")
try fullSong.save(to: jgxURL)
check(FileManager.default.fileExists(atPath: jgxURL.path), ".jgx file created on disk")

let jgxData = try Data(contentsOf: jgxURL)
let jgxRawJSON = try JSONSerialization.jsonObject(with: jgxData) as? [String: Any]
check(jgxRawJSON?["format"] as? String == "jgx", "JGX header format is 'jgx'")
check(jgxRawJSON?["version"] as? Int == 1, "JGX version is 1")
check(jgxRawJSON?["author"] as? String == "Jimmy Granlund", "JGX author is Jimmy Granlund")
check(jgxRawJSON?["generator"] as? String == "RetroTrakk", "JGX generator is RetroTrakk")
check(jgxRawJSON?["song"] != nil, "JGX payload contains song data")

let loadedJGXSong = try SongModel.load(from: jgxURL)
check(loadedJGXSong.instruments.count == fullSong.instruments.count, "JGX restores exact instrument count")
check(loadedJGXSong.instruments[0].name == fullSong.instruments[0].name, "JGX restores instrument name")
check(loadedJGXSong.channelInstruments == fullSong.channelInstruments, "JGX restores channel instruments mapping")
check(loadedJGXSong.bpm == fullSong.bpm, "JGX restores BPM")
check(loadedJGXSong.patterns.count == fullSong.patterns.count, "JGX restores pattern count")
check(loadedJGXSong.patterns[0].cells[0][0].note == 60, "JGX restores cell note")
check(loadedJGXSong.patterns[0].cells[2][1].note == 61, "JGX restores multi-channel notes")

// Test backward compatibility: Loading raw SongModel JSON via SongModel.load / JGXProject.decode
let legacyJSONURL = dir.appendingPathComponent("legacy-song.json")
try songJSON.write(to: legacyJSONURL)
let legacyLoadedSong = try SongModel.load(from: legacyJSONURL)
check(legacyLoadedSong.instruments.count == fullSong.instruments.count, "Loads legacy JSON song transparently")
check(legacyLoadedSong.instruments[0].name == fullSong.instruments[0].name, "Legacy song retains Surge preset properties")

print("ALL TESTS PASSED")
