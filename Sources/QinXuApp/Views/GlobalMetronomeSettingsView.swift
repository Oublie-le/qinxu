import SwiftUI
import QinXuCore

/// Draft timing stays local until the store accepts the complete, valid configuration.
struct GlobalMetronomeSettingsView: View {
    @ObservedObject var model: PracticeViewModel
    @State private var draft: GlobalMetronomeSettings
    @State private var saveFailure: String?

    init(model: PracticeViewModel) {
        self.model = model
        _draft = State(initialValue: model.metronomeSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("全局节拍器", systemImage: "metronome")
                    .font(.system(size: 18, weight: .semibold))
                Spacer(minLength: 4)
                Button("取消") { model.showingMetronomeSettings = false }
                    .buttonStyle(.plain).font(.system(size: 13))
                    .accessibilityIdentifier("globalMetronome.cancel")
                Button("保存", action: save)
                    .buttonStyle(QuietButtonStyle(prominent: true))
                    .disabled(draft.validationMessage != nil)
                    .accessibilityIdentifier("globalMetronome.save")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(QinXuTheme.paper)
            .overlay(alignment: .bottom) { Rectangle().fill(QinXuTheme.line).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    liveControls
                    Text("调整设置 · 保存后生效")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(QinXuTheme.muted)
                    tempoCard
                    meterCard
                    if let message = draft.validationMessage {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.system(size: 12)).foregroundStyle(QinXuTheme.wrong)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("globalMetronome.validation")
                    }
                    if let saveFailure {
                        Label(saveFailure, systemImage: "exclamationmark.circle")
                            .font(.system(size: 12)).foregroundStyle(QinXuTheme.wrong)
                            .accessibilityIdentifier("globalMetronome.saveError")
                    }
                    Text("所有曲目跟随全局速度；节拍器拍号只决定重拍循环，不改变谱面拍号。")
                        .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("globalMetronome.scroll")
        }
        .frame(minWidth: 320, minHeight: 280)
        .background(QinXuTheme.background)
        .foregroundStyle(QinXuTheme.ink)
        .tint(QinXuTheme.accent)
        .accessibilityIdentifier("globalMetronome.sheet")
    }

    private var liveControls: some View {
        PracticeCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.metronomeRunning ? "正在运行" : "当前设置")
                            .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                        Text("\(model.metronomeSettings.beatsPerMeasure)/\(model.metronomeSettings.beatUnit) · \(model.metronomeSettings.tempoNote.symbol) \(Int(model.metronomeSettings.tempoBPM))/分 · 每响\(model.metronomeSettings.clickNote.title)")
                            .font(.system(size: 13, weight: .medium)).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("当前全局节拍器设置")
                    .accessibilityValue("\(model.metronomeSettings.beatsPerMeasure)/\(model.metronomeSettings.beatUnit)，\(model.metronomeSettings.tempoNote.title)每分钟 \(Int(model.metronomeSettings.tempoBPM)) 次，每响\(model.metronomeSettings.clickNote.title)")
                    .accessibilityIdentifier("globalMetronome.summary")
                    Spacer(minLength: 4)
                    Button { model.toggleMetronome() } label: {
                        Label(model.metronomeRunning ? "停止" : "启动", systemImage: model.metronomeRunning ? "stop.fill" : "play.fill")
                    }.buttonStyle(QuietButtonStyle(prominent: true))
                        .accessibilityLabel(model.metronomeRunning ? "停止节拍器" : "启动节拍器")
                        .accessibilityIdentifier("globalMetronome.toggle")
                }
                HStack(spacing: 10) {
                    beatIndicator
                    Spacer(minLength: 8)
                    Toggle("声音", isOn: Binding(get: { model.metronomeEnabled }, set: { model.metronomeEnabled = $0 }))
                        .font(.system(size: 12)).fixedSize()
                        .disabled(!model.metronomeSoundAvailable)
                        .accessibilityIdentifier("globalMetronome.sound")
                }
                if !model.metronomeSoundAvailable {
                    Text("麦克风录音期间仅闪拍，避免节拍声干扰识音。")
                        .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                }
            }
        }
    }

    private var beatIndicator: some View {
        HStack(spacing: 4) {
            ForEach(1...model.metronomeSettings.beatsPerMeasure, id: \.self) { beat in
                Circle().fill(model.metronomeBeat == beat ? QinXuTheme.accent : QinXuTheme.line)
                    .frame(width: beat == 1 ? 9 : 6, height: beat == 1 ? 9 : 6)
            }
            if model.metronomeSettings.pulsesPerBeat > 1 {
                Text("\(model.metronomeSubdivision ?? 0)/\(model.metronomeSettings.pulsesPerBeat)")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(QinXuTheme.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("节拍指示")
        .accessibilityValue(model.metronomeBeat.map { "第 \($0) 拍，第 \(model.metronomeSubdivision ?? 1) 分拍" } ?? "未运行")
        .accessibilityIdentifier("globalMetronome.beat")
    }

    private var tempoCard: some View {
        PracticeCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Label("速度", systemImage: "speedometer").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(draft.tempoNote.symbol) \(Int(draft.tempoBPM)) / 分")
                        .font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                }
                Slider(value: $draft.tempoBPM, in: 20...300, step: 1)
                    .accessibilityLabel("每分钟所选音符个数")
                    .accessibilityValue(String(Int(draft.tempoBPM)))
                    .accessibilityIdentifier("globalMetronome.tempo")
                HStack {
                    Picker("速度单位", selection: $draft.tempoNote) {
                        ForEach(MetronomeNoteValue.allCases, id: \.self) { value in
                            Text(value.title).tag(value)
                                .accessibilityIdentifier("globalMetronome.tempoNote.\(value.rawValue)")
                        }
                    }.pickerStyle(.menu).accessibilityIdentifier("globalMetronome.tempoNote")
                    Spacer(minLength: 4)
                    Stepper("每次调整 1", value: $draft.tempoBPM, in: 20...300, step: 1)
                        .labelsHidden().accessibilityLabel("速度微调")
                        .accessibilityIdentifier("globalMetronome.tempoStepper")
                }
                Text("每分钟 \(Int(draft.tempoBPM)) 个\(draft.tempoNote.title)")
                    .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            }
        }
    }

    private var meterCard: some View {
        PracticeCard(padding: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Label("拍号", systemImage: "music.note.list").font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 6)
                    Picker("每小节拍数", selection: $draft.beatsPerMeasure) {
                        ForEach(1...16, id: \.self) { value in
                            Text(String(value)).tag(value)
                                .accessibilityIdentifier("globalMetronome.beatsPerMeasure.\(value)")
                        }
                    }.pickerStyle(.menu).labelsHidden().accessibilityIdentifier("globalMetronome.beatsPerMeasure")
                    Text("/").foregroundStyle(QinXuTheme.muted)
                    Picker("一拍的音符分母", selection: $draft.beatUnit) {
                        ForEach([2, 4, 8, 16], id: \.self) { value in
                            Text(String(value)).tag(value)
                                .accessibilityIdentifier("globalMetronome.beatUnit.\(value)")
                        }
                    }.pickerStyle(.menu).labelsHidden().accessibilityIdentifier("globalMetronome.beatUnit")
                }
                Divider()
                Picker("每响一次", selection: $draft.clickNote) {
                    ForEach(MetronomeNoteValue.allCases.filter { $0 != .dottedQuarter }, id: \.self) { value in
                        Text(value.title).tag(value)
                            .accessibilityIdentifier("globalMetronome.clickNote.\(value.rawValue)")
                    }
                }.pickerStyle(.menu).font(.system(size: 13)).accessibilityIdentifier("globalMetronome.clickNote")
                Text(draft.pulsesPerBeat > 0 ? "每小节 \(draft.beatsPerMeasure) 拍，每拍响 \(draft.pulsesPerBeat) 次，第一拍加重。" : "请选择不长于一拍、且可整分一拍的音符。")
                    .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            }
        }
    }

    private func save() {
        guard draft.validationMessage == nil else { return }
        // Playback and sound are immediate controls; cancel only discards timing edits.
        var updated = draft
        updated.soundEnabled = model.metronomeSettings.soundEnabled
        if model.updateMetronomeSettings(updated) {
            model.showingMetronomeSettings = false
        } else {
            saveFailure = model.errorMessage ?? "设置尚未保存，请重试。"
        }
    }
}
