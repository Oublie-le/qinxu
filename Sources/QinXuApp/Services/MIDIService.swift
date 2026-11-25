import Foundation
import Combine
import CoreMIDI
import Darwin
import QinXuCore

struct MIDISource: Identifiable, Equatable {
    let id: Int32
    let name: String
    let endpoint: MIDIEndpointRef
}

@MainActor
final class MIDIService: ObservableObject {
    @Published private(set) var sources: [MIDISource] = []
    @Published private(set) var selectedSourceID: Int32?
    @Published private(set) var status = "正在查找 MIDI 钢琴…"
    @Published private(set) var connected = false
    var onEvent: ((NoteInput, TimeInterval) -> Void)?
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var endpoint = MIDIEndpointRef()
    private var decoder = MIDIStreamDecoder()
    private var generation = 0

    init(deviceAccessEnabled: Bool = true) {
        guard deviceAccessEnabled else {
            status = "MIDI 设备访问已停用"; return
        }
        let result = MIDIClientCreateWithBlock("琴序" as CFString, &client) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        guard result == noErr else { status = "MIDI 初始化失败（\(result)）"; return }
        refresh()
    }

    func refresh() {
        guard client != 0 else { return }
        sources = (0..<MIDIGetNumberOfSources()).compactMap { index in
            let source = MIDIGetSource(index)
            guard source != 0 else { return nil }
            var unique = Int32(bitPattern: source)
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &unique)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name)
            return MIDISource(id: unique, name: name?.takeRetainedValue() as String? ?? "MIDI 设备 \(index + 1)", endpoint: source)
        }
        if let selectedSourceID, let source = sources.first(where: { $0.id == selectedSourceID }), source.endpoint == endpoint { return }
        selectSource(sources.first?.id)
    }

    func selectSource(_ id: Int32?) {
        generation += 1
        if endpoint != 0 && port != 0 { MIDIPortDisconnectSource(port, endpoint) }
        if port != 0 { MIDIPortDispose(port); port = 0 }
        endpoint = 0; connected = false; selectedSourceID = nil
        decoder = MIDIStreamDecoder()
        onEvent?(.allNotesOff, ProcessInfo.processInfo.systemUptime)
        guard let source = sources.first(where: { $0.id == id }) else {
            status = "未连接钢琴 · 请通过 USB 连接支持 MIDI 的设备"
            return
        }
        let capturedGeneration = generation
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let secondsPerTick = Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        let result = MIDIInputPortCreateWithBlock(client, "钢琴输入" as CFString, &port) { [weak self] list, _ in
            // MIDIPacketList is variable length. Walk the original pointer, never a copied first packet.
            let offset = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
            var packet = UnsafeRawPointer(list).advanced(by: offset).assumingMemoryBound(to: MIDIPacket.self)
            var batches: [([UInt8], TimeInterval)] = []
            for _ in 0..<list.pointee.numPackets {
                let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \.data)!
                let bytes = UnsafeRawPointer(packet).advanced(by: dataOffset).assumingMemoryBound(to: UInt8.self)
                let array = Array(UnsafeBufferPointer(start: bytes, count: Int(packet.pointee.length)))
                let timestamp = packet.pointee.timeStamp == 0 ? ProcessInfo.processInfo.systemUptime : Double(packet.pointee.timeStamp) * secondsPerTick
                batches.append((array, timestamp))
                packet = UnsafePointer(MIDIPacketNext(packet))
            }
            Task { @MainActor in
                guard let self, self.generation == capturedGeneration else { return }
                for (bytes, time) in batches {
                    for event in self.decoder.feed(bytes) { self.onEvent?(event, time) }
                }
            }
        }
        guard result == noErr else { status = "MIDI 输入创建失败（\(result)）"; return }
        let connectResult = MIDIPortConnectSource(port, source.endpoint, nil)
        guard connectResult == noErr else {
            MIDIPortDispose(port); port = 0
            status = "连接失败（\(connectResult)）"; return
        }
        endpoint = source.endpoint; selectedSourceID = source.id; connected = true
        status = "已连接 · \(source.name)"
    }

    deinit {
        if port != 0 { MIDIPortDispose(port) }
        if client != 0 { MIDIClientDispose(client) }
    }
}
