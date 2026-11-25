import SwiftUI
import QinXuCore

/// All scores and advice come from evaluated events in QinXuCore.
struct PracticeReportView: View {
    let report: PracticeReport
    let scoreTitle: String
    let compact: Bool
    let onClose: () -> Void
    var onRetry: (() -> Void)? = nil
    var onMeasure: ((Int) -> Void)? = nil

    private var issueMeasures: [PracticeMeasureResult] { report.measureResults.filter(\.hasIssues) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 16 : 24) {
                    overview
                    measurements
                    suggestions
                    if !issueMeasures.isEmpty { measureReview }
                    DisclosureGroup("分数怎么算") {
                        Text(report.formulaDescription)
                            .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
                            .lineSpacing(4).padding(.top, 8)
                    }.font(.system(size: 13)).accessibilityIdentifier("report.formula")
                    if let onRetry {
                        Button(action: onRetry) {
                            Label("再练一遍", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(QuietButtonStyle(prominent: true))
                            .accessibilityIdentifier("report.retry")
                    }
                }
                .padding(compact ? 16 : 24)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("report.scroll")
            .background(QinXuTheme.background)
            .foregroundStyle(QinXuTheme.ink)
            .navigationTitle("练习报告")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: onClose).accessibilityIdentifier("report.close")
                }
            }
        }
        .tint(QinXuTheme.accent)
        .frame(minWidth: 320, minHeight: 280)
    }

    private var overview: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(scoreTitle).font(.system(size: compact ? 21 : 27, weight: .semibold))
                    .accessibilityIdentifier("report.title")
                Text("\(report.mode.title) · \(report.hand.title) · \(Int(report.tempoBPM)) BPM")
                    .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
                if let source = report.inputSource {
                    Text("输入：" + source).font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                        .accessibilityIdentifier("report.inputSource")
                    if source.contains("麦克风") {
                        Text("实验识音，结果可能含识别误差。")
                            .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                    }
                }
                Text("第 \(report.startMeasure)–\(report.endMeasure) 小节 · \(report.isComplete ? "已完成" : "本次片段")")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(QinXuTheme.teal)
                if !report.isComplete {
                    Text("已判定 \(report.evaluatedNotes) / \(report.totalNotes) 个音符，尚未生成完整得分。")
                        .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                }
            }
            Spacer(minLength: 0)
            if let score = report.overallScore {
                VStack(spacing: 3) {
                    Text("\(score)").font(.system(size: compact ? 42 : 55, weight: .medium, design: .rounded))
                    Text("总分 / 100").font(.system(size: 11))
                }.foregroundStyle(QinXuTheme.accent)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("总分").accessibilityValue("\(score)")
                    .accessibilityIdentifier("report.overallScore")
            }
        }
    }

    private var measurements: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 115 : 145), spacing: 10)], spacing: 10) {
            metric("音高准确率", value: report.pitchAccuracy.map { String(format: "%.1f%%", $0) } ?? "未评定", symbol: "target", color: QinXuTheme.teal, identifier: "pitchAccuracy")
            metric("正确音", value: String(report.correct), symbol: "checkmark.circle", color: QinXuTheme.teal, identifier: "correct")
            metric("错音次数", value: String(report.wrong), symbol: "xmark.circle", color: QinXuTheme.wrong, identifier: "wrong")
            if report.mode == .rhythm {
                metric("漏音", value: report.missed.map(String.init) ?? "未评定", symbol: "minus.circle", color: QinXuTheme.amber, identifier: "missed")
                metric("抢拍", value: report.early.map(String.init) ?? "未评定", symbol: "backward.end", color: QinXuTheme.amber, identifier: "early")
                metric("拖拍", value: report.late.map(String.init) ?? "未评定", symbol: "forward.end", color: QinXuTheme.amber, identifier: "late")
                metric("节奏分", value: report.rhythmScore.map { "\($0) / 100" } ?? "未完成", symbol: "metronome", color: QinXuTheme.teal, identifier: "rhythmScore")
                metric("平均起音偏差", value: report.meanAbsoluteOnsetErrorMilliseconds.map { "\(Int($0.rounded())) ms" } ?? "未评定", symbol: "waveform.path", color: QinXuTheme.ink, identifier: "onsetError")
            }
        }.accessibilityIdentifier("report.metrics")
    }

    private func metric(_ label: String, value: String, symbol: String, color: Color, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(label, systemImage: symbol).font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            Text(value).font(.system(size: compact ? 22 : 26, weight: .medium, design: .rounded))
                .monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(QinXuTheme.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label).accessibilityValue(value)
        .accessibilityIdentifier("report.metric." + identifier)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("下一遍怎么练", systemImage: "lightbulb").font(.system(size: 16, weight: .semibold))
            ForEach(Array(report.suggestions.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 10) {
                    Text(String(index + 1)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .frame(width: 22, height: 22).background(QinXuTheme.sage, in: Circle())
                    Text(text).font(.system(size: 13)).lineSpacing(3)
                }
            }
            if report.mode == .wait {
                Text("识谱模式会等你弹对；本报告不评抢拍、拖拍、漏音或松键时长。")
                    .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            }
        }.accessibilityIdentifier("report.suggestions")
    }

    private var measureReview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("需要复习的小节", systemImage: "music.note.list").font(.system(size: 16, weight: .semibold))
            ForEach(issueMeasures) { measure in
                HStack(spacing: 12) {
                    Text("第 \(measure.measure) 小节").font(.system(size: 13, weight: .medium)).monospacedDigit()
                    Text(issueDescription(measure)).font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                    Spacer(minLength: 4)
                    if let onMeasure {
                        Button { onMeasure(measure.measure) } label: {
                            Label("练这节", systemImage: "repeat").font(.system(size: 11))
                        }.buttonStyle(QuietButtonStyle())
                            .accessibilityIdentifier("report.measure.\(measure.measure)")
                    }
                }.padding(12).background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func issueDescription(_ measure: PracticeMeasureResult) -> String {
        var items: [String] = []
        if measure.wrong > 0 { items.append("错音 \(measure.wrong)") }
        if let missed = measure.missed, missed > 0 { items.append("漏音 \(missed)") }
        if let early = measure.early, early > 0 { items.append("抢拍 \(early)") }
        if let late = measure.late, late > 0 { items.append("拖拍 \(late)") }
        return items.joined(separator: " · ")
    }
}
