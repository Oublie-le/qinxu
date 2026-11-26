import SwiftUI
import QinXuCore

struct LibraryCollectionView: View {
    @ObservedObject var model: PracticeViewModel
    let collection: LibraryCollection
    let compact: Bool
    let onSelect: (String) -> Void
    let onPractice: (String) -> Void
    var filterEntry: (LibraryEntryReference) -> Bool = { _ in true }
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var reading: ImportedReadingDocument?
    @State private var query = ""

    private var current: LibraryCollection {
        model.catalog.collections.first(where: { $0.id == collection.id }) ?? collection
    }
    private var isCustom: Bool { model.catalog.collections.contains { $0.id == collection.id } }
    private var entries: [LibraryEntryReference] {
        current.entries.filter(filterEntry).filter { query.isEmpty || title(for: $0).localizedStandardContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 12 : 18) {
                    HStack(spacing: 12) {
                        Image(systemName: current.kind.symbol).font(.system(size: 30)).foregroundStyle(QinXuTheme.teal)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(current.title).font(.system(size: compact ? 21 : 27, weight: .semibold))
                                .accessibilityIdentifier("collection.title")
                            Text("\(current.kind.title) · \(entries.count) / \(current.entries.count) 项")
                                .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
                            if !current.subtitle.isEmpty {
                                Text(current.subtitle).font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
                            }
                        }
                        Spacer()
                        if isCustom {
                            Button { editing = true } label: { Label("编辑", systemImage: "slider.horizontal.3") }
                                .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("collection.edit")
                        }
                    }
                    TextField("查找本组曲谱或资料", text: $query)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("collection.search")
                    if entries.isEmpty {
                        Text(query.isEmpty ? "还没有内容。点击编辑，选择要收进来的曲谱或阅读资料。" : "没有匹配的内容。")
                            .font(.system(size: 13)).foregroundStyle(QinXuTheme.muted).padding(.vertical, 20)
                    }
                    ForEach(entries) { entry in entryRow(entry) }
                }.padding(compact ? 16 : 24).frame(maxWidth: 900).frame(maxWidth: .infinity)
            }.background(QinXuTheme.background).accessibilityIdentifier("collection.scroll")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.accessibilityIdentifier("collection.close") } }
                .sheet(isPresented: $editing) { CollectionContentsEditor(model: model, collection: current, onDeleted: { dismiss() }) }
                .sheet(item: $reading) { document in
                    ImportedDocumentReaderView(model: model, document: document, compact: compact)
                }
        }.tint(QinXuTheme.accent).foregroundStyle(QinXuTheme.ink).frame(minWidth: 320, minHeight: 280)
    }

    @ViewBuilder private func entryRow(_ entry: LibraryEntryReference) -> some View {
        HStack(spacing: 12) {
            switch entry {
            case .score(let id):
                if let score = model.scores.first(where: { $0.id == id }) {
                    if let cover = model.scoreCoverData[id] {
                        ScoreCoverView(score: score, imageData: cover).frame(width: 38, height: 50)
                    } else {
                        Image(systemName: "music.note.list")
                            .foregroundStyle(QinXuTheme.teal)
                            .frame(width: 38, height: 50)
                            .background(QinXuTheme.sage, in: RoundedRectangle(cornerRadius: 7))
                            .accessibilityHidden(true)
                    }
                    Button { onSelect(id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(score.title).font(.system(size: 13, weight: .medium))
                            Text("\(score.composer) · \(score.measures.count) 小节")
                                .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("collection.score." + id)
                    Button { onPractice(id) } label: { Label("练习", systemImage: "play.fill") }
                        .buttonStyle(QuietButtonStyle(prominent: true)).accessibilityIdentifier("collection.practice." + id)
                } else { missingEntry }
            case .document(let id):
                if let document = model.documentLibrary.documents.first(where: { $0.id == id }) {
                    Image(systemName: "doc.richtext").font(.system(size: 25)).foregroundStyle(QinXuTheme.teal)
                    Button { reading = document } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(document.title).font(.system(size: 13, weight: .medium))
                            Text("\(document.pageCount) 页 · 阅读资料，不判音")
                                .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("collection.document." + id)
                    Image(systemName: "book").foregroundStyle(QinXuTheme.teal)
                } else { missingEntry }
            }
        }.padding(12).background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 12))
    }

    private var missingEntry: some View {
        Label("此内容当前不可用，可在编辑中移出分组。", systemImage: "doc.questionmark")
            .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
    }
    private func title(for entry: LibraryEntryReference) -> String {
        switch entry {
        case .score(let id): return model.scores.first(where: { $0.id == id })?.title ?? ""
        case .document(let id): return model.documentLibrary.documents.first(where: { $0.id == id })?.title ?? ""
        }
    }
}

private struct CollectionContentsEditor: View {
    @ObservedObject var model: PracticeViewModel
    let onDeleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LibraryCollection
    @State private var query = ""
    @State private var confirmingDelete = false

    init(model: PracticeViewModel, collection: LibraryCollection, onDeleted: @escaping () -> Void) {
        self.model = model; self.onDeleted = onDeleted; _draft = State(initialValue: collection)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("分组") {
                    TextField("名称", text: $draft.title)
                    Picker("类型", selection: $draft.kind) {
                        ForEach(LibraryCollectionKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section("选择内容") {
                    TextField("查找曲名或资料名", text: $query).accessibilityIdentifier("collection.contents.search")
                    ForEach(model.scores.filter { query.isEmpty || $0.title.localizedStandardContains(query) }) { score in
                        Toggle(score.title, isOn: membership(.score(score.id))).accessibilityIdentifier("collection.include.score." + score.id)
                    }
                    ForEach(model.documentLibrary.documents.filter { query.isEmpty || $0.title.localizedStandardContains(query) }) { document in
                        Toggle(isOn: membership(.document(document.id))) {
                            Label(document.title + " · 阅读资料", systemImage: "doc.richtext")
                        }.accessibilityIdentifier("collection.include.document." + document.id)
                    }
                }
                if let error = model.catalog.errorMessage { Text(error).foregroundStyle(QinXuTheme.wrong) }
                Section {
                    Button("删除这个分组", role: .destructive) { confirmingDelete = true }
                    Text("仅移除分组，曲谱和阅读资料仍保留。")
                        .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                }
            }.font(.system(size: 13)).navigationTitle("编辑分组")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                            if model.catalog.updateCollection(draft) { dismiss() }
                        }.disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.title.count > 80)
                            .accessibilityIdentifier("collection.contents.save")
                    }
                }
                .confirmationDialog("删除“\(draft.title)”？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("删除分组", role: .destructive) {
                        if model.catalog.deleteCollection(id: draft.id) { dismiss(); onDeleted() }
                    }
                }
        }.tint(QinXuTheme.accent).frame(minWidth: 320, minHeight: 280)
    }

    private func membership(_ entry: LibraryEntryReference) -> Binding<Bool> {
        Binding(get: { draft.entries.contains(entry) }, set: { included in
            if included { if !draft.entries.contains(entry) { draft.entries.append(entry) } }
            else { draft.entries.removeAll { $0 == entry } }
        })
    }
}
