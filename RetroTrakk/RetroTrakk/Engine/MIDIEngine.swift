// RetroTrakk — MIDIEngine.swift
// CoreMIDI direkt: listar källor, tar emot note on/off + velocity.

import Foundation
import CoreMIDI
import Combine

public final class MIDIEngine: ObservableObject {
    @Published public var sources: [String] = []
    @Published public var selectedSource: Int? = nil
    @Published public var lastEvent: String = "Ingen MIDI ännu"
    @Published public var isConnected: Bool = false

    public var onNoteOn: ((UInt8, UInt8) -> Void)?
    public var onNoteOff: ((UInt8) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedEndpoint: MIDIEndpointRef = 0

    public init() {
        setupClient()
        rescan()
    }

    private func setupClient() {
        MIDIClientCreateWithBlock("RetroTrakkMIDI" as CFString, &client) { _ in }
        MIDIInputPortCreateWithBlock(client, "RetroTrakkIn" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.handlePacketList(packetList)
        }
    }

    public func rescan() {
        let count = MIDIGetNumberOfSources()
        var names: [String] = []
        for i in 0..<count {
            let ep = MIDIGetSource(i)
            var cfName: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(ep, kMIDIPropertyDisplayName, &cfName) == noErr,
               let s = cfName?.takeRetainedValue() as String? {
                names.append(s)
            } else {
                names.append("MIDI-källa \(i + 1)")
            }
        }
        DispatchQueue.main.async {
            self.sources = names
            if self.selectedSource == nil, !names.isEmpty {
                self.connect(index: 0)
            }
        }
    }

    public func connect(index: Int) {
        guard index >= 0, index < MIDIGetNumberOfSources() else { return }
        if connectedEndpoint != 0 {
            MIDIPortDisconnectSource(inputPort, connectedEndpoint)
        }
        let ep = MIDIGetSource(index)
        if MIDIPortConnectSource(inputPort, ep, nil) == noErr {
            connectedEndpoint = ep
            DispatchQueue.main.async {
                self.selectedSource = index
                self.isConnected = true
                self.lastEvent = "Ansluten: \(self.sources[index])"
            }
        }
    }

    public func disconnect() {
        if connectedEndpoint != 0 {
            MIDIPortDisconnectSource(inputPort, connectedEndpoint)
            connectedEndpoint = 0
        }
        DispatchQueue.main.async { self.isConnected = false }
    }

    private func handlePacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        let rawPtr = UnsafeRawPointer(packetList)
        let packetOffset = MemoryLayout<UInt32>.stride
        var packetPtr = rawPtr.advanced(by: packetOffset).assumingMemoryBound(to: MIDIPacket.self)
        for _ in 0..<packetList.pointee.numPackets {
            let packet = packetPtr.pointee
            let bytes = withUnsafeBytes(of: packet.data) { Array($0.prefix(Int(packet.length))) }
            parse(bytes: bytes)
            packetPtr = UnsafePointer(MIDIPacketNext(packetPtr))
        }
    }

    private func parse(bytes: [UInt8]) {
        var i = 0
        while i < bytes.count {
            let status = bytes[i]
            let kind = status & 0xF0
            if kind == 0x90, i + 2 < bytes.count {
                let note = bytes[i + 1], vel = bytes[i + 2]
                if vel == 0 {
                    noteOff(note)
                } else {
                    noteOn(note, vel)
                }
                i += 3
            } else if kind == 0x80, i + 2 < bytes.count {
                noteOff(bytes[i + 1])
                i += 3
            } else {
                i += 1
            }
        }
    }

    private func noteOn(_ note: UInt8, _ vel: UInt8) {
        DispatchQueue.main.async {
            self.lastEvent = "Note On \(TrackerCell.noteName(note)) vel \(vel)"
        }
        onNoteOn?(note, vel)
    }

    private func noteOff(_ note: UInt8) {
        DispatchQueue.main.async {
            self.lastEvent = "Note Off \(TrackerCell.noteName(note))"
        }
        onNoteOff?(note)
    }
}
