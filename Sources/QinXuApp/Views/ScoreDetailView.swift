import SwiftUI
import QinXuCore

struct ScoreDetailView: View {
    @ObservedObject var model: PracticeViewModel
    let score: PianoScore
    let compact: Bool
    let onBack: () -> Void
    let onPractice: () -> Void
    let onCover: () -> Void

    private var isFavorite: Bool { model.favoriteScoreIDs.contains(score.id) }
    private var isOriginal: Bool { DemoScores.all.contains { $0.id == score.id } }
    private var sourceTitle: String { BundledPracticeLibrary.ids.contains(score.id) ? "内置教材" : isOriginal ? "原创样谱" : "已导入" }
    private var checkpoint: PracticeCheckpoint? {
        guard let value = model.progress(for: score.id), !value.isCompleted else { return nil }
        return value
    }
    private var hands: String {
        let right = score.notes.contains { $0.staff == 1 }
        let left = score.notes.contains { $0.staff == 2 }
        return right && left ? "双手" : left ? "左手" : "右手"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 12 : 20) {
                Button(action: onBack) { Label("返回曲谱", systemImage: "arrow.left") }
                    .font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(QinXuTheme.muted)
                    .accessibilityIdentifier("detail.back")
                heading
                if let checkpoint { resumeCard(checkpoint) }
                preview
                notationNotes
            }
            .padding(.bottom, 18)
        }
        .foregroundStyle(QinXuTheme.ink)
        .accessibilityIdentifier("detail.scroll")
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: compact ? 16 : 24) {
            ScoreCoverView(score: score, imageData: model.scoreCoverData[score.id])
                .frame(width: compact ? 72 : 108, height: compact ? 96 : 144)
            VStack(alignment: .leading, spacing: compact ? 7 : 11) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        titleAndComposer
                        Spacer(minLength: 5)
                        actions
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        titleAndComposer
                        actions
                    }
                }
                metadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleAndComposer: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(score.title).font(.system(size: compact ? 21 : 27, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("detail.title")
            if !score.composer.isEmpty {
                Label(score.composer, systemImage: "person")
                    .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if checkpoint == nil {
                Button(action: onPractice) { Label("开始练习", systemImage: "play.fill") }
                    .buttonStyle(QuietButtonStyle(prominent: true))
                    .accessibilityIdentifier("detail.practice")
            }
            Button { model.toggleFavorite(score.id) } label: {
                Image(systemName: isFavorite ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityLabel(isFavorite ? "取消收藏" : "加入谱架")
            .accessibilityValue(isFavorite ? "已收藏" : "未收藏")
            .accessibilityIdentifier("detail.favorite")
            Menu {
                Button(action: onCover) { Label("更换封面", systemImage: "photo.badge.plus") }
                if model.scoreCoverData[score.id] != nil {
                    Button { model.removeCover(for: score.id) } label: { Label("恢复默认封面", systemImage: "arrow.counterclockwise") }
                }
            } label: { Image(systemName: "photo") }
                .font(.system(size: 13)).padding(10)
                .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(QinXuTheme.line, lineWidth: 1))
                .accessibilityLabel("曲谱封面").accessibilityIdentifier("detail.cover")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func resumeCard(_ progress: PracticeCheckpoint) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Label("上次停在第 \(progress.measure) 小节", systemImage: "bookmark.circle")
                    .font(.system(size: compact ? 12 : 14, weight: .medium))
                    .accessibilityIdentifier("detail.progress")
                Text("\(progress.hand.title) · \(progress.mode.title) · 上次 ♩\(Int(progress.tempoBPM))")
                    .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            }
            Spacer(minLength: 4)
            Button { model.resume(scoreID: score.id); onPractice() } label: {
                Label("继续练习", systemImage: "play.fill")
            }.buttonStyle(QuietButtonStyle(prominent: true)).accessibilityIdentifier("detail.resume")
            Button {
                if model.selectedScoreID != score.id { model.selectScore(score.id) }
                model.loopEnabled = false
                model.restart()
                onPractice()
            } label: { Label("从头", systemImage: "arrow.counterclockwise") }
                .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("detail.restart")
        }
        .padding(compact ? 12 : 16)
        .background(QinXuTheme.sage, in: RoundedRectangle(cornerRadius: 12))
    }

    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) { metadataItems }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    tag("\(score.measures.count) 小节", symbol: "music.note.list")
                    tag("\(score.beatsPerMeasure)/\(score.beatUnit) 拍", symbol: "timer")
                    tag("原谱 ♩\(Int(score.tempoBPM))", symbol: "metronome")
                }
                HStack(spacing: 7) {
                    tag(hands, symbol: "hand.raised")
                    tag(sourceTitle, symbol: isOriginal ? "music.note" : "doc")
                }
            }
        }
    }

    @ViewBuilder private var metadataItems: some View {
        tag("\(score.measures.count) 小节", symbol: "music.note.list")
        tag("\(score.beatsPerMeasure)/\(score.beatUnit) 拍", symbol: "timer")
        tag("原谱 ♩\(Int(score.tempoBPM))", symbol: "metronome")
        tag(hands, symbol: "hand.raised")
        tag(sourceTitle, symbol: isOriginal ? "music.note" : "doc")
    }

    private func tag(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 11))
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(QinXuTheme.line.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
            .fixedSize(horizontal: true, vertical: false)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("曲谱预览", systemImage: "doc.text").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("简化练习谱").font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            }.padding(.horizontal, compact ? 12 : 20).padding(.top, compact ? 10 : 18)
            PracticeScoreView(score: score, hand: .both, currentBeat: 0,
                              expectedNotes: [], verdicts: [:], active: false, compact: compact)
        }
        .padding(.bottom, 8)
        .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(QinXuTheme.line, lineWidth: 1))
    }

    private var notationNotes: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("按实际音高与拍点显示；未还原原谱连线、表情与版式。")
            ForEach(score.warnings, id: \.self) { warning in
                Label(warning, systemImage: "info.circle")
            }
        }
        .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
