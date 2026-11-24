import SwiftUI
import UniformTypeIdentifiers
import PianoCore

struct ContentView: View {
    @ObservedObject var model: PracticeViewModel
    @State private var showingLibrary = false
    @State private var showingHistory = false
    @State private var pendingImport = false

    private var currentMeasure: Int {
        model.engine.expectedNotes.first?.measure ?? model.selectedScore.measures.last(where: { $0.startBeat <= model.engine.currentBeat })?.number ?? 1
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 900
            HStack(spacing: 0) {
                if wide { libraryPanel.frame(width: 235) }
                VStack(spacing: 0) {
                    header(wide: wide)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            introduction
                            controls
                            scoreCard
                            keyboardCard
                            connectionCard
                            Text("本地练习 · 曲谱与练习记录保存在这台设备上")
                                .font(.system(size: 11)).foregroundStyle(PracticeTheme.muted)
                                .frame(maxWidth: .infinity).padding(.bottom, 8)
                        }
                        .padding(geometry.size.width < 600 ? 16 : 28)
                        .frame(maxWidth: 1280)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .background(PracticeTheme.background)
        }
        .tint(PracticeTheme.teal)
        .preferredColorScheme(.light)
        .fileImporter(isPresented: $model.isImporting, allowedContentTypes: [.xml, .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { model.importScore(from: url) }
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .alert("暂时无法完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(isPresented: $showingLibrary, onDismiss: {
            if pendingImport { pendingImport = false; model.isImporting = true }
        }) {
            NavigationStack {
                libraryPanel
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingLibrary = false } } }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingHistory) {
            PracticeHistoryView(history: model.history)
        }
    }

    private func header(wide: Bool) -> some View {
        HStack {
            if !wide {
                Button { showingLibrary = true } label: { Image(systemName: "sidebar.left").font(.system(size: 19)) }
                    .buttonStyle(.plain).accessibilityLabel("打开曲谱库")
            }
            Text("练习室").font(.system(size: 14, weight: .semibold))
            Spacer()
            Label("离线可用", systemImage: "checkmark.shield")
                .font(.system(size: 11)).foregroundStyle(PracticeTheme.muted)
            Button { showingHistory = true } label: { Label("练习记录", systemImage: "clock.arrow.circlepath") }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(PracticeTheme.ink)
        .padding(.horizontal, 28).frame(height: 64)
        .background(PracticeTheme.paper.opacity(0.85))
        .overlay(alignment: .bottom) { Rectangle().fill(PracticeTheme.line).frame(height: 1) }
    }

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 11) {
                Image(systemName: "pianokeys").font(.system(size: 25))
                    .foregroundStyle(Color(red: 0.73, green: 0.85, blue: 0.70))
                VStack(alignment: .leading, spacing: 3) {
                    Text("琴伴").font(.system(size: 25, weight: .semibold, design: .serif))
                    Text("A LITTLE PRACTICE, EVERY DAY").font(.system(size: 7, weight: .medium)).tracking(1)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }.padding(.top, 15)

            VStack(alignment: .leading, spacing: 12) {
                Text("我的曲谱").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.scores) { score in
                            Button {
                                model.selectScore(score.id)
                                showingLibrary = false
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "music.note.list").frame(width: 18).padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(score.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                        Text("\(score.measures.count) 小节 · \(Int(score.tempoBPM)) BPM")
                                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                                    }
                                    Spacer(minLength: 0)
                                    if score.id == model.selectedScoreID { Circle().fill(Color(red: 0.73, green: 0.85, blue: 0.70)).frame(width: 5, height: 5).padding(.top, 6) }
                                }
                                .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                                .background(score.id == model.selectedScoreID ? Color.white.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Button {
                if showingLibrary { pendingImport = true; showingLibrary = false }
                else { model.isImporting = true }
            } label: {
                Label("导入 MusicXML", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4])))
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: "leaf").font(.system(size: 21)).foregroundStyle(Color(red: 0.73, green: 0.85, blue: 0.70))
                Text("慢一点，也是在进步。").font(.system(size: 13, weight: .medium))
                Text("先读懂一个音，再连成一段旋律。")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineSpacing(4)
            }.padding(.bottom, 12)
        }
        .padding(20).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PracticeTheme.navy)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionEyebrow(text: "YOUR DAILY PIANO PRACTICE")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.selectedScore.title).font(.system(size: 32, weight: .medium, design: .serif))
                    Spacer(minLength: 14)
                    pieceMetadata
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text(model.selectedScore.title).font(.system(size: 27, weight: .medium, design: .serif))
                    pieceMetadata
                }
            }
            Text(model.mode == .wait ? "按自己的速度，弹对当前音符后继续。" : "跟随时间线练习，留意音高、起音和节奏。")
                .font(.system(size: 13)).foregroundStyle(PracticeTheme.muted)
        }.foregroundStyle(PracticeTheme.ink)
    }

    private var pieceMetadata: some View {
        HStack(spacing: 13) {
            if !model.selectedScore.composer.isEmpty { Text(model.selectedScore.composer).lineLimit(1) }
            Text("\(model.selectedScore.beatsPerMeasure)/\(model.selectedScore.beatUnit) 拍")
            Text("\(model.selectedScore.measures.count) 小节")
        }.font(.system(size: 11)).foregroundStyle(PracticeTheme.muted)
    }

    private var controls: some View {
        PracticeCard(padding: 18) {
            VStack(alignment: .leading, spacing: 17) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { modePicker.frame(width: 225); handPicker.frame(width: 180); Spacer(); playControls }
                    VStack(alignment: .leading, spacing: 14) {
                        modePicker
                        HStack { handPicker.frame(maxWidth: 210); Spacer(); playControls }
                    }
                }
                if model.mode == .rhythm {
                    Toggle("节拍器声音", isOn: $model.metronomeEnabled).font(.system(size: 12)).toggleStyle(.switch).fixedSize()
                }
                Rectangle().fill(PracticeTheme.line).frame(height: 1)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 26) { tempoControl.frame(minWidth: 210, maxWidth: 330); Spacer(); loopControl }
                    VStack(alignment: .leading, spacing: 15) { tempoControl; loopControl }
                }
            }
        }
    }

    private var modePicker: some View {
        Picker("练习模式", selection: $model.mode) {
            ForEach(PracticeMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented).onChange(of: model.mode) { _, _ in model.reconfigure() }
    }

    private var handPicker: some View {
        Picker("练习手", selection: $model.hand) {
            ForEach(PracticeHand.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented).onChange(of: model.hand) { _, _ in model.reconfigure() }
    }

    private var playControls: some View {
        HStack(spacing: 8) {
            Button { model.restart() } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(QuietButtonStyle()).accessibilityLabel("从头再练")
            Button { model.togglePlayback() } label: {
                Label(model.isPlaying ? "暂停" : (model.engine.isFinished ? "再练一次" : "开始练习"), systemImage: model.isPlaying ? "pause.fill" : "play.fill")
            }.buttonStyle(QuietButtonStyle(prominent: true))
        }
    }

    private var tempoControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "metronome").font(.system(size: 16)).foregroundStyle(PracticeTheme.muted)
            Slider(value: $model.tempo, in: 20...300, step: 1, onEditingChanged: { editing in if !editing { model.reconfigure() } })
                .accessibilityLabel("速度，四分音符每分钟")
            Text("\(Int(model.tempo))").font(.system(size: 15, weight: .semibold, design: .monospaced)).monospacedDigit()
            Text("BPM").font(.system(size: 9, weight: .medium)).foregroundStyle(PracticeTheme.muted)
        }.foregroundStyle(PracticeTheme.ink)
    }

    private var loopControl: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $model.loopEnabled) { Label("循环", systemImage: "repeat") }
                .toggleStyle(.switch).fixedSize().font(.system(size: 12))
                .onChange(of: model.loopEnabled) { _, _ in model.reconfigure() }
            if model.loopEnabled {
                Picker("起始小节", selection: $model.loopStart) {
                    ForEach(model.selectedScore.measures) { Text("\($0.number)").tag($0.number) }
                }.labelsHidden().frame(maxWidth: 75)
                    .onChange(of: model.loopStart) { _, value in
                        if model.loopEnd < value { model.loopEnd = value }
                        model.reconfigure()
                    }
                Text("至").font(.system(size: 11)).foregroundStyle(PracticeTheme.muted)
                Picker("结束小节", selection: $model.loopEnd) {
                    ForEach(model.selectedScore.measures.filter { $0.number >= model.loopStart }) { Text("\($0.number)").tag($0.number) }
                }.labelsHidden().frame(maxWidth: 75)
                    .onChange(of: model.loopEnd) { _, _ in model.reconfigure() }
                Text("小节").font(.system(size: 11)).foregroundStyle(PracticeTheme.muted)
            } else { Text("反复练习一个片段").font(.system(size: 11)).foregroundStyle(PracticeTheme.muted) }
        }
    }

    private var scoreCard: some View {
        PracticeCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Label("跟谱练习", systemImage: "music.note")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("第 \(currentMeasure) / \(model.selectedScore.measures.count) 小节")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(PracticeTheme.muted)
                }.padding(22)

                if model.selectedScore.notes.filter({ model.hand.includes(staff: $0.staff) }).isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(PracticeTheme.muted)
                        Text("这份曲谱没有\(model.hand.title)声部的音符").font(.system(size: 14, weight: .medium))
                        Text("切换到双手，或选择另一份曲谱。 ").font(.system(size: 12)).foregroundStyle(PracticeTheme.muted)
                    }.frame(maxWidth: .infinity).padding(.vertical, 65)
                } else {
                    PracticeScoreView(score: model.selectedScore, hand: model.hand, currentBeat: model.engine.currentBeat, expectedNotes: model.engine.expectedNotes, verdicts: model.engine.verdicts, active: model.isPlaying)
                }

                VStack(alignment: .leading, spacing: 9) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 15) { feedback; Spacer(); counters }
                        VStack(alignment: .leading, spacing: 11) { feedback; counters }
                    }
                    if let durationFeedback = model.engine.durationFeedback {
                        Text(durationFeedback).font(.system(size: 11)).foregroundStyle(PracticeTheme.muted)
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(PracticeTheme.teal.opacity(0.055))

                VStack(alignment: .leading, spacing: 5) {
                    Text("简化练习谱：按实际音高与四分音符拍点排布；临时记号逐音显示，留白表示休止。未还原原谱的连线、表情与版式。")
                    ForEach(model.selectedScore.warnings, id: \.self) { Text("提示：\($0)") }
                }.font(.system(size: 10)).foregroundStyle(PracticeTheme.muted).lineSpacing(3).padding(18)
            }.foregroundStyle(PracticeTheme.ink)
        }
    }

    private var feedback: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: model.engine.isFinished ? "checkmark.circle.fill" : "hand.point.up.left")
                .foregroundStyle(PracticeTheme.teal)
            VStack(alignment: .leading, spacing: 4) {
                if let countdown = model.countdown {
                    Text("预备 · \(countdown)").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(PracticeTheme.teal)
                } else {
                    Text(model.engine.feedback).font(.system(size: 13, weight: .medium))
                }
                if !model.engine.expectedNotes.isEmpty {
                    Text("当前音符  " + model.engine.expectedNotes.map { note in
                        let beats = String(format: "%.3g", note.durationBeats)
                        let seconds = String(format: "%.2f", note.durationBeats * 60 / model.tempo)
                        return "\(note.name) · \(beats) 拍 ≈ \(seconds) 秒"
                    }.joined(separator: "；"))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(PracticeTheme.muted)
                }
            }
        }
    }

    private var counters: some View {
        HStack(spacing: 16) {
            counter("正确", count: model.engine.correctCount, color: PracticeTheme.teal)
            counter("错音", count: model.engine.wrongCount, color: PracticeTheme.wrong)
            counter("漏音", count: model.engine.missedCount, color: PracticeTheme.muted)
        }
    }

    private func counter(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Text("\(count)").font(.system(size: 18, weight: .medium, design: .serif)).monospacedDigit().foregroundStyle(color)
            Text(title).font(.system(size: 10)).foregroundStyle(PracticeTheme.muted)
        }
    }

    private var keyboardCard: some View {
        PracticeCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label("键盘指引", systemImage: "pianokeys").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Circle().fill(PracticeTheme.teal.opacity(0.23)).frame(width: 8, height: 8)
                    Text("待弹").font(.system(size: 10)).foregroundStyle(PracticeTheme.muted)
                    Circle().fill(PracticeTheme.teal).frame(width: 8, height: 8)
                    Text("按下").font(.system(size: 10)).foregroundStyle(PracticeTheme.muted)
                }
                PianoKeyboardView(expectedPitches: Set(model.engine.expectedNotes.map(\.midi)), heldPitches: model.engine.heldPitches, hand: model.hand, interactive: model.inputMode == .touch, press: model.press, release: model.release)
                HStack(alignment: .top, spacing: 8) {
                    Text(model.inputMode == .touch ? "触屏练习：按住可延音，多指可弹和弦；松开即释放。触屏按键暂不发声。" : "键盘显示待弹与已按下的音。连接钢琴后开始练习。")
                        .font(.system(size: 11)).foregroundStyle(PracticeTheme.muted)
                    Spacer(minLength: 0)
                    if model.inputMode != .touch {
                        Button("试试触屏") { model.setInputMode(.touch) }.font(.system(size: 11, weight: .semibold)).buttonStyle(.plain)
                    }
                }
            }.foregroundStyle(PracticeTheme.ink)
        }
    }

    private var connectionCard: some View {
        InputConnectionView(model: model, midi: model.midi, microphone: model.microphone)
    }
}

private struct InputConnectionView: View {
    @ObservedObject var model: PracticeViewModel
    @ObservedObject var midi: MIDIService
    @ObservedObject var microphone: MicrophoneService

    var body: some View {
        PracticeCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("演奏输入", systemImage: "cable.connector").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Picker("输入方式", selection: Binding(get: { model.inputMode }, set: { model.setInputMode($0) })) {
                        Text("MIDI 钢琴").tag(InputMode.midi)
                        Text("触屏").tag(InputMode.touch)
                        Text("麦克风 · 实验").tag(InputMode.microphone)
                    }.pickerStyle(.menu)
                }
                switch model.inputMode {
                case .midi:
                    HStack(spacing: 10) {
                        Circle().fill(midi.connected ? PracticeTheme.teal : PracticeTheme.amber).frame(width: 7, height: 7)
                        Text(midi.status).font(.system(size: 12)).foregroundStyle(PracticeTheme.muted)
                        Spacer()
                        Button { model.refreshMIDI() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                            .buttonStyle(.plain).font(.system(size: 11))
                    }
                    Picker("MIDI 来源", selection: Binding<Int32?>(get: { midi.selectedSourceID }, set: { midi.selectSource($0) })) {
                        Text("选择设备").tag(Optional<Int32>.none)
                        ForEach(midi.sources) { source in Text(source.name).tag(Optional(source.id)) }
                    }
                    Text("通过 USB MIDI 或系统已连接的蓝牙 MIDI 输入。这里不会播放钢琴伴奏音。")
                        .font(.system(size: 10)).foregroundStyle(PracticeTheme.muted)
                case .touch:
                    Label("触屏键盘已启用", systemImage: "hand.tap").font(.system(size: 12)).foregroundStyle(PracticeTheme.teal)
                    Text("用于体验识谱与判音流程。建议使用 iPad 多指演奏，完整练琴请连接 MIDI 钢琴。")
                        .font(.system(size: 11)).foregroundStyle(PracticeTheme.muted)
                case .microphone:
                    HStack {
                        Circle().fill(microphone.isActive ? PracticeTheme.teal : PracticeTheme.amber).frame(width: 7, height: 7)
                        Text(microphone.status).font(.system(size: 12)).foregroundStyle(PracticeTheme.muted)
                        Spacer()
                        if let pitch = microphone.detectedPitch { Text(NoteNames.name(pitch)).font(.system(size: 18, weight: .semibold, design: .monospaced)).foregroundStyle(PracticeTheme.teal) }
                    }
                    ProgressView(value: min(1, max(0, microphone.level)))
                        .accessibilityLabel("麦克风输入音量")
                    Text("实验功能：C3–C6 单音识谱验证。请在安静环境中逐个弹音，不使用延音踏板；节奏判定、和弦与双手同时演奏暂不支持。")
                        .font(.system(size: 11)).foregroundStyle(PracticeTheme.amber).lineSpacing(3)
                }
            }.foregroundStyle(PracticeTheme.ink)
        }
    }
}

private struct PracticeHistoryView: View {
    var history: [PracticeSummary]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if history.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "clock.arrow.circlepath").font(.system(size: 35)).foregroundStyle(PracticeTheme.teal)
                            Text("练习会留下足迹").font(.system(size: 22, weight: .medium, design: .serif))
                            Text("完成一轮练习后，在这里查看真实的练习记录。")
                                .font(.system(size: 13)).foregroundStyle(PracticeTheme.muted)
                        }.frame(maxWidth: .infinity).padding(.vertical, 90)
                    } else {
                        ForEach(history.sorted { $0.date > $1.date }) { record in
                            PracticeCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(record.scoreTitle).font(.system(size: 16, weight: .semibold))
                                            Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(PracticeTheme.muted)
                                        }
                                        Spacer()
                                        Text(record.mode.title).font(.system(size: 10)).foregroundStyle(PracticeTheme.teal).padding(7).background(PracticeTheme.teal.opacity(0.08), in: Capsule())
                                    }
                                    HStack(spacing: 15) {
                                        Text("正确 \(record.correct)")
                                        Text("错音 \(record.wrong)")
                                        Text("漏音 \(record.missed)")
                                        Spacer()
                                        Text("\(Int(record.durationSeconds)) 秒")
                                    }.font(.system(size: 11)).foregroundStyle(PracticeTheme.muted)
                                }
                            }
                        }
                    }
                }.padding(22)
            }
            .background(PracticeTheme.background).foregroundStyle(PracticeTheme.ink)
            .navigationTitle("练习记录")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.frame(minWidth: 340, minHeight: 440)
    }
}
