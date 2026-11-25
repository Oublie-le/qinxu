import SwiftUI
import QinXuCore

/// Device lifecycle remains in the existing services; this view only displays and selects input.
struct InputConnectionView: View {
    @ObservedObject private var model: PracticeViewModel
    @ObservedObject private var midi: MIDIService
    @ObservedObject private var microphone: MicrophoneService
    @ObservedObject private var polyphonic: PolyphonicMicrophoneService

    init(model: PracticeViewModel) {
        self.model = model
        self.midi = model.midi
        self.microphone = model.microphone
        self.polyphonic = model.polyphonicMicrophone
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("输入方式", selection: Binding(get: { model.inputMode }, set: { model.setInputMode($0) })) {
                    Label("MIDI 钢琴", systemImage: "cable.connector").tag(InputMode.midi)
                    Label("屏幕琴键", systemImage: "hand.tap").tag(InputMode.touch)
                    Label("单音 · 实验", systemImage: "mic").tag(InputMode.microphone)
                    Label("双手 · 实验", systemImage: "waveform").tag(InputMode.microphonePolyphonic)
                }
                .pickerStyle(.segmented).accessibilityIdentifier("devices.inputMode")

                PracticeCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 15) {
                        switch model.inputMode {
                        case .midi: midiContent
                        case .touch: touchContent
                        case .microphone: microphoneContent
                        case .microphonePolyphonic: polyphonicContent
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .foregroundStyle(QinXuTheme.ink)
        .background(QinXuTheme.background)
        .tint(QinXuTheme.accent)
    }

    private var midiContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: midi.connected ? "checkmark.circle.fill" : "cable.connector")
                    .foregroundStyle(midi.connected ? QinXuTheme.teal : QinXuTheme.amber)
                Text(midi.status).font(.system(size: 13, weight: .medium))
                    .accessibilityIdentifier("devices.midiStatus")
                Spacer(minLength: 8)
                Button { model.refreshMIDI() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("devices.refresh")
            }
            Picker("MIDI 来源", selection: Binding<Int32?>(get: { midi.selectedSourceID }, set: { midi.selectSource($0) })) {
                Text("选择设备").tag(Optional<Int32>.none)
                ForEach(midi.sources) { source in Text(source.name).tag(Optional(source.id)) }
            }.accessibilityIdentifier("devices.midiSource")
            Text("通过 USB MIDI 或系统已连接的蓝牙 MIDI 输入。这里不输出钢琴音色或伴奏。")
                .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
        }
    }

    private var touchContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("屏幕琴键已启用", systemImage: "hand.tap").font(.system(size: 15, weight: .medium))
                .foregroundStyle(QinXuTheme.teal)
            Text("按住琴键可延音，松开即释放；可用多指弹奏和弦。")
            Text("按键暂不发声。连接 MIDI 钢琴可使用实体琴键练习。")
                .foregroundStyle(QinXuTheme.muted)
        }.font(.system(size: 12))
    }

    private var microphoneContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(systemName: microphone.isActive ? "mic.fill" : "mic")
                    .foregroundStyle(microphone.isActive ? QinXuTheme.teal : QinXuTheme.amber)
                Text(microphone.status).font(.system(size: 13))
                    .accessibilityIdentifier("devices.microphoneStatus")
                Spacer(minLength: 8)
                if let pitch = microphone.detectedPitch {
                    Text(NoteNames.name(pitch)).font(.system(size: 20, weight: .medium, design: .monospaced))
                        .foregroundStyle(QinXuTheme.teal)
                }
            }
            ProgressView(value: min(1, max(0, microphone.level)))
                .accessibilityLabel("麦克风输入音量")
            Label("实验性单音识别 · C3–C6", systemImage: "flask")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(QinXuTheme.amber)
            Text("只支持识谱模式逐个弹音；请在安静环境中练习，不使用延音踏板。和弦、双手同时演奏与节奏评分暂不支持。实琴准确率尚未验证。")
                .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
        }
    }
    private var polyphonicContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(polyphonic.status, systemImage: polyphonic.isActive ? "waveform" : "mic")
                .font(.system(size: 13)).accessibilityIdentifier("devices.polyphonicStatus")
            if !polyphonic.detectedPitches.isEmpty {
                Text(polyphonic.detectedPitches.sorted().map { NoteNames.name($0) }.joined(separator: " · "))
                    .font(.system(size: 18, weight: .medium, design: .monospaced)).foregroundStyle(QinXuTheme.teal)
            }
            ProgressView(value: min(1, max(0, polyphonic.level))).accessibilityLabel("麦克风输入音量")
            Label("双手与和弦识音 · 实验性 · A0–C8", systemImage: "flask")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(QinXuTheme.amber)
            Text("在 iPad 上离线分析约 2 秒的音频窗口，仅用于识谱等待。首次反馈需等待缓冲，之后也有识别延迟；不评节奏或松键时长。请先不踩踏板，以较慢速度弹奏。")
            Text("使用 Spotify Basic Pitch 多音模型；不根据曲谱补出未听到的音。iPad 9 与电钢琴扬声器的准确率、延迟尚待实测。")
            if let inference = polyphonic.inferenceMilliseconds, let delay = polyphonic.analysisDelayMilliseconds {
                Text("最近一次推理 \(Int(inference)) ms · 分析滞后 \(Int(delay)) ms")
                    .monospacedDigit().accessibilityIdentifier("devices.polyphonicLatency")
            }
            if BasicPitchModel.resourceURL == nil {
                Text("当前构建未包含识音模型，无法启动双手麦克风。")
                    .foregroundStyle(QinXuTheme.amber)
            }
        }.font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
    }

}
