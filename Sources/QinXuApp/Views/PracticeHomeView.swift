import SwiftUI
import UniformTypeIdentifiers
import QinXuCore

/// App navigation and device presentation stay outside the deterministic practice engine.
struct PracticeHomeView: View {
    @ObservedObject var model: PracticeViewModel
    @State private var section: QinXuSection = .library
    @State private var detailScoreID: String?
    @State private var showingDevices = false
    @State private var coverSelection: CoverSelection?
    @State private var immersivePractice = false

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 550 && geometry.size.width > geometry.size.height
            let labels = geometry.size.width >= 800 && !compact
            let immersed = immersivePractice && section == .practice && detailScoreID == nil
            HStack(spacing: 0) {
                if !immersed {
                    navigation(labels: labels)
                        .frame(width: labels ? 174 : 62)
                    Rectangle().fill(QinXuTheme.line).frame(width: 1)
                }
                VStack(spacing: 0) {
                    if !compact && !immersed { header }
                    content(compact: compact)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(QinXuTheme.background)
        }
        .tint(QinXuTheme.accent)
        .foregroundStyle(QinXuTheme.ink)
        .preferredColorScheme(.light)
        .sheet(isPresented: $model.isImporting) {
            LibraryImportView(model: model, onScoreImported: { id in
                detailScoreID = id; section = .library
            }, onDocumentImported: { _ in
                detailScoreID = nil; section = .library
            })
        }
        .alert("暂时无法完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(isPresented: $showingDevices) {
            NavigationStack {
                InputConnectionView(model: model)
                    .background(QinXuTheme.background)
                    .navigationTitle("演奏输入")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showingDevices = false }.accessibilityIdentifier("devices.close")
                        }
                    }
            }.frame(minWidth: 320, minHeight: 260)
        }
        .sheet(item: $coverSelection) { selection in
            if let score = model.scores.first(where: { $0.id == selection.id }) {
                ScoreCoverEditor(model: model, score: score)
            }
        }
        .sheet(isPresented: $model.showingMetronomeSettings) {
            GlobalMetronomeSettingsView(model: model)
        }
    }

    @ViewBuilder private func content(compact: Bool) -> some View {
        if let id = detailScoreID, let score = model.scores.first(where: { $0.id == id }) {
            ScoreDetailView(model: model, score: score, compact: compact,
                onBack: { detailScoreID = nil }, onPractice: { practice(id) },
                onCover: { editCover(id) })
                .padding(compact ? 12 : 24)
        } else {
            switch section {
            case .library, .favorites:
                ScoreLibraryView(model: model, compact: compact, favoritesOnly: section == .favorites,
                    onSelect: { detailScoreID = $0 }, onPractice: practice,
                    onImport: {
                        model.pausePractice()
                        model.isImporting = true
                    }, onCover: editCover)
                    .padding(compact ? 12 : 24)
            case .practice:
                PracticeSessionView(model: model, compact: compact, onExit: {
                    model.pausePractice()
                    immersivePractice = false
                    section = .library
                    detailScoreID = model.selectedScoreID
                }, onShowDevices: openDevices, immersive: immersivePractice,
                   onToggleImmersion: { immersivePractice.toggle() })
            case .history:
                PracticeHistoryContent(history: model.history, scores: model.scores,
                    compact: compact, onPractice: { id in
                        practice(id)
                        model.restart()
                    }, onClose: { navigate(.library) })
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(detailScoreID == nil ? section.title : "曲谱详情")
                .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            Spacer()
            Label("本地曲库", systemImage: "internaldrive")
                .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            Button(action: openDevices) {
                Label(model.inputMode.title, systemImage: model.inputMode.isMicrophone ? "mic" : "pianokeys")
                    .font(.system(size: 11))
            }.buttonStyle(.plain).accessibilityIdentifier("devices.open")
        }.padding(.horizontal, 24).frame(height: 45)
    }

    private func navigation(labels: Bool) -> some View {
        VStack(alignment: labels ? .leading : .center, spacing: labels ? 8 : 4) {
            Button { navigate(.library) } label: { QinXuWordmark(compact: !labels) }
                .buttonStyle(.plain).accessibilityLabel("琴序首页")
                .padding(.horizontal, labels ? 12 : 0).padding(.top, labels ? 25 : 8)
                .padding(.bottom, labels ? 23 : 4)
            ForEach(QinXuSection.allCases) { item in
                Button { navigate(item) } label: {
                    navigationLabel(item, labels: labels)
                }
                .buttonStyle(.plain)
                .foregroundStyle(section == item && detailScoreID == nil ? QinXuTheme.accent : QinXuTheme.ink)
                .background(section == item && detailScoreID == nil ? QinXuTheme.softAccent : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier(item.identifier)
                .accessibilityAddTraits(section == item && detailScoreID == nil ? .isSelected : [])
            }
            Spacer(minLength: 4)
            Button { model.openMetronomeSettings() } label: {
                if labels {
                    HStack(spacing: 10) {
                        Image(systemName: "metronome").font(.system(size: 17))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("节拍器").font(.system(size: 12, weight: .medium))
                            Text("\(model.metronomeSettings.beatsPerMeasure)/\(model.metronomeSettings.beatUnit) · \(model.metronomeSettings.tempoNote.symbol) \(Int(model.metronomeSettings.tempoBPM))")
                                .font(.system(size: 10)).monospacedDigit().foregroundStyle(QinXuTheme.muted)
                        }
                        Spacer(minLength: 0)
                        if model.metronomeRunning { Circle().fill(QinXuTheme.accent).frame(width: 5, height: 5) }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "metronome").font(.system(size: 17))
                        Text("节拍器").font(.system(size: 9))
                    }.frame(width: 50, height: 44)
                }
            }.buttonStyle(.plain)
                .foregroundStyle(model.metronomeRunning ? QinXuTheme.accent : QinXuTheme.ink)
                .background(model.metronomeRunning ? QinXuTheme.softAccent : .clear, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("全局节拍器")
                .accessibilityValue(model.metronomeRunning ? "正在运行" : "已停止")
                .accessibilityIdentifier("navigation.metronome")
            Button(action: openDevices) {
                if labels {
                    Label("演奏输入", systemImage: model.inputMode.isMicrophone ? "mic" : "cable.connector")
                        .font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(QinXuTheme.sage, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "mic.and.signal.meter").font(.system(size: 17))
                        .frame(width: 44, height: 40)
                }
            }.buttonStyle(.plain).foregroundStyle(QinXuTheme.teal)
                .accessibilityLabel("演奏输入与设备").accessibilityIdentifier("navigation.devices")
                .padding(.bottom, labels ? 18 : 4)
        }.padding(.horizontal, labels ? 15 : 5)
            .frame(maxHeight: .infinity).background(QinXuTheme.paper)
    }

    @ViewBuilder private func navigationLabel(_ item: QinXuSection, labels: Bool) -> some View {
        if labels {
            HStack(spacing: 12) {
                Image(systemName: item.symbol).font(.system(size: 17)).frame(width: 21)
                Text(item.title).font(.system(size: 13))
            }.padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
        } else {
            VStack(spacing: 4) {
                Image(systemName: item.symbol).font(.system(size: 17))
                Text(item.shortTitle).font(.system(size: 9))
            }.frame(width: 50, height: 44)
        }
    }

    private func navigate(_ next: QinXuSection) {
        model.stopAudition()
        if section == .practice && next != .practice { model.pausePractice() }
        if next != .practice { immersivePractice = false }
        detailScoreID = nil
        section = next
    }
    private func practice(_ id: String) {
        model.stopAudition()
        if model.selectedScoreID != id { model.selectScore(id) }
        detailScoreID = nil
        section = .practice
    }
    private func openDevices() {
        model.pausePractice()
        showingDevices = true
    }
    private func editCover(_ id: String) {
        model.pausePractice()
        coverSelection = CoverSelection(id: id)
    }
}

private struct CoverSelection: Identifiable { let id: String }
private enum QinXuSection: String, CaseIterable, Identifiable {
    case library, favorites, practice, history
    var id: Self { self }
    var title: String {
        switch self { case .library: return "曲谱"; case .favorites: return "我的谱架"; case .practice: return "练琴"; case .history: return "练习记录" }
    }
    var shortTitle: String { self == .favorites ? "谱架" : self == .history ? "记录" : title }
    var symbol: String {
        switch self { case .library: return "square.grid.2x2"; case .favorites: return "books.vertical"; case .practice: return "pianokeys"; case .history: return "chart.bar.xaxis" }
    }
    var identifier: String {
        switch self { case .library: return "library.open"; case .favorites: return "favorites.open"; case .practice: return "practice.open"; case .history: return "history.open" }
    }
}

private struct ScoreCoverEditor: View {
    @ObservedObject var model: PracticeViewModel
    let score: PianoScore
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ScoreCoverView(score: score, imageData: model.scoreCoverData[score.id])
                        .frame(width: 114, height: 152)
                    Text(score.title).font(.headline)
                    Button { importing = true } label: { Label("选择封面图片", systemImage: "photo.badge.plus") }
                        .buttonStyle(QuietButtonStyle(prominent: true)).accessibilityIdentifier("cover.choose")
                    Text("JPG / PNG / WebP · 最大 8 MB\n封面仅保存在这台设备上。")
                        .font(.caption).foregroundStyle(QinXuTheme.muted).multilineTextAlignment(.center)
                    if model.scoreCoverData[score.id] != nil {
                        Button { model.removeCover(for: score.id) } label: { Label("恢复默认封面", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("cover.reset")
                    }
                }.frame(maxWidth: .infinity).padding(20)
            }.background(QinXuTheme.background)
                .navigationTitle("曲谱封面")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.jpeg, .png, .webP]) { result in
                    switch result {
                    case .success(let url): model.importCover(from: url, for: score.id)
                    case .failure(let error): model.errorMessage = error.localizedDescription
                    }
                }
                .alert("封面未更新", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button("知道了", role: .cancel) { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }.frame(minWidth: 320, minHeight: 280)
    }
}
