import SwiftUI
import QinXuCore

struct PracticeHistoryContent: View {
    let history: [PracticeSummary]
    let scores: [PianoScore]
    var compact: Bool
    var onPractice: (String) -> Void
    var onClose: () -> Void

    private var ordered: [PracticeSummary] { history.sorted { $0.date > $1.date } }
    private var duration: Int { Int(history.reduce(0) { $0 + $1.durationSeconds } / 60) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 14 : 22) {
                HStack {
                    Label("练习记录", systemImage: "chart.bar.xaxis").font(.system(size: compact ? 20 : 25, weight: .semibold))
                    Spacer()
                    Button(action: onClose) { Label("曲谱", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("history.close")
                }
                if history.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 32)).foregroundStyle(QinXuTheme.teal)
                        Text("暂无练习记录").font(.headline).accessibilityIdentifier("history.empty")
                        Text("完成一轮练习后显示记录。")
                            .font(.subheadline).foregroundStyle(QinXuTheme.muted)
                    }.frame(maxWidth: .infinity).padding(.vertical, compact ? 35 : 95)
                } else {
                    HStack(spacing: 12) {
                        metric("已完成", value: "\(history.count)", unit: "次", symbol: "checkmark.circle")
                        metric("练习时长", value: "\(duration)", unit: "分钟", symbol: "clock")
                        metric("累计正确", value: "\(history.reduce(0) { $0 + $1.correct })", unit: "音", symbol: "music.note")
                    }
                    ForEach(ordered) { record in recordCard(record) }
                }
            }.padding(compact ? 16 : 26)
        }.accessibilityIdentifier("history.scroll")
    }

    private func metric(_ title: String, value: String, unit: String, symbol: String) -> some View {
        PracticeCard(padding: compact ? 12 : 17) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol).font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value).font(.system(size: compact ? 25 : 31, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(unit).font(.system(size: 10)).foregroundStyle(QinXuTheme.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recordCard(_ record: PracticeSummary) -> some View {
        PracticeCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.scoreTitle).font(.system(size: 16, weight: .semibold))
                        Text(record.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                    }
                    Spacer()
                    Text(record.mode.title).font(.system(size: 11)).foregroundStyle(QinXuTheme.teal)
                        .padding(7).background(QinXuTheme.sage, in: Capsule())
                }
                ViewThatFits(in: .horizontal) {
                    HStack { results(record); Spacer(); retry(record) }
                    VStack(alignment: .leading, spacing: 12) { results(record); retry(record) }
                }
            }
        }
    }

    private func results(_ record: PracticeSummary) -> some View {
        HStack(spacing: 16) {
            Label("正确 \(record.correct)", systemImage: "checkmark.circle").foregroundStyle(QinXuTheme.teal)
            Label("错音 \(record.wrong)", systemImage: "xmark.circle").foregroundStyle(QinXuTheme.wrong)
            Label("漏音 \(record.missed)", systemImage: "minus.circle")
            Text("\(Int(record.durationSeconds)) 秒")
        }.font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
    }

    @ViewBuilder private func retry(_ record: PracticeSummary) -> some View {
        // Older summaries have no score ID. Only offer a retry when the title is unambiguous.
        let matches = scores.filter { $0.title == record.scoreTitle }
        if matches.count == 1, let score = matches.first {
            Button { onPractice(score.id) } label: { Label("再练这首", systemImage: "arrow.counterclockwise") }
                .buttonStyle(QuietButtonStyle(prominent: true))
        }
    }
}
