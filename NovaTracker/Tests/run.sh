#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
probe_dir=$(mktemp -d /tmp/retrotrakk-verification.XXXXXX)
swiftc -O NovaTracker/Models/JGXProject.swift NovaTracker/Models/SongModel.swift NovaTracker/Models/InstrumentDefinition.swift NovaTracker/Engine/AudioUnitManager.swift NovaTracker/Engine/RetroTrakkAudioEngine.swift NovaTracker/Engine/AppleLibrary.swift Tests/main.swift -o "$probe_dir/verify"
"$probe_dir/verify"
