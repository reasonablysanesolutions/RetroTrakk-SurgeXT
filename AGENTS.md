# Riktlinjer för AI-assistenter & Utvecklare (AGENTS.md)

Detta dokument är en modell-agnostisk guide för alla AI-agenter (Claude, GPT, Gemini, Cursor etc.) och mänskliga utvecklare som arbetar i **RetroTrakk**. Läs detta innan du föreslår eller genomför ändringar.

---

## 1. Gyllene Regler & Arkitektoniska Principer

1. **Inga externa SPM/CocoaPods-beroenden:**
   * Projektet är avsiktligt byggt med 100% standard macOS SDK (SwiftUI, AVFoundation, CoreMIDI, AudioToolbox).
   * Lägg **aldrig** till externa paket om inte användaren uttryckligen ber om det.
2. **Kör alltid verifieringstesterna:**
   * Innan du avslutar en uppgift, kör alltid `./NovaTracker/Tests/run.sh`.
   * Skriptet bygger och exekverar de tidskänsliga testerna via `swiftc`. Alla tester måste passera.
3. **Core Audio-tråden vs UI-tråden:**
   * Sekvensering och not-uppspelning sköts av `AVAudioSequencer` på Core Audio-nivå. Skapa **aldrig** en `Timer` för att trigga notstarter under uppspelning.
   * UI-timers används enbart för att läsa av klockan (`sequencer.currentPositionInBeats`) och uppdatera playhead-grafik.
   * Tunga diskoperationer (som laddning av EXS-bibliotek) måste ske asynkront via DispatchQueue och Staging Graph-mönstret i `NovaAudioEngine.swift`.
4. **Prestanda i `TrackerView`:**
   * Använd **aldrig** `GeometryReader` inuti individuella celler eller rader. Trackern har 512 celler; per-cell geometri sänker frameraten direkt. All layout ska använda fast radhöjd (`trackerRowHeight = 26`) och matematisk hit-testing.
5. **En enda sanning för nottiming:**
   * Ändra eller anpassa alltid `PlaybackTimeline` i `SongModel.swift` om notpositioner eller tidsberäkningar förändras. Playback och offline WAV-rendering måste använda exakt samma nottidslinje.

---

## 2. Snabbkommandon för Terminalen

| Åtgärd | Kommando |
|---|---|
| **Kör tester** | `./NovaTracker/Tests/run.sh` |
| **Bygg app via CLI** | `cd NovaTracker && xcodebuild -project RetroTrakk.xcodeproj -scheme RetroTrakk -configuration Debug -destination 'platform=macOS' build` |
| **Bygg release & installera** | `cd NovaTracker && xcodebuild -project RetroTrakk.xcodeproj -scheme RetroTrakk -configuration Release -destination 'platform=macOS' build && cp -R ~/Library/Developer/Xcode/DerivedData/RetroTrakk-*/Build/Products/Release/RetroTrakk.app /Applications/` |

---

## 3. Var görs vilka ändringar?

* **Ny tracker-effekt (t.ex. Portamento, Arpeggio, Volume Slide):**
  * Utöka `TrackerCell` i `NovaTracker/Models/SongModel.swift` (`effect` och `param`).
  * Implementera logik för effekten i `PlaybackTimeline` eller MIDI-eventhanteringen i `NovaAudioEngine.swift`.
  * Uppdatera `TrackerView.swift` för att rendera effektkolumnen i cellerna.
* **Ljudmotorn & Instrumenthantering:**
  * Modifiera `NovaTracker/Engine/NovaAudioEngine.swift` (AU-instansiering, rendering, kanalmixers).
  * Instrumentkatalog och GM-definitioner: `NovaTracker/Engine/AppleLibrary.swift`.
  * AU-komponenthantering: `NovaTracker/Engine/AudioUnitManager.swift`.
* **Inmatning, Kvantisering & Tangentbord:**
  * Modifiera `NovaTracker/Engine/TrackerEngine.swift` (ackorddetektering, MIDI-step, cursorrörelser).
  * Keypress-mappning: `noteForKey` i `NovaTracker/Views/TrackerView.swift`.
* **Gränssnitt & Paneler:**
  * Huvudlayout: `NovaTracker/Views/ContentView.swift`.
  * Tracker-rutnät: `NovaTracker/Views/TrackerView.swift`.
  * Topprad (Transport, BPM, Stepper): `NovaTracker/Views/TransportBar.swift`.
  * Sidopaneler: `NovaTracker/Views/Sidebars.swift`.

---

## 4. Git och Versionshantering

* Projektet har ännu inte initierats som ett git-repository på disken.
* Om användaren ber om att versionshantera projektet:
  1. Skapa en `.gitignore` anpassad för macOS/Xcode (ignorera `DerivedData`, `.DS_Store`, `.build`, `.backups`, UserInterfaceState etc.).
  2. Initiera repo: `git init`.
  3. GitHub CLI finns tillgängligt via `gh` och är inloggat som `reasonablysanesolutions`.
