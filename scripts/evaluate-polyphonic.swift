// Offline, labeled-audio probe using exactly the app model and acoustic tracker.
// swiftc Sources/QinXuApp/Services/BasicPitchModel.swift Sources/QinXuCore/PolyphonicNoteTracker.swift scripts/evaluate-polyphonic.swift -o /tmp/qinxu-poly-eval
import Foundation
import AVFoundation

@main enum PolyphonicEvaluation {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            print("Usage: qinxu-poly-eval MODEL.mlpackage RECORDING.wav OUTPUT.json"); return
        }
        let model = try BasicPitchModel(modelURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[2]))
        let format = file.processingFormat
        let length = AVAudioFrameCount(file.length)
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: length)!
        try file.read(into: input)
        var mono = Array(repeating: Float(0), count: Int(input.frameLength))
        for channel in 0..<Int(format.channelCount) {
            for index in mono.indices { mono[index] += input.floatChannelData![channel][index] / Float(format.channelCount) }
        }
        let nativeWindow = Int(ceil(Double(BasicPitchModel.sampleCount) * format.sampleRate / BasicPitchModel.sampleRate))
        let step = Int(format.sampleRate * 0.2)
        var tracker = PolyphonicNoteTracker()
        var lastFrame = -Double.infinity
        var lastFrameIndex: Int64 = -1
        var pendingEvents: [PolyphonicNoteTracker.Event] = []
        var events: [[String: Any]] = []
        var latencies: [Double] = []
        var analysisSeconds: [Double] = []
        var maxPolyphony = 0
        let start = ProcessInfo.processInfo.systemUptime
        for offset in stride(from: 0, through: mono.count - nativeWindow, by: step) {
            let audio = try BasicPitchModel.resample(Array(mono[offset..<(offset + nativeWindow)]), from: format.sampleRate)
            let p = try model.predict(samples: audio)
            latencies.append(p.inferenceSeconds)
            let baseFrame = Int64(floor(Double(offset) / format.sampleRate / BasicPitchModel.frameHop))
            for frame in BasicPitchModel.edgeFrames..<(BasicPitchModel.frameCount - BasicPitchModel.edgeFrames) {
                let time = Double(offset) / format.sampleRate + Double(frame) * BasicPitchModel.frameHop
                let frameIndex = baseFrame + Int64(frame)
                lastFrame = time
                guard frameIndex > lastFrameIndex else { continue }
                pendingEvents += tracker.consume(notes: p.notes[frame], onsets: p.onsets[frame], at: time)
                lastFrameIndex = frameIndex
                maxPolyphony = max(maxPolyphony, tracker.activePitches.count)
            }
            let horizon = lastFrame - 11 * BasicPitchModel.frameHop
            pendingEvents.removeAll { event in
                guard event.time <= horizon else { return false }
                let delivered = Double(offset + nativeWindow) / format.sampleRate + p.inferenceSeconds
                if event.isOn { analysisSeconds.append(delivered - event.time) }
                events.append(["pitch": event.pitch, "isOn": event.isOn, "time": event.time, "delivered": delivered])
                return true
            }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let output: [String: Any] = ["events": events, "audioSeconds": Double(mono.count) / format.sampleRate,
            "firstAnalyzed": Double(BasicPitchModel.edgeFrames) * BasicPitchModel.frameHop, "lastAnalyzed": lastFrame,
            "windows": latencies.count, "inferenceSeconds": latencies, "deliveryDelaySeconds": analysisSeconds,
            "maxActivePitches": maxPolyphony, "processingSeconds": elapsed, "modelRevision": BasicPitchModel.revision,
            "note": "Offline Mac CoreML replay; not live iPad latency or microphone accuracy. No score constraints."]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
        print("windows=\(latencies.count) processing=\(elapsed)s maxPolyphony=\(maxPolyphony) onsets=\(events.filter { $0["isOn"] as? Bool == true }.count)")
    }
}
