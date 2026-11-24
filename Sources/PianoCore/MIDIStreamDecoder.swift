import Foundation

/// Incremental MIDI 1.0 decoder. Keep one decoder per input source: running
/// status and held channels must never leak between independent devices.
public struct MIDIStreamDecoder {
    private var runningStatus: UInt8?
    private var messageStatus: UInt8?
    private var payload: [UInt8] = []
    private var inSysEx = false
    private var held = Array(repeating: Set<Int>(), count: 16)
    private var pedals = Array(repeating: false, count: 16)

    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [NoteInput] {
        var result: [NoteInput] = []
        for byte in bytes {
            // Real-time messages can occur inside ANY message, even SysEx.
            if byte >= 0xF8 {
                if byte == 0xFF {
                    self = MIDIStreamDecoder()
                    result.append(.allNotesOff)
                }
                continue
            }
            if inSysEx {
                if byte == 0xF7 { inSysEx = false; continue }
                if byte < 0x80 { continue }
                // Another status terminates a malformed/truncated SysEx.
                inSysEx = false
            }
            if byte >= 0x80 {
                payload.removeAll(keepingCapacity: true)
                messageStatus = nil
                if byte < 0xF0 {
                    runningStatus = byte
                    messageStatus = byte
                } else {
                    runningStatus = nil
                    if byte == 0xF0 { inSysEx = true }
                    else if byte == 0xF1 || byte == 0xF2 || byte == 0xF3 { messageStatus = byte }
                }
                continue
            }
            guard let status = messageStatus ?? runningStatus else { continue }
            messageStatus = status
            payload.append(byte)
            let needed: Int
            if status == 0xF2 { needed = 2 }
            else if status >= 0xF0 || status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0 { needed = 1 }
            else { needed = 2 }
            guard payload.count >= needed else { continue }
            if status < 0xF0 { result += decode(status: status, data: payload) }
            payload.removeAll(keepingCapacity: true)
            messageStatus = nil
        }
        return result
    }

    private mutating func decode(status: UInt8, data: [UInt8]) -> [NoteInput] {
        let channel = Int(status & 0x0F)
        let kind = status & 0xF0
        let first = Int(data[0])
        if kind == 0x90 && data[1] > 0 {
            let alreadyHeld = held.contains { $0.contains(first) }
            held[channel].insert(first)
            return alreadyHeld ? [] : [.on(pitch: first, velocity: Int(data[1]))]
        }
        if kind == 0x80 || (kind == 0x90 && data[1] == 0) {
            let wasHeld = held[channel].remove(first) != nil
            return wasHeld && !held.contains(where: { $0.contains(first) }) ? [.off(pitch: first)] : []
        }
        guard kind == 0xB0 else { return [] }
        if first == 64 || first == 121 {
            let previous = pedals.contains(true)
            pedals[channel] = first == 64 ? data[1] >= 64 : false
            let current = pedals.contains(true)
            return current == previous ? [] : [.sustain(current)]
        }
        if first == 120 || first == 123 {
            // Channel-mode commands affect that channel only. Emit individual
            // releases so a note on a second channel cannot be cut off.
            let released = held[channel]
            held[channel].removeAll()
            return released.sorted().filter { pitch in !held.contains { $0.contains(pitch) } }.map { .off(pitch: $0) }
        }
        return []
    }
}
