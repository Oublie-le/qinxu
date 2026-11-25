import Foundation
import Testing
import QinXuCore
@testable import QinXuApp

@Suite struct BasicPitchModelTests {
    @Test func bundledModelProducesFinitePolyphonicMatricesWithoutSilenceNotes() throws {
        let model = try BasicPitchModel()
        let result = try model.predict(samples: Array(repeating: 0, count: BasicPitchModel.sampleCount))
        #expect(result.notes.count == 172 && result.onsets.count == 172)
        #expect(result.notes.allSatisfy { $0.count == 88 && $0.allSatisfy(\.isFinite) })
        #expect(result.onsets.allSatisfy { $0.count == 88 && $0.allSatisfy(\.isFinite) })
        #expect(result.onsets.flatMap { $0 }.max()! < 0.5)
        #expect(result.inferenceSeconds > 0)
        // This is resource/runtime validation, not evidence of real-piano accuracy.
    }

    @Test func resamplingPreservesFrequencyAndExactModelLength() throws {
        for rate in [44_100.0, 48_000.0] {
            let count = Int(ceil(Double(BasicPitchModel.sampleCount) * rate / BasicPitchModel.sampleRate))
            let audio = (0..<count).map { Float(sin(2 * .pi * 440 * Double($0) / rate) * 0.1) }
            let converted = try BasicPitchModel.resample(audio, from: rate)
            #expect(converted.count == BasicPitchModel.sampleCount)
            let crossings = zip(converted, converted.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
            let estimate = Double(crossings) / (Double(converted.count) / BasicPitchModel.sampleRate)
            #expect(abs(estimate - 440) < 2)
        }
    }

    @Test func audioMailboxKeepsLatestContinuousWindowWhileInferenceIsBusy() throws {
        let mailbox = PolyphonicAudioMailbox(sampleRate: 22_050)
        let first = (0..<30_000).map(Float.init)
        try first.withUnsafeBufferPointer { try mailbox.append($0.baseAddress!, count: $0.count, sampleTime: 0, captureTime: 100) }
        #expect(!mailbox.isReady())
        let next = (30_000..<50_000).map(Float.init)
        try next.withUnsafeBufferPointer { try mailbox.append($0.baseAddress!, count: $0.count, sampleTime: 30_000, captureTime: 100 + 30_000.0 / 22_050) }
        #expect(mailbox.isReady())
        let firstWindow = mailbox.snapshot()
        #expect(firstWindow.samples.count == 43_844)
        #expect(firstWindow.samples.first == 6_156 && firstWindow.samples.last == 49_999)
        #expect(!mailbox.isReady())
        let busy = (50_000..<100_000).map(Float.init)
        try busy.withUnsafeBufferPointer { try mailbox.append($0.baseAddress!, count: $0.count, sampleTime: 50_000, captureTime: 100 + 50_000.0 / 22_050) }
        let latest = mailbox.snapshot()
        #expect(latest.samples.first == 56_156 && latest.samples.last == 99_999)
        #expect(latest.startSample == 56_156 && latest.endSample == 100_000)
        #expect(zip(latest.samples, latest.samples.dropFirst()).allSatisfy { $1 - $0 == 1 })
    }

    @Test func capturedSamplesIgnoreCallbackLatencyAndDetectDiscontinuities() async throws {
        let fast = PolyphonicAudioMailbox(sampleRate: 22_050)
        let delayed = PolyphonicAudioMailbox(sampleRate: 22_050)
        let bridge = AudioCaptureClock(hostSeconds: 1_000, uptime: 100)
        for start in stride(from: 0, to: 50_000, by: 10_000) {
            let audio = (start..<(start + 10_000)).map(Float.init)
            let captureTime = bridge.timestamp(hostSeconds: 1_000 + Double(start) / 22_050)
            try audio.withUnsafeBufferPointer { try fast.append($0.baseAddress!, count: $0.count, sampleTime: Int64(start), captureTime: captureTime) }
            try await Task.sleep(nanoseconds: 1_000_000)
            try audio.withUnsafeBufferPointer { try delayed.append($0.baseAddress!, count: $0.count, sampleTime: Int64(start), captureTime: captureTime) }
        }
        let a = fast.snapshot(), b = delayed.snapshot()
        #expect(a.samples == b.samples && a.startTime == b.startTime && a.startSample == b.startSample)
        #expect(abs(a.startTime - (100 + 6_156.0 / 22_050)) < 0.00001)
        let block = [Float](repeating: 0, count: 100)
        #expect(throws: PolyphonicAudioMailbox.TimelineError.self) {
            try block.withUnsafeBufferPointer { try delayed.append($0.baseAddress!, count: $0.count, sampleTime: 50_100, captureTime: 100 + 50_100.0 / 22_050) }
        }
        #expect(!delayed.isReady())
        #expect(throws: PolyphonicAudioMailbox.TimelineError.self) {
            try block.withUnsafeBufferPointer { try fast.append($0.baseAddress!, count: $0.count, sampleTime: 50_000, captureTime: .nan) }
        }
        #expect(!fast.isReady())
    }

    @Test func eventBatchPreservesSpacingOrderAndStopsAfterSynchronousTeardown() {
        let events = [PolyphonicNoteTracker.Event(pitch: 60, isOn: true, time: 11),
                      .init(pitch: 48, isOn: true, time: 10),
                      .init(pitch: 60, isOn: false, time: 12),
                      .init(pitch: 60, isOn: true, time: 12)]
        var active = true
        var delivered: [PolyphonicNoteTracker.Event] = []
        PolyphonicEventDelivery.deliver(events, while: { active }) { event in
            delivered.append(event)
            if delivered.count == 2 { active = false }
        }
        #expect(delivered.map(\.time) == [10, 11])
        #expect(delivered.map(\.pitch) == [48, 60])
        delivered = []
        PolyphonicEventDelivery.deliver(Array(events.suffix(2)), while: { true }) { delivered.append($0) }
        #expect(delivered.map(\.isOn) == [false, true])
    }

    @Test @MainActor func openingDevicesAfterFailedStartPreservesTheFailure() async {
        let service = PolyphonicMicrophoneService(deviceAccessEnabled: false)
        await service.start()
        #expect(service.status.contains("已停用"))
        service.stop()
        #expect(service.status.contains("已停用"))
        #expect(!service.isActive)
    }

    @Test func missingModelCannotSilentlyUseFakeRecognition() {
        #expect(throws: BasicPitchModel.ModelError.self) { try BasicPitchModel(modelURL: nil) }
    }
}
