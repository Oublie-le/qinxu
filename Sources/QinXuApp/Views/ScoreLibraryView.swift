import SwiftUI
import QinXuCore

struct ScoreLibraryView: View {
    @ObservedObject var model: PracticeViewModel
    let compact: Bool
    let favoritesOnly: Bool
    let onSelect: (String) -> Void
    let onPractice: (String) -> Void
    let onImport: () -> Void
    let onCover: (String) -> Void
    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    @State private var readingBook: BundledBook?

    private var demoIDs: Set<String> { Set(DemoScores.all.map(\.id)) }
    private var matchingScores: [PianoScore] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.scores.filter { score in
            if favoritesOnly && !model.favoriteScoreIDs.contains(score.id) { return false }
            switch filter {
            case .all: break
            case .original: if !demoIDs.contains(score.id) { return false }
            case .imported: if BundledPracticeLibrary.allBundledIDs.contains(score.id) { return false }
            case .favorites: if !model.favoriteScoreIDs.contains(score.id) { return false }
            case .books: return false
            }
            if !favoritesOnly && filter == .all && text.isEmpty && BundledPracticeLibrary.ids.contains(score.id) { return false }
            return text.isEmpty || score.title.localizedStandardContains(text)
                || score.composer.localizedStandardContains(text)
        }
    }

    private var matchingBooks: [BundledBook] {
        guard !favoritesOnly, filter == .all || filter == .books else { return [] }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return BundledBook.all.filter { book in
            text.isEmpty || book.title.localizedStandardContains(text)
                || book.composer.localizedStandardContains(text)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let count = max(1, min(6, Int((geometry.size.width + 12) / (compact ? 108 : 130))))
            VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                header
                filters
                if !favoritesOnly && filter != .books { currentScoreStrip }
                results(columns: count)
            }
        }
        .foregroundStyle(QinXuTheme.ink)
        .onChange(of: favoritesOnly) { _, _ in filter = .all }
        .sheet(item: $readingBook) { book in
            BookPracticeView(book: book, compact: compact,
                             onSelect: { id in readingBook = nil; onSelect(id) },
                             onPractice: { id in readingBook = nil; onPractice(id) })
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                pageTitle
                searchField.frame(minWidth: 145)
                headerActions
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack { pageTitle; Spacer(); headerActions }
                searchField
            }
        }
    }

    private var pageTitle: some View {
        Text(favoritesOnly ? "我的谱架" : "曲谱")
            .font(.system(size: compact ? 20 : 23, weight: .semibold))
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("library.title")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(QinXuTheme.muted)
            TextField("搜索曲名、作曲家", text: $query)
                .textFieldStyle(.plain).font(.system(size: 13))
                .autocorrectionDisabled()
                .accessibilityLabel("搜索曲名、作曲家")
                .accessibilityIdentifier("library.search")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(QinXuTheme.muted)
                    .accessibilityLabel("清除搜索").accessibilityIdentifier("library.search.clear")
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 40)
        .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(QinXuTheme.line, lineWidth: 1))
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            Button { onCover(model.selectedScoreID) } label: { Label("封面", systemImage: "photo.badge.plus") }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel("管理曲谱封面").accessibilityIdentifier("library.cover")
            Button(action: onImport) { Label("导入", systemImage: "plus") }
                .buttonStyle(QuietButtonStyle(prominent: true))
                .accessibilityIdentifier("library.import")
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) { filterButtons }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) { filterButtons }
            }
        }
    }

    @ViewBuilder private var filterButtons: some View {
        ForEach(LibraryFilter.allCases.filter { !favoritesOnly || ($0 != .favorites && $0 != .books) }) { item in
            Button { filter = item } label: {
                Label(item.title, systemImage: item.symbol)
                    .font(.system(size: 12, weight: filter == item ? .medium : .regular))
                    .padding(.horizontal, 12).frame(minHeight: compact ? 32 : 36)
                    .foregroundStyle(filter == item ? QinXuTheme.paper : QinXuTheme.ink)
                    .background(filter == item ? QinXuTheme.ink : QinXuTheme.paper, in: Capsule())
                    .overlay(Capsule().stroke(filter == item ? Color.clear : QinXuTheme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityValue(filter == item ? "已选" : "未选")
            .accessibilityIdentifier("library.filter." + item.rawValue)
        }
    }

    private var currentScoreStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 15)).foregroundStyle(QinXuTheme.teal)
                .frame(width: 30, height: 30)
                .background(QinXuTheme.sage, in: RoundedRectangle(cornerRadius: 8))
            Text("当前曲谱").font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            Text(model.selectedScore.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            if !compact {
                Text("\(model.selectedScore.measures.count) 小节 · \(Int(model.selectedScore.tempoBPM)) BPM")
                    .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { onPractice(model.selectedScoreID) } label: {
                Label("练习", systemImage: "play.fill").font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12).frame(minHeight: 34)
                    .foregroundStyle(QinXuTheme.accent)
                    .background(QinXuTheme.softAccent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain).accessibilityIdentifier("library.continue")
        }
        .padding(.horizontal, 12).padding(.vertical, compact ? 5 : 8)
        .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(QinXuTheme.line, lineWidth: 1))
    }

    private func results(columns: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 11 : 16) {
                HStack {
                    Label(filter == .books ? "教材" : "曲谱", systemImage: filter == .books ? "books.vertical" : "music.note.list")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(matchingBooks.isEmpty ? "\(matchingScores.count) 首" : filter == .books ? "\(matchingBooks.count) 册" : "\(matchingScores.count) 首 · \(matchingBooks.count) 册教材")
                        .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                        .accessibilityIdentifier("library.results.count")
                }
                if matchingScores.isEmpty && matchingBooks.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0, maximum: compact ? 116 : 140), spacing: 14, alignment: .top), count: columns), alignment: .leading, spacing: 20) {
                        ForEach(matchingBooks) { book in
                            BookLibraryCard(book: book, compact: compact) { readingBook = book }
                        }
                        ForEach(matchingScores) { score in
                            ScoreLibraryCard(score: score, imageData: model.scoreCoverData[score.id],
                                             isFavorite: model.favoriteScoreIDs.contains(score.id),
                                             isOriginal: demoIDs.contains(score.id), compact: compact,
                                             onOpen: { onSelect(score.id) },
                                             onFavorite: { model.toggleFavorite(score.id) },
                                             onPractice: { onPractice(score.id) },
                                             onCover: { onCover(score.id) })
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 1).padding(.bottom, 18)
        }
        .accessibilityIdentifier("library.scroll")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: query.isEmpty ? "books.vertical" : "magnifyingglass")
                .font(.system(size: 28)).foregroundStyle(QinXuTheme.muted)
            Text(query.isEmpty ? "暂无曲谱" : "没有匹配的曲谱").font(.system(size: 15, weight: .medium))
            Text(favoritesOnly ? "在曲谱卡片上点收藏，即可加入谱架。" : "更换筛选条件，或导入 MusicXML 曲谱。")
                .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, compact ? 20 : 50)
        .accessibilityIdentifier("library.empty")
    }
}

private enum LibraryFilter: String, Identifiable, CaseIterable {
    case all, books, original, imported, favorites
    var id: String { rawValue }
    var title: String {
        switch self { case .all: return "全部"; case .books: return "教材"; case .original: return "原创样谱"; case .imported: return "已导入"; case .favorites: return "收藏" }
    }
    var symbol: String {
        switch self { case .all: return "square.grid.2x2"; case .books: return "books.vertical"; case .original: return "music.note"; case .imported: return "square.and.arrow.down"; case .favorites: return "bookmark" }
    }
}

private struct BookLibraryCard: View {
    let book: BundledBook
    let compact: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                BookCoverView(book: book)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .frame(maxWidth: compact ? 92 : 140)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "book").font(.system(size: 12))
                            .frame(width: 28, height: 28)
                            .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 7)).padding(4)
                    }
                Text(book.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Label("中文练习谱", systemImage: "music.note.list")
                    .font(.system(size: 10)).foregroundStyle(QinXuTheme.muted).lineLimit(1)
                Text("\(BundledPracticeLibrary.beyer.scores.count) 项练习").font(.system(size: 10)).foregroundStyle(QinXuTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开教材：\(book.title)，中文练习谱，\(BundledPracticeLibrary.beyer.scores.count) 项练习")
        .accessibilityIdentifier("library.book." + book.id)
    }
}

private struct BookCoverView: View {
    let book: BundledBook

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color(red: 0.88, green: 0.90, blue: 0.84)
                VStack(alignment: .leading, spacing: 5) {
                    Text("拜厄").font(.system(size: geometry.size.width < 100 ? 23 : 30, weight: .semibold, design: .serif))
                    Text("钢琴基本教程").font(.system(size: geometry.size.width < 100 ? 8 : 11))
                    Rectangle().fill(QinXuTheme.teal.opacity(0.3)).frame(height: 1).padding(.top, 4)
                    Text("作品 101").font(.system(size: 9)).foregroundStyle(QinXuTheme.muted)
                    Spacer(minLength: 4)
                    Image(systemName: "pianokeys").font(.system(size: 21)).foregroundStyle(QinXuTheme.teal)
                    Text("中文练习谱").font(.system(size: 9))
                }.padding(geometry.size.width < 100 ? 10 : 14)
            }
            .foregroundStyle(QinXuTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(QinXuTheme.line, lineWidth: 1))
        }.accessibilityHidden(true)
    }
}

private struct ScoreLibraryCard: View {
    let score: PianoScore
    let imageData: Data?
    let isFavorite: Bool
    let isOriginal: Bool
    let compact: Bool
    let onOpen: () -> Void
    let onFavorite: () -> Void
    let onPractice: () -> Void
    let onCover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Button(action: onOpen) {
                    ScoreCoverView(score: score, imageData: imageData)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .frame(maxWidth: compact ? 92 : 140)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看曲谱：" + score.title)
                .accessibilityIdentifier("library.score." + score.id)
                HStack(spacing: 0) {
                    cardAction(symbol: isFavorite ? "bookmark.fill" : "bookmark", label: (isFavorite ? "取消收藏：" : "收藏：") + score.title,
                               identifier: "library.favorite." + score.id, selected: isFavorite, action: onFavorite)
                    cardAction(symbol: "play", label: "练习：" + score.title,
                               identifier: "library.practice." + score.id, selected: false, action: onPractice)
                }.padding(2)
            }
            .contextMenu {
                Button(action: onCover) { Label("更换封面", systemImage: "photo") }
                Button(action: onFavorite) { Label(isFavorite ? "取消收藏" : "收藏", systemImage: isFavorite ? "bookmark.slash" : "bookmark") }
            }
            Button(action: onOpen) {
                Text(score.title).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(QinXuTheme.ink).lineLimit(compact ? 1 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).accessibilityLabel(score.title)
            if !compact {
                Text(score.composer.isEmpty ? (isOriginal ? "原创样谱" : "导入曲谱") : score.composer)
                    .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted).lineLimit(1)
            }
            HStack(spacing: 5) {
                Image(systemName: isOriginal ? "music.note" : "doc").font(.system(size: 10))
                Text("\(score.measures.count) 小节")
                Spacer(minLength: 0)
            }.font(.system(size: 10)).foregroundStyle(QinXuTheme.muted)
        }
    }

    private func cardAction(symbol: String, label: String, identifier: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? QinXuTheme.accent : QinXuTheme.muted)
                .frame(width: 28, height: 28)
                .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 7))
                .frame(width: 40, height: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
        .accessibilityValue(selected ? "已收藏" : "")
        .accessibilityIdentifier(identifier)
    }
}
