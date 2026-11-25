import SwiftUI
import UniformTypeIdentifiers
import QinXuCore

struct PracticeHomeView: View {
    @ObservedObject var model: PracticeViewModel
    @State private var showingLibrary = false
    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var pendingImport = false
    @State private var librarySearch = ""

    private var currentMeasure: Int {
        model.engine.expectedNotes.first?.measure ??
            model.selectedScore.measures.last(where: { $0.startBeat <= model.engine.currentBeat })?.number ?? 1
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 900
            let inset: CGFloat = geometry.size.width < 600 ? 14 : 28
            HStack(spacing: 0) {
                if wide {
                    libraryPanel.frame(width: 250)
                    Rectangle().fill(QinXuTheme.line).frame(width: 1)
                }
                VStack(spacing: 0) {
                    header(wide: wide, inset: inset)
                    workspace(inset: inset)
                    transport(inset: inset)
                }
            }
            .background(QinXuTheme.background)
        }
        .foregroundStyle(QinXuTheme.ink)
        .tint(QinXuTheme.accent)
        .preferredColorScheme(.light)
        .fileImporter(isPresented: $model.isImporting, allowedContentTypes: [.xml, .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    librarySearch = ""
                    model.importScore(from: url)
                }
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .alert("无法完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(isPresented: $showingLibrary, onDismiss: {
            if pendingImport {
                pendingImport = false
                model.isImporting = true
            }
        }) {
            NavigationStack {
                libraryPanel
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showingLibrary = false }.accessibilityIdentifier("library.close")
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingSettings) { PracticeSettingsView(model: model) }
        .sheet(isPresented: $showingHistory) { PracticeHistoryView(history: model.history) }
    }

    private func workspace(inset: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                scoreSheet
                keyboardPanel
            }
            .padding(.horizontal, inset)
            .padding(.vertical, inset)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .id(model.selectedScoreID)
        .accessibilityIdentifier("practice.scroll")
    }

    private func header(wide: Bool, inset: CGFloat) -> some View {
        HStack(spacing: 10) {
            if wide {
                Label("练习", systemImage: "music.note")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(QinXuTheme.muted)
            } else {
                Button {
                    showingLibrary = true
                } label: {
                    Label("曲库", systemImage: "books.vertical")
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel("打开曲谱库")
                .accessibilityIdentifier("library.open")
            }
            Spacer(minLength: 4)
            Button { showingHistory = true } label: {
                Label("记录", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityLabel("练习记录")
            .accessibilityIdentifier("history.open")
            Button { showingSettings = true } label: {
                Label("设置", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityLabel("练习设置")
            .accessibilityIdentifier("practice.settings")
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 7)
        .background(QinXuTheme.paper)
        .overlay(alignment: .bottom) { Divider().overlay(QinXuTheme.line) }
    }

    private var visibleScores: [PianoScore] {
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.scores }
        return model.scores.filter {
            $0.title.localizedStandardContains(query) || $0.composer.localizedStandardContains(query)
        }
    }

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "pianokeys")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(QinXuTheme.accent, in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityHidden(true)
                Text("琴序").font(.title2.weight(.bold))
                Spacer()
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(QinXuTheme.muted)
                TextField("搜索曲名或作曲家", text: $librarySearch)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("library.search")
                if !librarySearch.isEmpty {
                    Button { librarySearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(QinXuTheme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .font(.subheadline)
            .padding(11)
            .background(QinXuTheme.background, in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Text("我的曲谱").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(visibleScores.count)").font(.caption.monospacedDigit()).foregroundStyle(QinXuTheme.muted)
            }
            ScrollView {
                LazyVStack(spacing: 5) {
                    if visibleScores.isEmpty {
                        Text("没有匹配的曲谱")
                            .font(.subheadline)
                            .foregroundStyle(QinXuTheme.muted)
                            .padding(.vertical, 24)
                    }
                    ForEach(visibleScores) { score in libraryRow(score) }
                }
            }
            Button {
                if showingLibrary {
                    pendingImport = true
                    showingLibrary = false
                } else {
                    model.isImporting = true
                }
            } label: {
                Label("导入 MusicXML", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(QuietButtonStyle(prominent: true))
            .accessibilityIdentifier("library.import")
            #if os(macOS)
            .keyboardShortcut("o", modifiers: .command)
            #endif
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QinXuTheme.paper)
    }

    private func libraryRow(_ score: PianoScore) -> some View {
        let selected = score.id == model.selectedScoreID
        return Button {
            model.selectScore(score.id)
            showingLibrary = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 31, height: 34)
                    .foregroundStyle(selected ? QinXuTheme.accent : QinXuTheme.muted)
                    .background(selected ? QinXuTheme.paper : QinXuTheme.background, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(score.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text("\(score.measures.count) 小节 · \(Int(score.tempoBPM)) BPM")
                        .font(.caption2).foregroundStyle(QinXuTheme.muted)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.caption.weight(.bold))
                        .foregroundStyle(QinXuTheme.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(selected ? QinXuTheme.accentTint : Color.clear, in: RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("library.score." + score.id)
    }

    private var scoreSheet: some View {
        PracticeCard(padding: 0) {
            VStack(spacing: 0) {
                scoreHeading
                if model.selectedScore.notes.contains(where: { model.hand.includes(staff: $0.staff) }) {
                    PracticeScoreView(
                        score: model.selectedScore, hand: model.hand, currentBeat: model.engine.currentBeat,
                        expectedNotes: model.engine.expectedNotes, verdicts: model.engine.verdicts, active: model.isPlaying
                    )
                    .padding(.horizontal, 12)
                } else {
                    ContentUnavailableView("没有此声部的音符", systemImage: "music.note",
                                           description: Text("切换到双手，或选择另一份曲谱。"))
                        .frame(minHeight: 200)
                }
                scoreFeedback
            }
        }
    }

    private var scoreHeading: some View {
        let score = model.selectedScore
        return VStack(alignment: .leading, spacing: 9) {
            Text(score.title)
                .font(.system(.title, design: .serif, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("practice.score.title")

            if !score.composer.isEmpty {
                Text(score.composer).font(.subheadline).foregroundStyle(QinXuTheme.muted)
            }

            HStack(spacing: 10) {
                Text("\(score.beatsPerMeasure)/\(score.beatUnit) 拍")
                Text("\(Int(model.tempo)) BPM")
                if model.loopEnabled {
                    Image(systemName: "repeat").accessibilityLabel("已启用小节循环")
                }
                Spacer(minLength: 6)
                Text("\(currentMeasure) / \(score.measures.count) 小节")
                    .fontWeight(.semibold)
                    .foregroundStyle(QinXuTheme.accent)
                    .accessibilityLabel("第 \(currentMeasure) 小节，共 \(score.measures.count) 小节")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(QinXuTheme.muted)

            let progress = model.engine.isFinished ? 1 : Double(max(0, currentMeasure - 1)) / Double(max(1, score.measures.count))
            GeometryReader { geometry in
                Capsule().fill(QinXuTheme.line)
                    .overlay(alignment: .leading) {
                        Capsule().fill(QinXuTheme.accent).frame(width: geometry.size.width * min(1, progress))
                    }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 7)
    }

    private var scoreFeedback: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { feedback; Spacer(minLength: 0); counters }
                VStack(alignment: .leading, spacing: 9) { feedback; counters }
            }
            if let text = model.engine.durationFeedback {
                Text(text).font(.caption).foregroundStyle(QinXuTheme.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QinXuTheme.background)
        .overlay(alignment: .top) { Divider().overlay(QinXuTheme.line) }
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let countdown = model.countdown {
                Text("预备 \(countdown)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(QinXuTheme.accent)
            } else {
                Text(model.engine.feedback)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("practice.feedback")
            }
            if !model.engine.expectedNotes.isEmpty {
                Text(model.engine.expectedNotes.map { note in
                    let beats = String(format: "%.3g", note.durationBeats)
                    let seconds = String(format: "%.2f", note.durationBeats * 60 / model.tempo)
                    return "\(note.name) · \(beats) 拍 · \(seconds) 秒"
                }.joined(separator: "  /  "))
                .font(.caption.monospacedDigit())
                .foregroundStyle(QinXuTheme.muted)
                .accessibilityIdentifier("practice.expected")
            }
        }
    }

    private var counters: some View {
        HStack(spacing: 10) {
            counter("正确", identifier: "practice.count.correct", count: model.engine.correctCount, color: QinXuTheme.success)
            counter("错音", identifier: "practice.count.wrong", count: model.engine.wrongCount, color: QinXuTheme.wrong)
            counter("漏音", identifier: "practice.count.missed", count: model.engine.missedCount, color: QinXuTheme.muted)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func counter(_ title: String, identifier: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(QinXuTheme.muted)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(String(count))
        .accessibilityIdentifier(identifier)
    }

    private var keyboardPanel: some View {
        PracticeCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("键盘指引", systemImage: "pianokeys").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Button { showingSettings = true } label: {
                        Label(inputTitle, systemImage: inputIcon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(QinXuTheme.accent)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 36)
                            .background(QinXuTheme.accentTint, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                        .accessibilityHint("打开练习设置以更改输入方式")
                }
                PianoKeyboardView(
                    expectedPitches: Set(model.engine.expectedNotes.map(\.midi)), heldPitches: model.engine.heldPitches,
                    hand: model.hand, interactive: model.inputMode == .touch, press: model.press, release: model.release
                )
            }
        }
    }

    private var inputTitle: String {
        switch model.inputMode {
        case .touch: "触屏 · 无声"
        case .midi: model.midi.connected ? "MIDI 已连接" : "MIDI 未连接"
        case .microphone: "麦克风 · 实验"
        }
    }

    private var inputIcon: String {
        switch model.inputMode {
        case .touch: "hand.tap"
        case .midi: "cable.connector"
        case .microphone: "mic"
        }
    }

    private func transport(inset: CGFloat) -> some View {
        HStack(spacing: 7) {
            Menu {
                ForEach(PracticeMode.allCases, id: \.self) { mode in
                    Button {
                        if model.mode != mode { model.mode = mode; model.reconfigure() }
                    } label: {
                        if model.mode == mode { Label(mode.title, systemImage: "checkmark") }
                        else { Text(mode.title) }
                    }.disabled(mode == .rhythm && model.inputMode == .microphone)
                }
            } label: {
                pill(model.mode == .wait ? "识谱" : "节奏")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 9)
            .frame(minWidth: 44, minHeight: 44)
            .background(QinXuTheme.accentTint, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("练习模式")
            .accessibilityValue(model.mode.title)

            Menu {
                ForEach(PracticeHand.allCases, id: \.self) { hand in
                    Button {
                        if model.hand != hand { model.hand = hand; model.reconfigure() }
                    } label: {
                        if model.hand == hand { Label(hand.title, systemImage: "checkmark") }
                        else { Text(hand.title) }
                    }
                }
            } label: {
                pill(model.hand.title)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 9)
            .frame(minWidth: 44, minHeight: 44)
            .background(QinXuTheme.accentTint, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("练习手")
            .accessibilityValue(model.hand.title)

            Spacer(minLength: 0)

            Button { model.restart() } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel("从头再练")
                .accessibilityIdentifier("practice.restart")

            Button { model.togglePlayback() } label: {
                Label(model.isPlaying ? "暂停" : (model.engine.isFinished ? "再练一次" : "开始练习"),
                      systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                    .fixedSize()
            }
            .buttonStyle(QuietButtonStyle(prominent: true))
            .accessibilityIdentifier("practice.play")
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 9)
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity)
        .background(QinXuTheme.paper)
        .overlay(alignment: .top) { Divider().overlay(QinXuTheme.line) }
    }

    private func pill(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(QinXuTheme.accent)
    }
}

private struct PracticeSettingsView: View {
    @ObservedObject var model: PracticeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("速度") {
                    HStack {
                        Slider(value: Binding(get: { model.tempo }, set: { model.tempo = $0.rounded() }), in: 20...300,
                               onEditingChanged: { editing in if !editing { model.reconfigure() } })
                        .accessibilityLabel("速度，四分音符每分钟")
                        Text("\(Int(model.tempo)) BPM").font(.subheadline.monospacedDigit())
                    }
                    if model.mode == .rhythm {
                        Toggle("节拍器声音", isOn: $model.metronomeEnabled)
                    }
                }

                Section("小节循环") {
                    Toggle("重复所选片段", isOn: $model.loopEnabled)
                        .accessibilityIdentifier("practice.loop.toggle")
                        .onChange(of: model.loopEnabled) { _, _ in model.reconfigure() }
                    if model.loopEnabled {
                        Picker("起始小节", selection: $model.loopStart) {
                            ForEach(model.selectedScore.measures) { Text("\($0.number)").tag($0.number) }
                        }
                        .accessibilityIdentifier("practice.loop.start")
                        .onChange(of: model.loopStart) { _, value in
                            if model.loopEnd < value { model.loopEnd = value }
                            model.reconfigure()
                        }
                        Picker("结束小节", selection: $model.loopEnd) {
                            ForEach(model.selectedScore.measures.filter { $0.number >= model.loopStart }) {
                                Text("\($0.number)").tag($0.number)
                            }
                        }
                        .onChange(of: model.loopEnd) { _, _ in model.reconfigure() }
                    }
                }

                Section("演奏输入") {
                    InputSettingsView(model: model, midi: model.midi, microphone: model.microphone)
                }

                Section("曲谱说明") {
                    Text("练习谱按音高和拍点排布，留白表示休止，排版与原谱可能不同。")
                    ForEach(model.selectedScore.warnings, id: \.self) { Text($0) }
                }
                .font(.caption)
                .foregroundStyle(QinXuTheme.muted)
            }
            .formStyle(.grouped)
            .navigationTitle("练习设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("practice.settings.done")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 470)
        #endif
    }
}

private struct InputSettingsView: View {
    @ObservedObject var model: PracticeViewModel
    @ObservedObject var midi: MIDIService
    @ObservedObject var microphone: MicrophoneService

    var body: some View {
        Picker("输入方式", selection: Binding(get: { model.inputMode }, set: { model.setInputMode($0) })) {
            Text("MIDI 钢琴").tag(InputMode.midi)
            Text("触屏").tag(InputMode.touch)
            Text("麦克风 · 实验").tag(InputMode.microphone)
        }
        switch model.inputMode {
        case .midi:
            Picker("MIDI 来源", selection: Binding<Int32?>(get: { midi.selectedSourceID }, set: { midi.selectSource($0) })) {
                Text("选择设备").tag(Optional<Int32>.none)
                ForEach(midi.sources) { source in Text(source.name).tag(Optional(source.id)) }
            }
            HStack {
                Circle().fill(midi.connected ? QinXuTheme.success : QinXuTheme.amber).frame(width: 7, height: 7)
                Text(midi.status).font(.caption).foregroundStyle(QinXuTheme.muted)
                Spacer()
                Button("刷新") { model.refreshMIDI() }
            }
        case .touch:
            Text("触屏琴键可按住和同时弹奏，当前不发声。")
                .font(.caption).foregroundStyle(QinXuTheme.muted)
        case .microphone:
            Text(microphone.status).font(.subheadline)
            ProgressView(value: min(1, max(0, microphone.level)))
                .accessibilityLabel("麦克风输入音量")
            if let pitch = microphone.detectedPitch {
                Text(NoteNames.name(pitch)).font(.subheadline.monospacedDigit())
            }
            Text("实验功能。请用识谱模式逐个弹奏 C3–C6，避免延音踏板和和弦。")
                .font(.caption).foregroundStyle(QinXuTheme.amber)
        }
    }
}

private struct PracticeHistoryView: View {
    var history: [PracticeSummary]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if history.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32)).foregroundStyle(QinXuTheme.accent)
                            .accessibilityHidden(true)
                        Text("暂无练习记录").font(.headline).accessibilityIdentifier("history.empty")
                        Text("完成一轮练习后，记录会显示在这里。")
                            .font(.subheadline).foregroundStyle(QinXuTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(history.sorted { $0.date > $1.date }) { record in
                            PracticeCard {
                                VStack(alignment: .leading, spacing: 9) {
                                    Text(record.scoreTitle).font(.headline)
                                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(QinXuTheme.muted)
                                    Text("正确 \(record.correct) · 错音 \(record.wrong) · 漏音 \(record.missed) · \(Int(record.durationSeconds)) 秒")
                                        .font(.caption.monospacedDigit()).foregroundStyle(QinXuTheme.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .background(QinXuTheme.background)
            .navigationTitle("练习记录")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("history.close")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 390, minHeight: 420)
        #endif
    }
}
