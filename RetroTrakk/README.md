# RetroTrakk

Native macOS-app (Apple Silicon) — modern musik-tracker inspirerad av FastTracker/ProTracker/Renoise, med ljust 2026-gränssnitt. Swift + SwiftUI, ljud via AVFoundation/AVAudioEngine, MIDI via CoreMIDI.

> **Fullständig dokumentation:** Se [Rotens README](../README.md), [ARCHITECTURE.md](../ARCHITECTURE.md) och [AGENTS.md](../AGENTS.md) för teknisk arkitektur, designval och utvecklingsriktlinjer.

## Öppna & kör

Appen ligger i **Docken** (och i `/Applications/RetroTrakk.app`) — klicka bara.

För utveckling: öppna `RetroTrakk.xcodeproj` i Xcode (26+).
2. Välj scheme **RetroTrakk**, destination **My Mac**.
3. Tryck **⌘R**.

Eller från terminal:

```sh
cd RetroTrakk
xcodebuild -project RetroTrakk.xcodeproj -scheme RetroTrakk -configuration Release -destination 'platform=macOS' build
cp -R ~/Library/Developer/Xcode/DerivedData/RetroTrakk-*/Build/Products/Release/RetroTrakk.app /Applications/
```

Kräver macOS 14+ på Apple Silicon.

## Snabbstart i appen (< 10 sekunder till ljud)

1. Klicka en kanal i trackern (kolumnhuvud `1–8`) — kanal 1–4 har redan Piano/Bass/Pad/Drums (Apple DLS).
2. Klicka en cell, skriv noter med Mac-tangentbordet:
   - Undre raden `Z S X D C V G B H N J M` = en oktav, övre raden `Q 2 W 3 E R 5 T 6 Y 7 U` = oktaven över.
   - Piltangenter flyttar cursor, `Mellanslag` = Play/Stop, `.` = note off, `-`/`+` = oktav.
3. Tryck **Play**.

Med MIDI-keyboard:

1. Välj enhet i **MIDI-input** i toolbaren (skannas automatiskt via CoreMIDI).
2. Spela → step input direkt på cursor-raden, eller tryck **Record** + **Play** för live-inspelning kvantiserad till tracker-rader (1/2/4/8 steps per beat, kan stängas av).

## Struktur

- `RetroTrakk/Models/SongModel.swift` — `TrackerCell`, `PatternModel`, `InstrumentModel`, `SongModel` (Codable/JSON).
- `RetroTrakk/Engine/TrackerEngine.swift` — playback-scheduler, cursor/step input, live-inspelning med kvantisering.
- `RetroTrakk/Engine/NovaAudioEngine.swift` — `AVAudioEngine`, 8 kanalmixers (volym/pan/mute/solo), DLS/AUSampler/tredjeparts-AU, WAV-render (offline).
- `RetroTrakk/Engine/AudioUnitManager.swift` — skannar MusicDevice-AU:er (Apple + tredjepart).
- `RetroTrakk/Engine/MIDIEngine.swift` — CoreMIDI-klient, note on/off + velocity.
- `RetroTrakk/Views/` — `ContentView`, `TrackerView`, `TransportBar`, `Sidebars`, `InstrumentBrowser`.

## MVP-status

8 kanaler · 64 rader/pattern · flera patterns · order-lista · note/instrument/volym per rad · Play/Stop/Record/Edit · BPM · step input · MIDI step + live recording · Apple AU + tredjeparts-AU + WAV/AIFF-samples · spara/ladda JSON · rendera WAV.

## Prioritering framåt (enligt spec)

1. Stabil ljudmotor → 2. Tracker-playback → 3. Apple AU → 4. MIDI-keyboard → 5. Live recording → 6. UI-polish.

## Timing och ljudbibliotek — 0.9 (10)

- AVAudioSequencer spelar noter i musikaliska slag från rutnätet. Gränssnittets 30 Hz-timer visar bara positionen. BPM-byte ändrar sequencerns takt direkt.
- Live-inspelning utgår från sequencerns aktuella slagposition, inklusive startrad och orderövergångar. Kvantisering väljer närmaste rad; utan kvantisering används pågående rad. Uppspelning följer alltid de sparade cellerna.
- Varje kombination av trackerkanal och instrument har en egen ljudnod. Förhandslyssning har separata noder. Kanalernas mute, solo, volym och panorering påverkar rätt ljud.
- WAV-export använder samma nottidslinje och renderar fram till varje anslag/släpp utan blockavrundning.
- GarageBand-fliken läser installerade EXS/AUSampler-filer, även via symboliska länkar till externa diskar. Avmarkera **Endast samplerinstrument** för att även visa GarageBands patchar.
- GarageBands `.patch`-filer innehåller egna instrument och effektkedjor och kan inte köras som en vanlig Audio Unit här. Nyare EXS-format och instrument med saknade sample-referenser kan också nekas av AUSampler. Appen visar laddningsfel och behåller då föregående instrument; inget ersättningsljud väljs tyst.

Verifiering: `Tests/run.sh` bygger en separat testkörning utan nya paket. Den mäter WAV-anslag vid 60/125/240 BPM, testar klockan när huvudtråden blockeras, spelar in verkligt realtidsljud medan en not flyttas och laddar det lokalt installerade EXS-instrumentet Grand Piano. De sista bibliotekstesterna kräver ljudbiblioteket på denna dator.

Källor: [Apples AVAudioSequencer](https://developer.apple.com/documentation/avfaudio/avaudiosequencer), [AUSampler och EXS-begränsningar](https://developer.apple.com/library/archive/technotes/tn2283/_index.html).
