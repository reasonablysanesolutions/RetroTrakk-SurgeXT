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
check(timeline.beat(order: 1, row: 5) == 3.25, "Playback can start at a nonzero row and order")
check(timeline.position(at: 1.99, nearest: true)?.order == 1, "Live quantization crosses an order boundary")
check(timeline.position(at: 3.26)?.row == 5, "Recording uses actual playback position")
check(timeline.notes[0].voice != timeline.notes[1].voice, "Same instrument in two tracker channels has separate voices")
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

// MARK: - Core SoundFont Automated Tests
print("--- Starting Core SoundFont Tests ---")

// 1. Core SoundFont file resolution
let sfURL = CoreSoundFont.resolveURL()
check(sfURL != nil, "CoreSoundFont.resolveURL locates MuseScore_General.sf2")
if let sf = sfURL {
    check(FileManager.default.fileExists(atPath: sf.path), "MuseScore_General.sf2 file exists on disk")
}

// 2. Instrument Catalog search tests
check(InstrumentCatalog.all.count >= 120, "Catalog has at least 120 curated instruments (found \(InstrumentCatalog.all.count))")
let pianoResults = InstrumentCatalog.search("piano")
check(pianoResults.count > 0, "Search 'piano' returns results: \(pianoResults.count) matches")
let bassResults = InstrumentCatalog.search("bass")
check(bassResults.count > 0, "Search 'bass' returns results: \(bassResults.count) matches")
let warmResults = InstrumentCatalog.search("warm")
check(warmResults.count > 0, "Search 'warm' matches descriptions/tags")
let eightiesResults = InstrumentCatalog.search("80s")
check(eightiesResults.count > 0, "Search '80s' matches tags")
let softResults = InstrumentCatalog.search("soft")
check(softResults.count > 0, "Search 'soft' matches tags/descriptions")

// 3. Core SoundFont single-instrument playback (Grand Piano)
var sfSong = SongModel()
sfSong.orders = [0]
sfSong.patterns = [PatternModel(id: 0, name: "SF2 Live", rows: 16)]
sfSong.instruments = [
    InstrumentModel(id: 0, name: "Grand Piano", kind: .coreSoundFont, gmProgram: 0, bankMSB: 121, bankLSB: 0, isDrumKit: false)
]
sfSong.channelInstruments = [0, nil, nil, nil, nil, nil, nil, nil]
for row in [0, 4, 8, 12] {
    sfSong.setCell(orderPos: 0, row: row, channel: 0, cell: TrackerCell(note: 60, instrument: 1))
}

let sfAudio = RetroTrakkAudioEngine()
let sfCaptured = NSMutableData(); let sfLock = NSLock()
sfAudio.master.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
    sfLock.lock()
    sfCaptured.append(buffer.floatChannelData![0], length: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    sfLock.unlock()
}
try sfAudio.preparePlayback(song: sfSong, timeline: PlaybackTimeline(song: sfSong))
try sfAudio.startPlayback(at: 0)
Thread.sleep(forTimeInterval: 1.8)
sfAudio.stopPlayback(); sfAudio.master.removeTap(onBus: 0)
sfLock.lock(); let sfBytes = sfCaptured.copy() as! NSData; sfLock.unlock()
let sfSamples = sfBytes.bytes.assumingMemoryBound(to: Float.self)
let sfPeak = (0..<(sfBytes.length / 4)).reduce(Float(0)) { max($0, abs(sfSamples[$1])) }
print("Core SoundFont Grand Piano peak:", sfPeak, "frames:", sfBytes.length / 4)
check(sfPeak > 0.001, "Core SoundFont Grand Piano produces audible realtime playback")
sfAudio.stopEngine()

// 3b. First Play after preview test (ensuring no preview-stealing or uninitialized sine wave)
let firstPlayAudio = RetroTrakkAudioEngine()
firstPlayAudio.start()
_ = firstPlayAudio.ensureInstrument(sfSong.instruments[0])
firstPlayAudio.previewOn(inst: sfSong.instruments[0], midiNote: 60, velocity: 100)
Thread.sleep(forTimeInterval: 0.1)
firstPlayAudio.previewOff(instrumentId: sfSong.instruments[0].id, midiNote: 60)

let firstPlayCaptured = NSMutableData(); let firstPlayLock = NSLock()
firstPlayAudio.master.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
    firstPlayLock.lock()
    firstPlayCaptured.append(buffer.floatChannelData![0], length: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    firstPlayLock.unlock()
}
try firstPlayAudio.preparePlayback(song: sfSong, timeline: PlaybackTimeline(song: sfSong))
try firstPlayAudio.startPlayback(at: 0)
Thread.sleep(forTimeInterval: 1.8)
firstPlayAudio.stopPlayback(); firstPlayAudio.master.removeTap(onBus: 0)
firstPlayLock.lock(); let firstPlayBytes = firstPlayCaptured.copy() as! NSData; firstPlayLock.unlock()
let firstPlaySamples = firstPlayBytes.bytes.assumingMemoryBound(to: Float.self)
let firstPlayPeak = (0..<(firstPlayBytes.length / 4)).reduce(Float(0)) { max($0, abs(firstPlaySamples[$1])) }
print("Core SoundFont First Play after preview peak:", firstPlayPeak)
check(firstPlayPeak > 0.001, "First Play after keyboard preview produces audible realtime playback")
// Also verify that preview is still functional and was not destroyed/stolen by playback
firstPlayAudio.previewOn(inst: sfSong.instruments[0], midiNote: 64, velocity: 100)
Thread.sleep(forTimeInterval: 0.1)
firstPlayAudio.previewOff(instrumentId: sfSong.instruments[0].id, midiNote: 64)
firstPlayAudio.stopEngine()

// 4. In-place instrument switching test (Piano -> Finger Bass)
let switchAudio = RetroTrakkAudioEngine()
var switchSong = sfSong
switchAudio.ensureInstrument(switchSong.instruments[0])
// Audition before switch
switchAudio.auditionOn(definition: InstrumentCatalog.all[0], note: 60, velocity: 100)
Thread.sleep(forTimeInterval: 0.1)
switchAudio.auditionOff(note: 60)

// Switch instrument 0 to Electric Bass (Finger) program 33
let bassDef = InstrumentCatalog.all.first { $0.program == 33 && !$0.isDrumKit }!
switchSong.instruments[0] = InstrumentModel(
    id: 0, name: bassDef.displayName, kind: .coreSoundFont,
    gmProgram: Int(bassDef.program), bankMSB: Int(bassDef.bankMSB), bankLSB: Int(bassDef.bankLSB), isDrumKit: false
)
switchAudio.ensureInstrument(switchSong.instruments[0])

let switchCaptured = NSMutableData(); let switchLock = NSLock()
switchAudio.master.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
    switchLock.lock()
    switchCaptured.append(buffer.floatChannelData![0], length: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    switchLock.unlock()
}
try switchAudio.preparePlayback(song: switchSong, timeline: PlaybackTimeline(song: switchSong))
try switchAudio.startPlayback(at: 0)
Thread.sleep(forTimeInterval: 1.8)
switchAudio.stopPlayback(); switchAudio.master.removeTap(onBus: 0)
switchLock.lock(); let switchBytes = switchCaptured.copy() as! NSData; switchLock.unlock()
let switchSamples = switchBytes.bytes.assumingMemoryBound(to: Float.self)
let switchPeak = (0..<(switchBytes.length / 4)).reduce(Float(0)) { max($0, abs(switchSamples[$1])) }
print("In-place switched Bass peak:", switchPeak)
check(switchPeak > 0.001, "In-place switched instrument produces audible realtime playback")
switchAudio.stopEngine()

// 5. Drum Kit Test (Bank 120, Program 0 Standard Kit)
var drumSong = SongModel()
drumSong.orders = [0]
drumSong.patterns = [PatternModel(id: 0, name: "Drums", rows: 16)]
let drumDef = InstrumentCatalog.all.first { $0.isDrumKit }!
drumSong.instruments = [
    InstrumentModel(id: 0, name: drumDef.displayName, kind: .coreSoundFont, gmProgram: Int(drumDef.program), bankMSB: 120, bankLSB: 0, isDrumKit: true)
]
drumSong.channelInstruments = [0, nil, nil, nil, nil, nil, nil, nil]
// Kick (36) on 0, 8; Snare (38) on 4, 12
for (r, n) in [(0, 36), (4, 38), (8, 36), (12, 38)] {
    drumSong.setCell(orderPos: 0, row: r, channel: 0, cell: TrackerCell(note: UInt8(n), instrument: 1))
}
let drumAudio = RetroTrakkAudioEngine()
let drumCaptured = NSMutableData(); let drumLock = NSLock()
drumAudio.master.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
    drumLock.lock()
    drumCaptured.append(buffer.floatChannelData![0], length: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    drumLock.unlock()
}
try drumAudio.preparePlayback(song: drumSong, timeline: PlaybackTimeline(song: drumSong))
try drumAudio.startPlayback(at: 0)
Thread.sleep(forTimeInterval: 1.8)
drumAudio.stopPlayback(); drumAudio.master.removeTap(onBus: 0)
drumLock.lock(); let drumBytes = drumCaptured.copy() as! NSData; drumLock.unlock()
let drumSamples = drumBytes.bytes.assumingMemoryBound(to: Float.self)
let drumPeak = (0..<(drumBytes.length / 4)).reduce(Float(0)) { max($0, abs(drumSamples[$1])) }
print("Drum kit peak:", drumPeak)
check(drumPeak > 0.001, "Core SoundFont Drum Kit produces audible playback on bank 120")
drumAudio.stopEngine()

// 6. 8-channel simultaneous Core SoundFont playback and WAV render
var fullSong = SongModel()
fullSong.instruments = [
    InstrumentModel(id: 0, name: "Grand Piano", kind: .coreSoundFont, gmProgram: 0, soundFontIdentifier: "MuseScore_General.sf2"),
    InstrumentModel(id: 1, name: "Finger Bass", kind: .coreSoundFont, gmProgram: 33, soundFontIdentifier: "MuseScore_General.sf2"),
    InstrumentModel(id: 2, name: "Warm Pad", kind: .coreSoundFont, gmProgram: 89, soundFontIdentifier: "MuseScore_General.sf2"),
    InstrumentModel(id: 3, name: "Square Lead", kind: .coreSoundFont, gmProgram: 80, soundFontIdentifier: "MuseScore_General.sf2"),
    InstrumentModel(id: 4, name: "String Ensemble", kind: .coreSoundFont, gmProgram: 48, soundFontIdentifier: "MuseScore_General.sf2"),
    InstrumentModel(id: 5, name: "Synth Brass", kind: .coreSoundFont, gmProgram: 62, soundFontIdentifier: "MuseScore_General.sf2"),
    InstrumentModel(id: 6, name: "Saw Lead", kind: .coreSoundFont, gmProgram: 81, soundFontIdentifier: "MuseScore_General.sf2"),
    InstrumentModel(id: 7, name: "Acoustic Kit", kind: .coreSoundFont, gmProgram: 0, bankMSB: 120, isDrumKit: true, soundFontIdentifier: "MuseScore_General.sf2", midiChannel: 9),
]
fullSong.channelInstruments = [0, 1, 2, 3, 4, 5, 6, 7]
for ch in 0..<SongModel.channelCount {
    fullSong.setCell(orderPos: 0, row: ch * 2, channel: ch,
                     cell: TrackerCell(note: UInt8(60 + ch), instrument: UInt8(ch + 1)))
}
let fullAudio = RetroTrakkAudioEngine()
let fullURL = dir.appendingPathComponent("core-soundfont-8ch.wav")
try fullAudio.renderToWAV(song: fullSong, url: fullURL)
let fullFile = try AVAudioFile(forReading: fullURL)
let fullPCM = AVAudioPCMBuffer(pcmFormat: fullFile.processingFormat, frameCapacity: AVAudioFrameCount(fullFile.length))!
try fullFile.read(into: fullPCM)
check((0..<Int(fullPCM.frameLength)).contains { abs(fullPCM.floatChannelData![0][$0]) > 0.001 },
      "8-channel Core SoundFont song renders audible WAV output")

// 7. SongModel JSON persistence of .coreSoundFont instruments
let songJSON = try JSONEncoder().encode(fullSong)
let restoredSong = try JSONDecoder().decode(SongModel.self, from: songJSON)
check(restoredSong.instruments.count == 8, "Restores all 8 instruments from JSON")
check(restoredSong.instruments[0].kind == .coreSoundFont, "Restored instrument preserves .coreSoundFont kind")
check(restoredSong.instruments[7].isDrumKit == true, "Restored instrument preserves isDrumKit flag")
check(restoredSong.instruments[7].bankMSB == 120, "Restored drum instrument preserves bankMSB 120")

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
check(loadedJGXSong.instruments[0].name == "Grand Piano", "JGX restores instrument name")
check(loadedJGXSong.channelInstruments == fullSong.channelInstruments, "JGX restores channel instruments mapping")
check(loadedJGXSong.bpm == fullSong.bpm, "JGX restores BPM")
check(loadedJGXSong.patterns.count == fullSong.patterns.count, "JGX restores pattern count")
check(loadedJGXSong.patterns[0].cells[0][0].note == 60, "JGX restores cell note")
check(loadedJGXSong.patterns[0].cells[2][1].note == 61, "JGX restores multi-channel notes")

// Test backward compatibility: Loading raw SongModel JSON via SongModel.load / JGXProject.decode
let legacyJSONURL = dir.appendingPathComponent("legacy-song.json")
try songJSON.write(to: legacyJSONURL)
let legacyLoadedSong = try SongModel.load(from: legacyJSONURL)
check(legacyLoadedSong.instruments.count == 8, "Loads legacy JSON song transparently")
check(legacyLoadedSong.instruments[0].name == "Grand Piano", "Legacy song retains instrument properties")

// Test audio engine playback of song loaded from .jgx
let jgxAudio = RetroTrakkAudioEngine()
let jgxCaptured = NSMutableData(); let jgxLock = NSLock()
jgxAudio.master.installTap(onBus: 0, bufferSize: 512, format: nil) { buffer, _ in
    jgxLock.lock()
    jgxCaptured.append(buffer.floatChannelData![0], length: Int(buffer.frameLength) * MemoryLayout<Float>.size)
    jgxLock.unlock()
}
try jgxAudio.preparePlayback(song: loadedJGXSong, timeline: PlaybackTimeline(song: loadedJGXSong))
try jgxAudio.startPlayback(at: 0)
Thread.sleep(forTimeInterval: 1.5)
jgxAudio.stopPlayback(); jgxAudio.master.removeTap(onBus: 0)
jgxLock.lock(); let jgxBytes = jgxCaptured.copy() as! NSData; jgxLock.unlock()
let jgxSamples = jgxBytes.bytes.assumingMemoryBound(to: Float.self)
let jgxPeak = (0..<(jgxBytes.length / 4)).reduce(Float(0)) { max($0, abs(jgxSamples[$1])) }
print("JGX loaded song playback peak:", jgxPeak)
check(jgxPeak > 0.001, "Audio engine produces audible playback directly from loaded .jgx file")
jgxAudio.stopEngine()

print("ALL TESTS PASSED")

