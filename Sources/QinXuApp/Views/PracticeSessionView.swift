import SwiftUI
import QinXuCore

/// The transport and score use the same live model for MIDI, touch and experimental microphone input.
struct PracticeSessionView: View {
    @ObservedObject var model: PracticeViewModel
    let compact: Bool
    let onExit: () -> Void
    let onShowDevices: () -> Void
    var immersive = false
    var onToggleImmersion: () -> Void = {}
    @State private var showingSettings = false
    @State private var showingModeHelp = false
    @State private var openMetronomeAfterSettings = false
    private var auditionIsOpen: Bool {
        model.auditionScoreID == model.selectedScoreID && model.auditionPhase != .idle
    }
    private var displayedBeatsPerQuarter: Double { Double(model.selectedScore.beatUnit) / 4 }
    private var meterDiffers: Bool {
        model.metronomeSettings.beatsPerMeasure != model.selectedScore.beatsPerMeasure
            || model.metronomeSettings.beatUnit != model.selectedScore.beatUnit
    }

    private var currentMeasure: Int {
        if auditionIsOpen {
            return model.selectedScore.measures.last(where: { $0.startBeat <= model.auditionBeat })?.number ?? 1
        }
        return model.engine.expectedNotes.first?.measure
            ?? model.selectedScore.measures.last(where: { $0.startBeat <= model.engine.currentBeat })?.number
            ?? 1
    }

    private var expectedDescription: String {
        model.engine.expectedNotes.map { note in
            let beats = String(format: "%.3g", note.durationBeats * displayedBeatsPerQuarter)
            let seconds = String(format: "%.2f", note.durationBeats * 60 / model.tempo)
            return "\(note.name) · \(beats) 拍 ≈ \(seconds) 秒"
        }.joined(separator: "；")
    }

    var body: some View {
        VStack(spacing: 0) {
            heading.padding(.horizontal, compact ? 8 : 24).padding(.vertical, compact ? 0 : 12)
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 5 : 18) {
                    if !compact && !immersive { practiceOptions }
                    scoreSurface
                }
                .padding(.horizontal, compact ? 8 : 24)
                .padding(.top, compact ? 0 : 8).padding(.bottom, compact ? 4 : 20)
                .frame(maxWidth: 1400)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("practice.scroll")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                feedback.padding(.horizontal, compact ? 8 : 20).padding(.top, compact ? 2 : 4)
                keyboard.padding(.horizontal, compact ? 8 : 20).padding(.top, compact ? 2 : 5)
                transport
            }.background(QinXuTheme.paper)
        }
        .background(QinXuTheme.background)
        .foregroundStyle(QinXuTheme.ink)
        .onDisappear {
            if model.auditionScoreID == model.selectedScoreID { model.stopAudition() }
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            if openMetronomeAfterSettings {
                openMetronomeAfterSettings = false
                model.openMetronomeSettings()
            }
        }) { settings }
        .sheet(isPresented: $showingModeHelp) { modeHelp }
        .sheet(isPresented: $model.showingReport) {
            if let report = model.latestReport {
                PracticeReportView(report: report, scoreTitle: model.selectedScore.title, compact: compact,
                    onClose: { model.showingReport = false },
                    onRetry: { model.showingReport = false; model.restart() },
                    onMeasure: { measure in model.showingReport = false; model.practiceMeasure(measure) })
            }
        }
    }

    private var heading: some View {
        HStack(spacing: 12) {
            if !immersive {
                Button(action: onExit) { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .frame(width: 32, height: 32)
                    .accessibilityLabel("返回曲谱详情")
                    .accessibilityIdentifier("practice.back")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.selectedScore.title)
                    .font(.system(size: compact ? 18 : immersive ? 21 : 27, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier("practice.score.title")
                if !compact && !immersive {
                    Text("\(model.selectedScore.composer) · \(model.selectedScore.beatsPerMeasure)/\(model.selectedScore.beatUnit) 拍 · \(model.selectedScore.measures.count) 小节")
                        .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
                }
            }
            Spacer(minLength: 6)
            ScoreAuditionControls(model: model, score: model.selectedScore, identifier: "practice.audition")
            if compact && !immersive {
                Button { showingSettings = true } label: {
                    Label("\(model.mode.title) · \(model.hand.title)", systemImage: "slider.horizontal.3")
                        .font(.system(size: 11))
                }.buttonStyle(.plain).accessibilityIdentifier("practice.settings")
            }
            if !immersive {
                Button(action: onShowDevices) {
                    Label(model.inputMode.title, systemImage: model.inputMode.isMicrophone ? "mic" : model.inputMode == .touch ? "hand.tap" : "cable.connector")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain).font(.system(size: 13))
                .foregroundStyle(QinXuTheme.muted)
                .accessibilityIdentifier("practice.devices")
            }
            Button(action: onToggleImmersion) {
                Label(immersive ? "退出沉浸" : "沉浸", systemImage: immersive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .medium)).padding(.vertical, 8)
            }.buttonStyle(.plain).foregroundStyle(QinXuTheme.accent)
                .accessibilityValue(immersive ? "已开启" : "已关闭")
                .accessibilityIdentifier("practice.immersion")
        }
    }

    private var practiceOptions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: compact ? 12 : 20) {
                modePicker.frame(width: compact ? 188 : 235)
                modeHelpButton
                Spacer(minLength: 8)
                handPicker.frame(width: compact ? 170 : 210)
                settingsButton
            }
            VStack(spacing: 8) {
                modePicker
                HStack { handPicker; modeHelpButton; settingsButton }
            }
        }
    }

    private var modePicker: some View {
        Picker("练习模式", selection: Binding(get: { model.mode }, set: { value in
            guard !model.inputMode.isMicrophone || value == .wait else { return }
            model.mode = value
            model.reconfigure()
        })) {
            Text(PracticeMode.wait.title).tag(PracticeMode.wait)
            Text(PracticeMode.rhythm.title).tag(PracticeMode.rhythm)
                .disabled(model.inputMode.isMicrophone)
        }
        .pickerStyle(.segmented).labelsHidden()
        .accessibilityIdentifier("practice.mode")
    }

    private var modeHelpButton: some View {
        Button { showingModeHelp = true } label: {
            Image(systemName: "questionmark.circle").font(.system(size: 16)).frame(width: 32, height: 32)
        }.buttonStyle(.plain).foregroundStyle(QinXuTheme.muted)
            .accessibilityLabel("识谱与节奏模式说明")
            .accessibilityIdentifier("practice.mode.help")
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
            if !compact && !immersive {
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

            if auditionIsOpen || model.selectedScore.notes.contains(where: { model.hand.includes(staff: $0.staff) }) {
                PracticeScoreView(score: model.selectedScore, hand: auditionIsOpen ? .both : model.hand,
                                  currentBeat: auditionIsOpen ? model.auditionBeat : model.engine.currentBeat,
                                  expectedNotes: auditionIsOpen ? [] : model.engine.expectedNotes,
                                  verdicts: auditionIsOpen ? [:] : model.engine.verdicts,
                                  active: auditionIsOpen ? model.auditionPhase == .playing : model.isPlaying,
                                  compact: compact)
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
        VStack(alignment: .leading, spacing: compact ? 2 : 8) {
            if auditionIsOpen {
                auditionFeedback
            } else {
                HStack(alignment: .center, spacing: 12) { feedbackText; Spacer(minLength: 6); counters }
                sustainStrip
            }
        }
        .padding(.horizontal, compact ? 10 : 16).padding(.vertical, compact ? 3 : 8)
        .frame(maxWidth: .infinity, minHeight: compact ? 60 : 106, maxHeight: compact ? 60 : 106, alignment: .topLeading)
        .background(QinXuTheme.sage, in: RoundedRectangle(cornerRadius: 10))
    }

    private var auditionFeedback: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch model.auditionPhase {
            case .idle, .preparing: Label("准备试听…", systemImage: "hourglass")
            case .playing: Label("正在试听", systemImage: "headphones")
            case .paused: Label("试听已暂停", systemImage: "pause.fill")
            }
            Text("第 \(currentMeasure) / \(model.selectedScore.measures.count) 小节")
                .monospacedDigit().foregroundStyle(QinXuTheme.muted)
                .accessibilityIdentifier("practice.audition.measure")
        }
        .font(.system(size: compact ? 11 : 13))
        .accessibilityIdentifier("practice.audition.status")
    }

    private var feedbackText: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let countdown = model.countdown {
                Text("预备 · \(countdown)").font(.system(size: compact ? 11 : 14, weight: .semibold))
                    .foregroundStyle(QinXuTheme.accent)
                    .accessibilityIdentifier("practice.countdown")
            } else {
                Text(model.inputMode.isMicrophone ? model.engine.feedback : model.engine.durationFeedback ?? model.engine.feedback)
                    .font(.system(size: compact ? 11 : 13, weight: .medium)).lineLimit(1)
                    .accessibilityIdentifier("practice.feedback")
            }
            if !expectedDescription.isEmpty {
                Text("下一待弹  " + expectedDescription)
                    .font(.system(size: compact ? 10 : 11, design: .monospaced))
                    .foregroundStyle(QinXuTheme.muted)
                    .lineLimit(1)
                    .accessibilityIdentifier("practice.expected")
            } else {
                Text(model.sustainGuidance.isEmpty ? "本段已没有待弹音符" : "下一待弹  已弹完，请保持长音")
                    .font(.system(size: compact ? 10 : 11)).foregroundStyle(QinXuTheme.muted).lineLimit(1)
            }
        }
    }

    private var sustainStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: compact ? 7 : 10) {
                Label("保持", systemImage: "hourglass").font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundStyle(QinXuTheme.accent)
                if model.sustainGuidance.isEmpty {
                    Text("弹下音符后，显示剩余拍数与秒数")
                        .font(.system(size: compact ? 10 : 11)).foregroundStyle(QinXuTheme.muted)
                } else {
                    ForEach(Array(model.sustainGuidance.prefix(6))) { guide in
                        sustainIndicator(guide)
                    }
                    if model.sustainGuidance.count > 6 {
                        Text("另有 \(model.sustainGuidance.count - 6) 音")
                            .font(.system(size: 10)).foregroundStyle(QinXuTheme.muted)
                    }
                }
            }.frame(height: compact ? 24 : 43)
        }
        .accessibilityIdentifier("practice.sustain")
    }

    private func sustainIndicator(_ guide: SustainGuidance) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            HStack(spacing: 5) {
                Text(NoteNames.name(guide.pitch)).fontWeight(.semibold)
                Text(String(format: "%.1f秒 / %.1f拍", guide.remainingSeconds, guide.remainingBeats * displayedBeatsPerQuarter))
            }.font(.system(size: compact ? 9 : 11, design: .monospaced)).monospacedDigit()
            GeometryReader { geometry in
                Capsule().fill(QinXuTheme.accent.opacity(0.14))
                    .overlay(alignment: .leading) {
                        Capsule().fill(QinXuTheme.accent)
                            .frame(width: max(0, geometry.size.width * guide.remainingFraction))
                    }
            }.frame(height: 4)
        }
        .frame(width: compact ? 125 : 155)
        .foregroundStyle(QinXuTheme.accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(NoteNames.name(guide.pitch)) 应保持")
        .accessibilityValue(String(format: "剩余 %.1f 拍，%.1f 秒", guide.remainingBeats * displayedBeatsPerQuarter, guide.remainingSeconds))
        .accessibilityIdentifier("practice.sustain.\(guide.pitch)")
    }

    private var counters: some View {
        HStack(spacing: compact ? 10 : 18) {
            counter("正确", identifier: "practice.count.correct", count: model.engine.correctCount, color: QinXuTheme.teal)
            counter("错音", identifier: "practice.count.wrong", count: model.engine.wrongCount, color: QinXuTheme.wrong)
            if model.mode == .rhythm {
                counter("漏音", identifier: "practice.count.missed", count: model.engine.missedCount, color: QinXuTheme.muted)
            }
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
        VStack(alignment: .leading, spacing: 5) {
            if !compact && !immersive {
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
                              expectedPitches: auditionIsOpen ? [] : Set(model.engine.expectedNotes.map(\.midi)),
                              heldPitches: auditionIsOpen ? [] : model.engine.heldPitches,
                              sustainedPitches: auditionIsOpen ? [] : model.sustainedPitches,
                              sustainSeconds: auditionIsOpen ? [:] : Dictionary(uniqueKeysWithValues: model.sustainGuidance.map { ($0.pitch, $0.remainingSeconds) }),
                              sustainFractions: auditionIsOpen ? [:] : Dictionary(uniqueKeysWithValues: model.sustainGuidance.map { ($0.pitch, $0.remainingFraction) }),
                              interactive: model.inputMode == .touch, press: model.press,
                              release: model.release, representsSound: model.inputMode.isMicrophone, compact: compact)
                .allowsHitTesting(!auditionIsOpen)
                .accessibilityHidden(auditionIsOpen)
        }
    }

    private var transport: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: compact ? 10 : 22) {
                metronomeControl
                Spacer(minLength: 8)
                playControls
                Spacer(minLength: 8)
                if !immersive { reportButton; loopButton }
            }
            VStack(spacing: 7) {
                HStack { playControls; Spacer(); if !immersive { reportButton } }
                HStack { metronomeControl; Spacer(); if !immersive { loopButton } }
            }
        }
        .padding(.horizontal, compact ? 12 : 24).padding(.vertical, compact ? 5 : 12)
        .background(QinXuTheme.paper)
        .overlay(alignment: .top) { Rectangle().fill(QinXuTheme.line).frame(height: 1) }
    }

    private var tempoButton: some View {
        Button { model.openMetronomeSettings() } label: {
            HStack(spacing: 3) {
                Text("\(model.metronomeSettings.beatsPerMeasure)/\(model.metronomeSettings.beatUnit)  \(model.metronomeSettings.tempoNote.symbol) \(Int(model.metronomeSettings.tempoBPM))").monospacedDigit()
                Image(systemName: "chevron.down").font(.system(size: 7))
            }.font(.system(size: compact ? 10 : 12, weight: .medium)).padding(.vertical, 3)
        }.buttonStyle(.plain).accessibilityLabel("全局节拍器，\(model.metronomeSettings.beatsPerMeasure)/\(model.metronomeSettings.beatUnit)，\(model.metronomeSettings.tempoNote.title)每分钟 \(Int(model.metronomeSettings.tempoBPM)) 次")
            .accessibilityIdentifier("practice.tempo")
    }

    private var metronomeControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: compact ? 7 : 10) {
                Button { model.toggleMetronome() } label: {
                    Label("节拍器", systemImage: "metronome")
                        .font(.system(size: compact ? 11 : 13, weight: .medium))
                        .foregroundStyle(model.metronomeRunning ? QinXuTheme.accent : QinXuTheme.ink)
                }.buttonStyle(.plain)
                    .accessibilityLabel(model.metronomeRunning ? "停止节拍器" : "启动节拍器")
                    .accessibilityIdentifier("practice.metronome.toggle")
                tempoButton
                Button { model.metronomeEnabled.toggle() } label: {
                    Image(systemName: model.metronomeEnabled && model.metronomeSoundAvailable ? "speaker.wave.2" : "speaker.slash")
                        .font(.system(size: compact ? 11 : 13)).frame(width: 24, height: 24)
                }.buttonStyle(.plain).disabled(!model.metronomeSoundAvailable)
                    .foregroundStyle(QinXuTheme.muted)
                    .accessibilityLabel(!model.metronomeSoundAvailable ? "麦克风录音期间仅视觉节拍" : model.metronomeEnabled ? "关闭节拍器声音" : "打开节拍器声音")
                    .accessibilityIdentifier("practice.metronome.sound")
            }
            HStack(spacing: compact ? 3 : 5) {
                ForEach(1...model.metronomeSettings.beatsPerMeasure, id: \.self) { beat in
                    Circle().fill(model.metronomeBeat == beat ? QinXuTheme.accent : QinXuTheme.line)
                        .frame(width: beat == 1 ? 7 : 5, height: beat == 1 ? 7 : 5)
                }
                if model.metronomeSettings.pulsesPerBeat > 1 {
                    Text("\(model.metronomeSubdivision ?? 0)/\(model.metronomeSettings.pulsesPerBeat)")
                        .font(.system(size: 9)).monospacedDigit().foregroundStyle(QinXuTheme.muted)
                }
                if meterDiffers {
                    Text("谱面 \(model.selectedScore.beatsPerMeasure)/\(model.selectedScore.beatUnit)")
                        .font(.system(size: 9)).foregroundStyle(QinXuTheme.muted)
                }
                if !model.metronomeSoundAvailable {
                    Text("仅闪拍").font(.system(size: 9)).foregroundStyle(QinXuTheme.muted)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("节拍指示")
            .accessibilityValue(model.metronomeBeat.map { "第 \($0) 拍，第 \(model.metronomeSubdivision ?? 1) 分拍" } ?? "未运行")
            .accessibilityIdentifier("practice.metronome.beat")
        }
    }

    private var reportButton: some View {
        Button { model.showCurrentReport() } label: {
            Label("报告", systemImage: "chart.bar.xaxis").font(.system(size: 11))
        }.buttonStyle(.plain).foregroundStyle(QinXuTheme.muted)
            .disabled(model.engine.correctCount == 0 && model.engine.wrongCount == 0 && model.engine.missedCount == 0)
            .accessibilityIdentifier("practice.report")
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
                    DisclosureGroup("识谱和节奏有什么区别？") {
                        Text("识谱：等你弹对后继续，不评抢拍、拖拍或漏音。节奏：预备一小节后按速度持续前进，记录错音、漏音和起音早晚。")
                            .foregroundStyle(QinXuTheme.muted)
                    }.accessibilityIdentifier("practice.mode.help.settings")
                    if model.inputMode.isMicrophone {
                        Text("麦克风目前仅支持识谱。节奏评分请切换 MIDI 或触屏输入。")
                            .foregroundStyle(QinXuTheme.muted)
                    }
                    handPicker
                }
                Section("全局节拍器") {
                    Button {
                        openMetronomeAfterSettings = true
                        showingSettings = false
                    } label: {
                        HStack {
                            Label("拍号、速度与分拍", systemImage: "metronome")
                            Spacer()
                            Text("\(model.metronomeSettings.beatsPerMeasure)/\(model.metronomeSettings.beatUnit) · \(model.metronomeSettings.tempoNote.symbol) \(Int(model.metronomeSettings.tempoBPM))").monospacedDigit()
                            Image(systemName: "chevron.right").font(.system(size: 10))
                        }
                    }.accessibilityIdentifier("practice.settings.metronome")
                    Text("练习速度跟随全局设置；曲谱的拍号与音符时值保持不变。")
                        .foregroundStyle(QinXuTheme.muted)
                    if meterDiffers {
                        Text("节拍器 \(model.metronomeSettings.beatsPerMeasure)/\(model.metronomeSettings.beatUnit) · 谱面 \(model.selectedScore.beatsPerMeasure)/\(model.selectedScore.beatUnit)")
                            .foregroundStyle(QinXuTheme.muted)
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
            .accessibilityIdentifier("practice.settings.form")
            .font(.system(size: 13))
            .navigationTitle("练习设置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingSettings = false }.accessibilityIdentifier("practice.settings.close") } }
        }
        .tint(QinXuTheme.accent)
        .frame(minWidth: 320, minHeight: 280)
        .onAppear { model.pausePractice() }
    }

    private var modeHelp: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    modeExplanation("识谱模式", symbol: "music.note", text: "弹对当前音或和弦后才继续。可以停下来找键，不按固定时间判抢拍、拖拍和漏音。适合先认熟音符。")
                    modeExplanation("节奏模式", symbol: "metronome", text: "预备一小节后，按设定速度持续向前。起音过早算抢拍，过晚算拖拍，错过时间窗算漏音。暂停会停住练习时间线。")
                    modeExplanation("长音提示", symbol: "hourglass", text: "橙色倒计时显示谱面要求还应保持多久，按当前速度换算秒数。它是练习指引；麦克风声音包含余音，不能证明琴键仍按着。")
                    modeExplanation("全局节拍器", symbol: "metronome", text: "所有曲目跟随全局速度。节拍器拍号决定重拍循环，分拍决定每响一次的时值；这些设置不会改写曲谱的拍号或音符。长音提示中的拍数仍按谱面拍号计算。")
                    if model.inputMode.isMicrophone {
                        Label("麦克风仅开放识谱模式；录音期间只闪拍，避免节拍器声音干扰识音。暂停录音后可独立使用有声节拍器。", systemImage: "mic")
                            .font(.system(size: 13)).foregroundStyle(QinXuTheme.muted)
                    }
                }.padding(24).frame(maxWidth: 620, alignment: .leading)
            }.background(QinXuTheme.background)
                .navigationTitle("练习模式")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("知道了") { showingModeHelp = false } } }
        }.frame(minWidth: 320, minHeight: 280)
            .onAppear { model.pausePractice() }
    }

    private func modeExplanation(_ title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.system(size: 17, weight: .semibold))
            Text(text).font(.system(size: 14)).lineSpacing(5).foregroundStyle(QinXuTheme.muted)
        }
    }
}
