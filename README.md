# RetroTrakk

Native macOS tracker (Apple Silicon, macOS 14+) — en modern, lättillgänglig musik-tracker inspirerad av FastTracker II, ProTracker och Renoise med ett ljust, modernt gränssnitt.

Byggd 100% i native **Swift** och **SwiftUI**, med ljud via **AVFoundation** (`AVAudioEngine`, `AVAudioSequencer`, `AVAudioUnitSampler`) och MIDI via **CoreMIDI**. Inga externa SPM-beroenden eller pakethanterare krävs.

---

## Snabböversikt

* **Mål:** Snabb, stabil och musikalisk tracker för macOS med låg latens, direkt respons och nolltid till första ljud (< 10 sekunder).
* **Plattform:** macOS 14.0+ på Apple Silicon (M1/M2/M3/M4).
* **Version:** 0.9 (Build 10).
* **Bundle ID:** `com.retrotrakk.app`
* **Projektfil:** `NovaTracker/RetroTrakk.xcodeproj`

---

## Kom igång & köra

### Från Xcode
1. Öppna `NovaTracker/RetroTrakk.xcodeproj` i Xcode.
2. Välj scheme **RetroTrakk** (eller **NovaTracker**), destination **My Mac**.
3. Tryck **⌘R** (Run) eller **⌘B** (Build).

### Från Terminal
Bygg release-version och kopiera till `/Applications`:
```bash
cd NovaTracker
xcodebuild -project RetroTrakk.xcodeproj -scheme RetroTrakk -configuration Release -destination 'platform=macOS' build
cp -R ~/Library/Developer/Xcode/DerivedData/RetroTrakk-*/Build/Products/Release/RetroTrakk.app /Applications/
```

Kör automatiserade verifieringstester (bygger och kör utan Xcode GUI):
```bash
./NovaTracker/Tests/run.sh
```

---

## Projektets struktur

```text
retrotrakk/
├── README.md                     # Detta dokument (översikt, snabbstart, status)
├── ARCHITECTURE.md               # Detaljerad teknisk arkitektur och designval
├── AGENTS.md                     # Riktlinjer och regler för AI-assistenter/modeller
├── NovaTracker/
│   ├── RetroTrakk.xcodeproj      # Xcode-projekt (inga externa SPM-paket)
│   ├── README.md                 # Projektspecifik snabbguide
│   ├── NovaTracker/
│   │   ├── NovaTrackerApp.swift  # SwiftUI App-livscykel och Environment-setup
│   │   ├── Models/
│   │   │   └── SongModel.swift   # TrackerCell, Pattern, Instrument, Song, PlaybackTimeline
│   │   ├── Engine/
│   │   │   ├── NovaAudioEngine.swift   # AVAudioEngine, mixers, sequencers, WAV-export
│   │   │   ├── TrackerEngine.swift     # Transport, step input, ackord, live-rec, editering
│   │   │   ├── MIDIEngine.swift        # CoreMIDI-klient, autodetektering, note on/off
│   │   │   ├── AudioUnitManager.swift  # Skanning och instansiering av MusicDevice AU:er
│   │   │   └── AppleLibrary.swift      # GM-ljudkatalog och sökning efter installerade EXS
│   │   ├── Views/
│   │   │   ├── ContentView.swift       # Huvudfönster (HSplitView, toolbar, statusrad)
│   │   │   ├── TrackerView.swift       # 8-kanalers tracker-grid, tangentbordsstyrning
│   │   │   ├── TransportBar.swift      # Play/Stop/Record, BPM, step size, oktav, beat-LED
│   │   │   ├── Sidebars.swift          # Instrument-bibliotek (vänster), Orders (höger)
│   │   │   └── InstrumentBrowser.swift # AU-väljare och filläsare för samplingar
│   │   └── Assets.xcassets/            # App-ikoner och färger
│   └── Tests/
│       ├── run.sh                # Testkörningsskript via swiftc
│       └── main.swift            # Verifieringstester (timing, audio clock, WAV, EXS)
```

---

## Huvudfunktioner i nuvarande version (0.9)

1. **8 Tracker-kanaler & 64 rader per pattern:**
   * Tydlig kolumnstruktur med decimala radnummer (00–63).
   * Not (`C-4`), instrument (`01`), volym (`00–40` hex / `0–64` dec), effekter.
2. **Klick- och tangentbordsinmatning:**
   * Två-oktavs pianomappning (`Z-M` nedre oktav, `Q-U` övre oktav).
   * Ackordstöd: Snabba anslag (< halva radtiden) sprids automatiskt över lediga kanaler på samma rad.
3. **CoreMIDI-stöd:**
   * Automatisk skanning av anslutna MIDI-klaviaturer via CoreMIDI.
   * Step-inmatning och polyfonisk ackordsinmatning (cursor flyttas vid release).
   * Live-inspelning synkad mot sequencern med valbar kvantisering (1, 2, 4, 8 steps per beat).
4. **Ljudmotor & Instrument:**
   * Apple DLS MusicDevice med full General MIDI-bank (Pianos, Organs, Synths, Drums på kanal 10).
   * Stöd för Apple AUSampler och laddning av `.exs` / `.aupreset`-instrument (även via symlänkar till externa diskar).
   * Laddning av WAV/AIFF-samplingar.
   * Stöd för tredjeparts Audio Units (MusicDevice).
5. **Projektfiler & Export:**
   * Spara och öppna projekt i JSON-format (`.retrotrakk.json`).
   * Sample-exakt offline-rendering till 16-bitars 44.1 kHz WAV-filer.

---

## Verifiering & Testsvit

Projektet har en automatiserad testsvit i `NovaTracker/Tests/main.swift` som verifierar:
* Sample-exakt timing för WAV-export vid olika BPM (60, 125, 240) inom 2 samplars tolerans.
* Klockstabilitet i Core Audio när UI-tråden blockeras (700 ms utan drift).
* Realtidsuppdatering av noter under pågående uppspelning utan klockomstart.
* Upptäckt och rendering av installerade EXS-ljud.

Kör testerna med:
```bash
./NovaTracker/Tests/run.sh
```

---

## Vidare dokumentation

* Läs [**ARCHITECTURE.md**](ARCHITECTURE.md) för djupgående detaljer om ljudgraf, trådsäkerhet, tidslinje och kända begränsningar.
* Läs [**AGENTS.md**](AGENTS.md) för instruktioner riktade till AI-assistenter och modeller som ska utveckla i kodbasen.
