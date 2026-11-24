import Testing
@testable import PianoCore

@Suite struct MIDIStreamDecoderTests {
    @Test func fragmentationRunningStatusAndRealtime() {
        var d = MIDIStreamDecoder()
        expectEqual(d.feed([0x90, 60]), [])
        expectEqual(d.feed([0xF8, 100, 64, 90]), [.on(pitch: 60, velocity: 100), .on(pitch: 64, velocity: 90)])
        expectEqual(d.feed([60, 0]), [.off(pitch: 60)])
        expectEqual(d.feed([0xF0, 1, 2, 0xF8, 3, 0xF7, 61, 80]), [])
        expectEqual(d.feed([0x80, 64, 30]), [.off(pitch: 64)])
    }

    @Test func channelAggregationAndChannelLocalPanic() {
        var d = MIDIStreamDecoder()
        expectEqual(d.feed([0x90, 60, 100, 0x91, 60, 90]), [.on(pitch: 60, velocity: 100)])
        expectEqual(d.feed([0x80, 60, 0]), [])
        expectEqual(d.feed([0xB1, 123, 0]), [.off(pitch: 60)])
        expectEqual(d.feed([0xB0, 64, 127, 0xB1, 64, 100]), [.sustain(true)])
        expectEqual(d.feed([0xB0, 121, 0]), [])
        expectEqual(d.feed([0xB1, 64, 0]), [.sustain(false)])
    }

    @Test func resetAndUnsupportedMessagesPreserveFraming() {
        var d = MIDIStreamDecoder()
        expectEqual(d.feed([0xC0, 60, 61, 0xD0, 40, 0xF2, 0, 4, 60, 80]), [])
        expectEqual(d.feed([0x90, 60, 80]), [.on(pitch: 60, velocity: 80)])
        expectEqual(d.feed([0xFF, 61, 100]), [.allNotesOff])
        expectEqual(d.feed([0x90, 60, 90]), [.on(pitch: 60, velocity: 90)])
        expectEqual(d.feed([0x90, 61, 0x91, 62, 90]), [.on(pitch: 62, velocity: 90)])
    }
}
