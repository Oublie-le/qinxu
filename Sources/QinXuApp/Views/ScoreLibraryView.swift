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
    @State private var readingDocument: ImportedReadingDocument?
    @State private var selectedCollection: LibraryCollection?
    @State private var organizing: LibraryEntryReference?
    @State private var creatingCollection = false
    @State private var author: String?
    @State private var difficulty: CatalogDifficulty?
    @State private var genre: String?
    @State private var source: CatalogSource = .all

    private var demoIDs: Set<String> { Set(DemoScores.all.map(\.id)) }
    private var text: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var allCollections: [LibraryCollection] { BundledCollections.collections + model.catalog.collections }
    private var groupedEntries: Set<LibraryEntryReference> { Set(allCollections.flatMap(\.entries)) }
    private var refinementCount: Int { [author != nil, difficulty != nil, genre != nil, source != .all].filter { $0 }.count }
    private var allEntries: [LibraryEntryReference] { model.scores.map { .score($0.id) } + model.documentLibrary.documents.map { .document($0.id) } }
    private var authors: [String] { Set(allEntries.map(authorName).filter { !$0.isEmpty }).sorted() }
    private var genres: [String] { Set(allEntries.map { metadata($0).genre }.filter { !$0.isEmpty }).sorted() }

    private var matchingScores: [PianoScore] {
        guard filter == .all || filter == .singles else { return [] }
        return model.scores.filter { score in
            if favoritesOnly && !model.favoriteScoreIDs.contains(score.id) { return false }
            if !favoritesOnly && text.isEmpty {
                if BundledPracticeLibrary.ids.contains(score.id) || groupedEntries.contains(.score(score.id)) { return false }
            }
            return matches(.score(score.id))
        }
    }

    private var matchingBooks: [BundledBook] {
        guard !favoritesOnly, filter == .all || filter == .books else { return [] }
        return BundledBook.all.filter { book in
            let titleMatches = text.isEmpty || book.title.localizedStandardContains(text) || book.composer.localizedStandardContains(text)
            return BundledPracticeLibrary.beyer.scores.contains { matches(.score($0.id), ignoringQuery: titleMatches) }
        }
    }

    private var matchingCollections: [LibraryCollection] {
        guard !favoritesOnly, filter != .singles else { return [] }
        return allCollections.filter { collection in
            if filter == .books && collection.kind != .book { return false }
            if filter == .collections && collection.kind != .collection { return false }
            let titleMatches = text.isEmpty || collection.title.localizedStandardContains(text) || collection.subtitle.localizedStandardContains(text)
            if collection.entries.isEmpty { return titleMatches && refinementCount == 0 }
            return collection.entries.contains { matches($0, ignoringQuery: titleMatches) }
        }
    }

    private var matchingDocuments: [ImportedReadingDocument] {
        guard !favoritesOnly, filter == .all || filter == .books else { return [] }
        return model.documentLibrary.documents.filter {
            (text.isEmpty ? !groupedEntries.contains(.document($0.id)) : true) && matches(.document($0.id))
        }
    }

    private func metadata(_ entry: LibraryEntryReference) -> ScoreCatalogMetadata {
        let fallback: ScoreCatalogMetadata
        if case .score(let id) = entry { fallback = BundledCollections.metadata[id] ?? .init() }
        else { fallback = .init() }
        return model.catalog.metadata(for: entry, fallback: fallback)
    }
    private func authorName(_ entry: LibraryEntryReference) -> String {
        if let override = metadata(entry).authorOverride, !override.isEmpty { return override }
        if case .score(let id) = entry { return model.scores.first(where: { $0.id == id })?.composer ?? "" }
        return ""
    }
    private func entryTitle(_ entry: LibraryEntryReference) -> String {
        switch entry {
        case .score(let id): return model.scores.first(where: { $0.id == id })?.title ?? ""
        case .document(let id): return model.documentLibrary.documents.first(where: { $0.id == id })?.title ?? ""
        }
    }
    private func isImported(_ entry: LibraryEntryReference) -> Bool {
        switch entry {
        case .score(let id): return !BundledPracticeLibrary.allBundledIDs.contains(id)
        case .document: return true
        }
    }
    private func matches(_ entry: LibraryEntryReference, ignoringQuery: Bool = false) -> Bool {
        let tags = metadata(entry)
        if let difficulty, tags.difficulty != difficulty { return false }
        if let genre, tags.genre != genre { return false }
        if let author, authorName(entry) != author { return false }
        if source == .imported && !isImported(entry) { return false }
        if source == .bundled && isImported(entry) { return false }
        return ignoringQuery || text.isEmpty || entryTitle(entry).localizedStandardContains(text) || authorName(entry).localizedStandardContains(text)
    }

    var body: some View {
        GeometryReader { geometry in
            let count = max(1, min(6, Int((geometry.size.width + 12) / (compact ? 108 : 130))))
            VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                header
                filters
                if !favoritesOnly && (filter == .all || filter == .singles) { currentScoreStrip }
                results(columns: count)
            }
        }
        .foregroundStyle(QinXuTheme.ink)
        .onChange(of: favoritesOnly) { _, _ in filter = .all }
        .sheet(item: $readingBook) { book in
            let titleMatches = text.isEmpty || book.title.localizedStandardContains(text) || book.composer.localizedStandardContains(text)
            BookPracticeView(book: book, compact: compact,
                             onSelect: { id in readingBook = nil; onSelect(id) },
                             onPractice: { id in readingBook = nil; onPractice(id) },
                             filterScore: { matches(.score($0.id), ignoringQuery: titleMatches) })
        }
        .sheet(item: $readingDocument) { document in
            ImportedDocumentReaderView(library: model.documentLibrary, document: document, compact: compact)
        }
        .sheet(item: $selectedCollection) { collection in
            let titleMatches = text.isEmpty || collection.title.localizedStandardContains(text) || collection.subtitle.localizedStandardContains(text)
            LibraryCollectionView(model: model, collection: collection, compact: compact,
                onSelect: { selectedCollection = nil; onSelect($0) },
                onPractice: { selectedCollection = nil; onPractice($0) },
                filterEntry: { matches($0, ignoringQuery: titleMatches) })
        }
        .sheet(item: $organizing) { entry in
            LibraryOrganizationView(catalog: model.catalog, entry: entry, title: entryTitle(entry),
                fallbackMetadata: metadata(entry), allowsAuthorEditing: isImported(entry))
        }
        .sheet(isPresented: $creatingCollection) {
            NewLibraryCollectionView(catalog: model.catalog)
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
            Menu {
                Button { creatingCollection = true } label: { Label("新建教材或曲集", systemImage: "folder.badge.plus") }
                    .accessibilityIdentifier("library.collection.new")
                Button { organizing = .score(model.selectedScoreID) } label: { Label("整理当前曲谱", systemImage: "tag") }
                Button { onCover(model.selectedScoreID) } label: { Label("管理曲谱封面", systemImage: "photo.badge.plus") }
                    .accessibilityIdentifier("library.cover")
            } label: { Label("整理", systemImage: "folder.badge.plus") }
                .menuStyle(.borderlessButton).fixedSize().font(.system(size: 12)).padding(10)
                .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(QinXuTheme.line, lineWidth: 1))
                .accessibilityIdentifier("library.organize")
            Button(action: onImport) { Label("导入", systemImage: "plus") }
                .buttonStyle(QuietButtonStyle(prominent: true))
                .accessibilityIdentifier("library.import")
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var filters: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) { filterButtons }
            }
            refinementMenu
        }
    }

    @ViewBuilder private var filterButtons: some View {
        ForEach(LibraryFilter.allCases.filter { !favoritesOnly || $0 == .all }) { item in
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

    private var refinementMenu: some View {
        Menu {
            Menu(author.map { "作者：" + ($0.isEmpty ? "未标注" : $0) } ?? "作者") {
                Button("全部作者") { author = nil }
                Button("未标注作者") { author = "" }
                ForEach(authors, id: \.self) { value in Button(value) { author = value } }
            }
            Menu(difficulty.map { "难度：" + $0.title } ?? "难度") {
                Button("全部难度") { difficulty = nil }
                ForEach(CatalogDifficulty.allCases, id: \.self) { value in
                    Button(value.title) { difficulty = value }.accessibilityIdentifier("library.difficulty." + value.rawValue)
                }
            }
            Menu(genre.map { "风格：" + $0 } ?? "风格") {
                Button("全部风格") { genre = nil }
                ForEach(genres, id: \.self) { value in Button(value) { genre = value } }
                Button("未标注风格") { genre = "" }
            }
            Menu("来源：" + source.title) {
                ForEach(CatalogSource.allCases, id: \.self) { value in Button(value.title) { source = value } }
            }
            if refinementCount > 0 {
                Divider()
                Button("清除筛选") { author = nil; difficulty = nil; genre = nil; source = .all }
                    .accessibilityIdentifier("library.filters.clear")
            }
        } label: {
            Label(refinementCount == 0 ? "筛选" : "筛选 \(refinementCount)", systemImage: "line.3.horizontal.decrease")
                .font(.system(size: 12)).padding(.horizontal, 11).frame(height: compact ? 32 : 36)
        }.menuStyle(.borderlessButton).fixedSize()
            .foregroundStyle(refinementCount > 0 ? QinXuTheme.accent : QinXuTheme.ink)
            .background(refinementCount > 0 ? QinXuTheme.softAccent : QinXuTheme.paper, in: Capsule())
            .accessibilityIdentifier("library.filters")
    }

    private var currentScoreStrip: some View {
        let progress = model.progress(for: model.selectedScoreID)
        let resumable = progress.map { !$0.isCompleted } ?? false
        return HStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 15)).foregroundStyle(QinXuTheme.teal)
                .frame(width: 30, height: 30)
                .background(QinXuTheme.sage, in: RoundedRectangle(cornerRadius: 8))
            Text("当前曲谱").font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            Text(model.selectedScore.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            if let progress {
                Text(progress.isCompleted ? "\(progress.hand.title)已到末尾" : "第 \(progress.measure) 小节")
                    .font(.system(size: 11)).foregroundStyle(QinXuTheme.teal).lineLimit(1)
                    .accessibilityIdentifier("library.progress")
            } else if !compact {
                Text("\(model.selectedScore.measures.count) 小节 · 原谱 ♩\(Int(model.selectedScore.tempoBPM))")
                    .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                if resumable { model.resume(scoreID: model.selectedScoreID) }
                onPractice(model.selectedScoreID)
            } label: {
                Label(resumable ? "继续" : "练习", systemImage: "play.fill").font(.system(size: 12, weight: .medium))
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
                    Label(filter == .all ? "教材 · 曲集 · 单曲" : filter.title, systemImage: filter.symbol)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(matchingScores.count + matchingBooks.count + matchingCollections.count + matchingDocuments.count) 项")
                        .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                        .accessibilityIdentifier("library.results.count")
                }
                if matchingScores.isEmpty && matchingBooks.isEmpty && matchingCollections.isEmpty && matchingDocuments.isEmpty {
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
                                             onCover: { onCover(score.id) },
                                             onOrganize: { organizing = .score(score.id) })
                        }
                        ForEach(matchingCollections) { collection in
                            LibraryCollectionCard(collection: collection, compact: compact) { selectedCollection = collection }
                        }
                        ForEach(matchingDocuments) { document in
                            ImportedDocumentCard(document: document, compact: compact,
                                onOpen: { readingDocument = document }, onOrganize: { organizing = .document(document.id) })
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
            Text(favoritesOnly ? "在曲谱卡片上点收藏，即可加入谱架。" : "更换筛选条件，或导入曲谱与阅读资料。")
                .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, compact ? 20 : 50)
        .accessibilityIdentifier("library.empty")
    }
}

private enum LibraryFilter: String, Identifiable, CaseIterable {
    case all, books, collections, singles
    var id: String { rawValue }
    var title: String {
        switch self { case .all: return "全部"; case .books: return "教材"; case .collections: return "曲集"; case .singles: return "单曲" }
    }
    var symbol: String {
        switch self { case .all: return "square.grid.2x2"; case .books: return "books.vertical"; case .collections: return "rectangle.stack"; case .singles: return "music.note" }
    }
}

private enum CatalogSource: String, CaseIterable {
    case all, bundled, imported
    var title: String { self == .all ? "全部" : self == .bundled ? "内置" : "已导入" }
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
    let onOrganize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Button(action: onOpen) {
                    ScoreCoverView(score: score, imageData: imageData)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .frame(maxWidth: compact ? 92 : 140)
                        .contentShape(Rectangle())
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
                Button(action: onOrganize) { Label("分类与分组", systemImage: "tag") }
                    .accessibilityIdentifier("library.organize." + score.id)
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

private struct LibraryCollectionCard: View {
    let collection: LibraryCollection
    let compact: Bool
    let onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                LibraryFolderCover(title: collection.title, subtitle: collection.kind.title,
                                   symbol: collection.kind.symbol, compact: compact)
                Text(collection.title).font(.system(size: 12, weight: .medium)).lineLimit(compact ? 1 : 2)
                Label("\(collection.entries.count) 项 · \(collection.kind.title)", systemImage: collection.kind.symbol)
                    .font(.system(size: 10)).foregroundStyle(QinXuTheme.muted).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("打开\(collection.kind.title)：\(collection.title)，\(collection.entries.count) 项")
            .accessibilityIdentifier("library.collection." + collection.id)
    }
}

private struct ImportedDocumentCard: View {
    let document: ImportedReadingDocument
    let compact: Bool
    let onOpen: () -> Void
    let onOrganize: () -> Void
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                LibraryFolderCover(title: document.title, subtitle: document.formatTitle,
                                   symbol: document.kind == .pdf ? "doc.richtext" : "photo.stack", compact: compact)
                Text(document.title).font(.system(size: 12, weight: .medium)).lineLimit(compact ? 1 : 2)
                Text("\(document.pageCount) 页 · 阅读，不判音")
                    .font(.system(size: 10)).foregroundStyle(QinXuTheme.muted).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("阅读资料：\(document.title)，\(document.pageCount) 页，不判音")
            .accessibilityIdentifier("library.document." + document.id)
            .contextMenu {
                Button(action: onOrganize) { Label("分类与分组", systemImage: "tag") }
                    .accessibilityIdentifier("library.organize.document." + document.id)
            }
    }
}

private struct LibraryFolderCover: View {
    let title: String
    let subtitle: String
    let symbol: String
    let compact: Bool
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: symbol).font(.system(size: compact ? 18 : 25))
                Text(title).font(.system(size: compact ? 15 : 19, weight: .medium, design: .serif)).lineLimit(3)
                Spacer(minLength: 4)
                Text(subtitle).font(.system(size: 10))
            }
            .padding(compact ? 10 : 14)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .foregroundStyle(QinXuTheme.teal)
            .background(QinXuTheme.sage, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(QinXuTheme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit).frame(maxWidth: compact ? 92 : 140)
        .accessibilityHidden(true)
    }
}
