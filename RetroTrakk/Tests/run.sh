#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
probe_dir=$(mktemp -d /tmp/retrotrakk-verification.XXXXXX)
swiftc -O RetroTrakk/Models/JGXProject.swift RetroTrakk/Models/SongModel.swift RetroTrakk/Models/InstrumentDefinition.swift RetroTrakk/Models/SurgePresetCatalog.swift RetroTrakk/Engine/AudioUnitManager.swift RetroTrakk/Engine/RetroTrakkAudioEngine.swift RetroTrakk/Engine/AppleLibrary.swift RetroTrakk/Engine/MIDIEngine.swift RetroTrakk/Engine/TrackerEngine.swift Tests/SurgeVoiceNodeTestStub.swift Tests/main.swift -o "$probe_dir/verify"
"$probe_dir/verify"
