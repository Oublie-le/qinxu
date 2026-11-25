import Foundation
import CoreML
import AVFoundation

/// The unmodified Spotify ICASSP 2022 CoreML model. Owned by one analysis queue.
final class BasicPitchModel {
    static let sampleRate = 22_050.0
    static let sampleCount = 43_844
    static let frameCount = 172
    static let frameHop = 256.0 / sampleRate
    static let edgeFrames = 15
    static let revision = "fa5997af0a8210982619003269994a1be25eddf3"
    struct Prediction {
        let notes: [[Float]]
        let onsets: [[Float]]
        let inferenceSeconds: TimeInterval
    }
    enum ModelError: LocalizedError {
        case missing, invalidInput, invalidOutput, resampling
        var errorDescription: String? {
            switch self {
            case .missing: return "此安装包缺少双手识音模型，请更新或重新安装应用。"
            case .invalidInput: return "双手识音的音频格式不正确。"
            case .invalidOutput: return "双手识音模型输出格式不兼容。"
            case .resampling: return "无法转换麦克风采样率。"
            }
        }
    }
    private let model: MLModel

    static var resourceURL: URL? {
        #if SWIFT_PACKAGE
        // A packaged Mac preview keeps SwiftPM resources in the standard Resources folder.
        let bundle = Bundle.main.resourceURL
            .flatMap { Bundle(url: $0.appendingPathComponent("QinXu_QinXuApp.bundle")) } ?? Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: "BasicPitch", withExtension: "mlpackage", subdirectory: "Resources")
            ?? bundle.url(forResource: "BasicPitch", withExtension: "mlpackage")
    }

    init(modelURL: URL? = BasicPitchModel.resourceURL) throws {
        guard let modelURL else { throw ModelError.missing }
        let compiled = try MLModel.compileModel(at: modelURL)
        defer { try? FileManager.default.removeItem(at: compiled) }
        let configuration = MLModelConfiguration()
        // Matches upstream's CoreML runtime choice; benchmark A13 before changing it.
        configuration.computeUnits = .cpuOnly
        model = try MLModel(contentsOf: compiled, configuration: configuration)
        let input = model.modelDescription.inputDescriptionsByName["input_2"]?.multiArrayConstraint
        guard input?.shape.map(\.intValue) == [1, Self.sampleCount, 1] else { throw ModelError.invalidInput }
    }

    func predict(samples: [Float]) throws -> Prediction {
        guard samples.count == Self.sampleCount, samples.allSatisfy(\.isFinite) else { throw ModelError.invalidInput }
        let input = try MLMultiArray(shape: [1, NSNumber(value: Self.sampleCount), 1], dataType: .float32)
        let pointer = input.dataPointer.bindMemory(to: Float.self, capacity: Self.sampleCount)
        for index in samples.indices { pointer[index] = samples[index] }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["input_2": input])
        let start = ProcessInfo.processInfo.systemUptime
        let result = try model.prediction(from: provider)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        guard let notes = result.featureValue(for: "Identity_1")?.multiArrayValue,
              let onsets = result.featureValue(for: "Identity_2")?.multiArrayValue,
              notes.shape.map(\.intValue) == [1, Self.frameCount, 88],
              onsets.shape.map(\.intValue) == [1, Self.frameCount, 88] else { throw ModelError.invalidOutput }
        return Prediction(notes: try matrix(notes), onsets: try matrix(onsets), inferenceSeconds: elapsed)
    }

    private func matrix(_ array: MLMultiArray) throws -> [[Float]] {
        // CoreML outputs have padded row strides (e.g. 96, not 88); never flatten blindly.
        guard array.dataType == .float32 else { throw ModelError.invalidOutput }
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.strides[0].intValue)
        let rowStride = array.strides[1].intValue, columnStride = array.strides[2].intValue
        var rows: [[Float]] = []
        for frame in 0..<Self.frameCount {
            let row = (0..<88).map { pointer[frame * rowStride + $0 * columnStride] }
            guard row.allSatisfy(\.isFinite) else { throw ModelError.invalidOutput }
            rows.append(row)
        }
        return rows
    }

    static func resample(_ samples: [Float], from sampleRate: Double) throws -> [Float] {
        guard sampleRate > 0, !samples.isEmpty,
              let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(sampleCount)),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { throw ModelError.resampling }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in input.floatChannelData![0].update(from: source.baseAddress!, count: samples.count) }
        converter.primeMethod = .none
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .endOfStream; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        guard status != .error, error == nil, output.frameLength == AVAudioFrameCount(sampleCount) else {
            throw error ?? ModelError.resampling as NSError
        }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: sampleCount))
    }
}
