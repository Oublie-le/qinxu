import SwiftUI
import QinXuCore

struct BookPracticeView: View {
    let book: BundledBook
    let compact: Bool
    let onSelect: (String) -> Void
    let onPractice: (String) -> Void
    var filterScore: (PianoScore) -> Bool = { _ in true }
    @Environment(\.dismiss) private var dismiss
    @State private var showingSource = false
    @State private var query = ""

    private var catalogue: BundledPracticeLibrary.Catalogue { BundledPracticeLibrary.beyer }
    private var lessons: [PianoScore] {
        catalogue.scores.filter { filterScore($0) && (query.isEmpty || $0.title.localizedStandardContains(query)) }
    }

    var body: some View {
        let sourcePages = Dictionary(uniqueKeysWithValues: catalogue.lessons.map { ($0.id, $0.sourcePage) })
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 36, height: 36) }
                    .buttonStyle(.plain).accessibilityLabel("关闭教材目录")
                    .accessibilityIdentifier("textbook.close")
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title).font(.system(size: compact ? 18 : 23, weight: .semibold))
                        .accessibilityIdentifier("textbook.title")
                    Text("中文练习 · \(catalogue.scores.count) 项 · 作品 101")
                        .font(.system(size: 12)).foregroundStyle(QinXuTheme.teal)
                }
                Spacer(minLength: 4)
                Menu {
                    Text("公版原作整理，非出版社中文版")
                    Text("录谱：RANOTE · CC BY 4.0")
                    Text("琴序：中文目录与练习数据转换")
                    Link("录谱来源与许可", destination: URL(string: "https://ranote.zzxxccvv.com/en/book/beyer")!)
                    Link("上海音乐出版社拜厄版本", destination: URL(string: "https://www.smph.cn/NewsDetails.aspx?id=545")!)
                    Button("查看公版原书（外文）") { showingSource = true }
                } label: { Image(systemName: "info.circle").frame(width: 36, height: 36) }
                    .accessibilityLabel("教材版本与来源")
                Button { showingSource = true } label: { Label("外文原书", systemImage: "book") }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityLabel("查看公版外文原书")
                    .accessibilityIdentifier("textbook.source")
            }.padding(compact ? 12 : 20)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                TextField("查找课次", text: $query)
                    .textFieldStyle(.plain).padding(10)
                    .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("textbook.search")
                Text("点课次看谱，点「练习」开始弹奏。原书页码可用于对照指法和教师伴奏。")
                    .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                if let error = catalogue.error {
                    Text(error).font(.system(size: 13)).foregroundStyle(QinXuTheme.wrong)
                }
            }.padding(.horizontal, compact ? 12 : 20).padding(.vertical, 10)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(lessons) { score in
                        HStack(spacing: 12) {
                            Button { onSelect(score.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "music.note.list").foregroundStyle(QinXuTheme.teal)
                                        .frame(width: 32, height: 36)
                                        .background(QinXuTheme.sage, in: RoundedRectangle(cornerRadius: 7))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(score.title.replacingOccurrences(of: "拜厄 · ", with: ""))
                                            .font(.system(size: 15, weight: .medium))
                                        HStack(spacing: 8) {
                                            Text("\(score.measures.count) 小节 · \(score.beatsPerMeasure)/\(score.beatUnit) 拍")
                                            if let page = sourcePages[score.id] {
                                                Text("原书第 \(page) 页")
                                            }
                                        }.font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                                    }
                                    Spacer()
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("textbook.lesson." + score.id)
                            Button { onPractice(score.id) } label: { Label("练习", systemImage: "play.fill") }
                                .buttonStyle(QuietButtonStyle(prominent: true))
                                .accessibilityIdentifier("textbook.practice." + score.id)
                        }.padding(.vertical, 12)
                        Divider().overlay(QinXuTheme.line)
                    }
                    if lessons.isEmpty && catalogue.error == nil {
                        Text("没有匹配的课次").foregroundStyle(QinXuTheme.muted).padding(24)
                    }
                }.padding(.horizontal, compact ? 12 : 20)
            }.accessibilityIdentifier("textbook.lessons")
        }
        .foregroundStyle(QinXuTheme.ink).background(QinXuTheme.background)
        .sheet(isPresented: $showingSource) { BookReaderView(book: book, compact: compact) }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: compact ? 320 : 440)
        #endif
    }

}
