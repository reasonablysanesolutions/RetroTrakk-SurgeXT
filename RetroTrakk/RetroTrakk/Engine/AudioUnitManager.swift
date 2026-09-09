// RetroTrakk — AudioUnitManager.swift
// Skannar MusicDevice-AU:er som macOS exponerar för tredjepartsappar.

import Foundation
import AVFoundation
import AudioToolbox

public struct AUInfo: Hashable, Identifiable {
    public var id: String { "\(manufacturer)-\(name)-\(type)-\(subtype)" }
    public var name: String
    public var manufacturer: String
    public var type: OSType
    public var subtype: OSType
    public var manufacturerID: OSType
    public var component: AVAudioUnitComponent
}

public final class AudioUnitManager {
    public static let shared = AudioUnitManager()

    /// Alla MusicDevice-komponenter (inkl. Apple DLS/AUSampler + tredjepart).
    public func availableMusicDevices() -> [AUInfo] {
        let manager = AVAudioUnitComponentManager.shared()
        // kAudioUnitType_MusicDevice — det enda macOS garanterat exponerar för instrument.
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0, componentManufacturer: 0,
            componentFlags: 0, componentFlagsMask: 0)
        let comps = manager.components(matching: desc)
        return comps.map { c in
            AUInfo(name: c.name, manufacturer: c.manufacturerName,
                   type: c.audioComponentDescription.componentType,
                   subtype: c.audioComponentDescription.componentSubType,
                   manufacturerID: c.audioComponentDescription.componentManufacturer,
                   component: c)
        }.sorted { $0.manufacturer < $1.manufacturer || ($0.manufacturer == $1.manufacturer && $0.name < $1.name) }
    }

    /// Snabblista för instrument-browserns Apple-sektion.
    public func appleInstruments() -> [AUInfo] {
        availableMusicDevices().filter { $0.manufacturer == "Apple" }
    }

    public func thirdPartyInstruments() -> [AUInfo] {
        availableMusicDevices().filter { $0.manufacturer != "Apple" }
    }

    /// Instansiera en MIDI-kapabel AU från en AVAudioUnitComponent.
    public func instantiate(_ info: AUInfo) throws -> AVAudioUnitMIDIInstrument {
        // AVAudioUnitMIDIInstrument init med AudioComponentDescription
        let desc = info.component.audioComponentDescription
        let unit = AVAudioUnitMIDIInstrument(audioComponentDescription: desc)
        return unit
    }

    public static func dlsDescription() -> AudioComponentDescription {
        AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                                  componentSubType: kAudioUnitSubType_DLSSynth, // DLSMusicDevice
                                  componentManufacturer: kAudioUnitManufacturer_Apple,
                                  componentFlags: 0, componentFlagsMask: 0)
    }

    public static func samplerDescription() -> AudioComponentDescription {
        AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                                  componentSubType: kAudioUnitSubType_Sampler,
                                  componentManufacturer: kAudioUnitManufacturer_Apple,
                                  componentFlags: 0, componentFlagsMask: 0)
    }
}
