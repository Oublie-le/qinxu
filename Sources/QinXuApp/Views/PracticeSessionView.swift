import SwiftUI
import QinXuCore

/// The transport and score use the same live model for MIDI, touch and experimental microphone input.
struct PracticeSessionView: View {
    @ObservedObject var model: PracticeViewModel
    let compact: Bool
    let onExit: () -> Void
    let onShowDevices: () -> Void
    @State private var showingSettings = false

    private var currentMeasure: Int {
        model.engine.expectedNotes.first?.measure
            ?? model.selectedScore.measures.last(where: { $0.startBeat <= model.engine.currentBeat })?.number
            ?? 1
    }

    private var expectedDescription: String {
        model.engine.expectedNotes.map { note in
            let beats = String(format: "%.3g", note.durationBeats)
            let seconds = String(format: "%.2f", note.durationBeats * 60 / model.tempo)
            return "\(note.name) · \(beats) 拍 ≈ \(seconds) 秒"
        }.joined(separator: "；")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 5 : 18) {
                heading
                if !compact { practiceOptions }
                scoreSurface
                if !compact { feedback }
                if !compact { keyboard }
            }
            .padding(compact ? 8 : 24)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("practice.scroll")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if compact { feedback.padding(.horizontal, 8).padding(.top, 4) }
                if compact { keyboard.padding(.horizontal, 8).padding(.top, 4) }
                transport
            }.background(QinXuTheme.paper)
        }
        .background(QinXuTheme.background)
        .foregroundStyle(QinXuTheme.ink)
        .sheet(isPresented: $showingSettings) { settings }
    }

    private var heading: some View {
        HStack(spacing: 12) {
            Button(action: onExit) { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .accessibilityLabel("返回曲谱详情")
                .accessibilityIdentifier("practice.back")
            VStack(alignment: .leading, spacing: 4) {
                Text(model.selectedScore.title)
                    .font(.system(size: compact ? 18 : 27, weight: .semibold))
                    .lineLimit(compact ? 1 : 2)
                    .accessibilityIdentifier("practice.score.title")
                if !compact {
                    Text("\(model.selectedScore.composer) · \(model.selectedScore.beatsPerMeasure)/\(model.selectedScore.beatUnit) 拍 · \(model.selectedScore.measures.count) 小节")
                        .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
                }
            }
            Spacer(minLength: 6)
            if compact {
                Button { showingSettings = true } label: {
                    Label("\(model.mode.title) · \(model.hand.title)", systemImage: "slider.horizontal.3")
                        .font(.system(size: 11))
                }.buttonStyle(.plain).accessibilityIdentifier("practice.settings")
            }
            Button(action: onShowDevices) {
                Label(model.inputMode.title, systemImage: model.inputMode == .touch ? "hand.tap" : "cable.connector")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain).font(.system(size: 11))
            .foregroundStyle(QinXuTheme.muted)
            .accessibilityIdentifier("practice.devices")
        }
    }

    private var practiceOptions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: compact ? 12 : 20) {
                modePicker.frame(width: compact ? 188 : 235)
                Spacer(minLength: 8)
                handPicker.frame(width: compact ? 170 : 210)
                settingsButton
            }
            VStack(spacing: 8) {
                modePicker
                HStack { handPicker; settingsButton }
            }
        }
    }

    private var modePicker: some View {
        Picker("练习模式", selection: $model.mode) {
            ForEach(PracticeMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden()
        .accessibilityIdentifier("practice.mode")
        .onChange(of: model.mode) { _, _ in model.reconfigure() }
    }

    private var handPicker: some View {
        Picker("练习手", selection: $model.hand) {
            ForEach(PracticeHand.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden()
        .accessibilityIdentifier("practice.hand")
        .onChange(of: model.hand) { _, _ in model.reconfigure() }
    }

    private var settingsButton: some View {
        Button { showingSettings = true } label: {
            Image(systemName: "slider.horizontal.3").frame(width: 32, height: 30)
        }.buttonStyle(.plain)
            .accessibilityLabel("速度、循环与谱面说明")
            .accessibilityIdentifier("practice.settings")
    }

    private var scoreSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !compact {
            HStack(spacing: 10) {
                Text("第 \(currentMeasure) / \(model.selectedScore.measures.count) 小节")
                    .monospacedDigit()
                Spacer(minLength: 5)
                if model.loopEnabled {
                    Label("\(model.loopStart)–\(model.loopEnd) 小节", systemImage: "repeat")
                        .foregroundStyle(QinXuTheme.accent)
                }
                Button { showingSettings = true } label: {
                    Label(model.selectedScore.warnings.isEmpty ? "简化练习谱" : "谱面提示 \(model.selectedScore.warnings.count)", systemImage: "info.circle")
                }.buttonStyle(.plain).accessibilityIdentifier("practice.notationInfo")
            }
            .font(.system(size: compact ? 10 : 11))
            .foregroundStyle(QinXuTheme.muted)
            .padding(.horizontal, compact ? 12 : 20).padding(.top, compact ? 8 : 15)
            }

            if model.selectedScore.notes.contains(where: { model.hand.includes(staff: $0.staff) }) {
                PracticeScoreView(score: model.selectedScore, hand: model.hand,
                                  currentBeat: model.engine.currentBeat, expectedNotes: model.engine.expectedNotes,
                                  verdicts: model.engine.verdicts, active: model.isPlaying, compact: compact)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "music.note").font(.system(size: 24))
                    Text("曲谱没有\(model.hand.title)声部的音符")
                    Text("请选择双手或其他曲谱").font(.system(size: 11))
                }.foregroundStyle(QinXuTheme.muted).frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 24 : 65)
            }
        }
        .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: compact ? 12 : 18))
        .overlay(RoundedRectangle(cornerRadius: compact ? 12 : 18).stroke(QinXuTheme.line, lineWidth: 1))
    }

    private var feedback: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) { feedbackText; Spacer(minLength: 8); counters }
            VStack(alignment: .leading, spacing: 7) { feedbackText; counters }
        }
        .padding(.horizontal, compact ? 10 : 16).padding(.vertical, compact ? 7 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QinXuTheme.sage, in: RoundedRectangle(cornerRadius: 10))
    }

    private var feedbackText: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let countdown = model.countdown {
                Text("预备 · \(countdown)").font(.system(size: compact ? 16 : 23, weight: .semibold))
                    .foregroundStyle(QinXuTheme.accent)
                    .accessibilityIdentifier("practice.countdown")
            } else {
                Text(model.engine.feedback).font(.system(size: compact ? 11 : 13, weight: .medium))
                    .accessibilityIdentifier("practice.feedback")
            }
            if !expectedDescription.isEmpty {
                Text(expectedDescription)
                    .font(.system(size: compact ? 10 : 11, design: .monospaced))
                    .foregroundStyle(QinXuTheme.muted)
                    .accessibilityIdentifier("practice.expected")
            }
            if model.inputMode != .microphonePolyphonic, let durationFeedback = model.engine.durationFeedback {
                Text(durationFeedback).font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            }
            if model.inputMode.isMicrophone {
                Label(model.inputStatus, systemImage: "mic")
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(QinXuTheme.muted)
                    .accessibilityIdentifier("practice.microphoneStatus")
            }
        }
    }

    private var counters: some View {
        HStack(spacing: compact ? 10 : 18) {
            counter("正确", identifier: "practice.count.correct", count: model.engine.correctCount, color: QinXuTheme.teal)
            counter("错音", identifier: "practice.count.wrong", count: model.engine.wrongCount, color: QinXuTheme.wrong)
            counter("漏音", identifier: "practice.count.missed", count: model.engine.missedCount, color: QinXuTheme.muted)
        }
    }

    private func counter(_ title: String, identifier: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").font(.system(size: compact ? 14 : 20, weight: .medium)).monospacedDigit().foregroundStyle(color)
            Text(title).font(.system(size: 10)).foregroundStyle(QinXuTheme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityValue(String(count)).accessibilityIdentifier(identifier)
    }

    private var keyboard: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 12) {
            if !compact {
                HStack {
                    Label("键盘指引", systemImage: "pianokeys").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Label("待弹", systemImage: "circle").foregroundStyle(QinXuTheme.teal)
                    Label("应保持", systemImage: "circle.fill").foregroundStyle(QinXuTheme.accent.opacity(0.5))
                    Label(model.inputMode.isMicrophone ? "声音" : "按下", systemImage: "circle.fill")
                        .foregroundStyle(QinXuTheme.accent)
                }.font(.system(size: 11))
            }
            PianoKeyboardView(pitchRange: PianoKeyboardRange.forScore(model.selectedScore, hand: model.hand),
                              expectedPitches: Set(model.engine.expectedNotes.map(\.midi)),
                              heldPitches: model.engine.heldPitches,
                              sustainedPitches: model.sustainedPitches,
                              interactive: model.inputMode == .touch, press: model.press,
                              release: model.release, representsSound: model.inputMode.isMicrophone, compact: compact)
            if model.inputMode.isMicrophone {
                Text(compact ? "绿色待弹 · 浅橙应保持 · 橙色声音；余音不是新的按键。" : "整首音域固定，可横向滑动。浅橙色延音按谱面时值提示；余音不是新的按键。")
                    .font(.system(size: compact ? 9 : 11)).foregroundStyle(QinXuTheme.muted)
            } else if !compact {
                Text(model.inputMode == .touch ? "整首音域固定；可横向滑动。触屏按住可延音，松开即释放；按键暂不发声。" : "整首音域固定；可横向滑动。键盘显示待弹与已按下的音符。")
                    .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            }
        }
    }

    private var transport: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: compact ? 10 : 22) { tempoButton; Spacer(minLength: 8); playControls; Spacer(minLength: 8); loopButton }
            VStack(spacing: 7) {
                playControls
                HStack { tempoButton; Spacer(); loopButton }
            }
        }
        .padding(.horizontal, compact ? 12 : 24).padding(.vertical, compact ? 5 : 12)
        .background(QinXuTheme.paper)
        .overlay(alignment: .top) { Rectangle().fill(QinXuTheme.line).frame(height: 1) }
    }

    private var tempoButton: some View {
        Button { showingSettings = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "metronome")
                Text("\(Int(model.tempo))").font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit()
                Text("BPM").font(.system(size: 10))
            }.padding(.vertical, 7)
        }.buttonStyle(.plain).accessibilityLabel("速度 \(Int(model.tempo)) BPM，轻点调整")
    }

    private var playControls: some View {
        HStack(spacing: 8) {
            Button { model.restart() } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(QuietButtonStyle()).accessibilityLabel("从头再练")
                .accessibilityIdentifier("practice.restart")
            Button { model.togglePlayback() } label: {
                Label(model.isPlaying ? "暂停" : (model.engine.isFinished ? "再练一次" : "开始练习"),
                      systemImage: model.isPlaying ? "pause.fill" : "play.fill")
            }.buttonStyle(QuietButtonStyle(prominent: true))
                .accessibilityIdentifier("practice.play")
        }
    }

    private var loopButton: some View {
        Button { showingSettings = true } label: {
            Label(model.loopEnabled ? "\(model.loopStart)–\(model.loopEnd)" : "小节循环", systemImage: "repeat")
                .font(.system(size: 11)).foregroundStyle(model.loopEnabled ? QinXuTheme.accent : QinXuTheme.muted)
                .padding(.vertical, 10)
        }.buttonStyle(.plain).accessibilityIdentifier("practice.loopSettings")
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("模式与分手") {
                    modePicker
                    handPicker
                }
                Section("速度") {
                    HStack {
                        Image(systemName: "metronome")
                        Text("\(Int(model.tempo)) BPM").monospacedDigit()
                    }
                    Slider(value: Binding(get: { model.tempo }, set: { model.tempo = $0.rounded() }), in: 20...300,
                           onEditingChanged: { editing in if !editing { model.reconfigure() } })
                        .accessibilityLabel("速度，四分音符每分钟")
                    if model.mode == .rhythm {
                        Toggle("节拍器声音", isOn: $model.metronomeEnabled)
                    }
                }
                Section("小节循环") {
                    Toggle("启用循环", isOn: $model.loopEnabled)
                        .onChange(of: model.loopEnabled) { _, _ in model.reconfigure() }
                    if model.loopEnabled {
                        Picker("起始小节", selection: $model.loopStart) {
                            ForEach(model.selectedScore.measures) { Text("\($0.number)").tag($0.number) }
                        }.onChange(of: model.loopStart) { _, value in
                            if model.loopEnd < value { model.loopEnd = value }
                            model.reconfigure()
                        }
                        Picker("结束小节", selection: $model.loopEnd) {
                            ForEach(model.selectedScore.measures.filter { $0.number >= model.loopStart }) { Text("\($0.number)").tag($0.number) }
                        }.onChange(of: model.loopEnd) { _, _ in model.reconfigure() }
                    }
                }
                Section("谱面与输入说明") {
                    Text("简化练习谱按实际音高与四分音符拍点排布，临时记号按小节处理，留白表示休止；未还原原谱连线、表情与版式。")
                    ForEach(model.selectedScore.warnings, id: \.self) { Text($0).foregroundStyle(QinXuTheme.amber) }
                    Text("触屏琴键暂不发声。麦克风提供实验性单音与多音识谱；多音需要缓冲音频，实琴准确率和设备延迟尚待验证，不用于节奏或按键时长评分。")
                }
            }
            .font(.system(size: 13))
            .navigationTitle("练习设置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingSettings = false } } }
        }
        .tint(QinXuTheme.accent)
        .frame(minWidth: 320, minHeight: 280)
        .onAppear { model.suspendForBackground() }
    }
}
