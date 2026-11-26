import SwiftUI

struct LibraryOrganizationView: View {
    @ObservedObject var catalog: LibraryCatalogController
    let entry: LibraryEntryReference
    let title: String
    var allowsAuthorEditing = true
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>
    @State private var metadata: ScoreCatalogMetadata
    @State private var creating = false

    init(catalog: LibraryCatalogController, entry: LibraryEntryReference, title: String,
         fallbackMetadata: ScoreCatalogMetadata = .init(), allowsAuthorEditing: Bool = true) {
        self.catalog = catalog; self.entry = entry; self.title = title
        self.allowsAuthorEditing = allowsAuthorEditing
        _selected = State(initialValue: catalog.collectionIDs(containing: entry))
        _metadata = State(initialValue: catalog.metadata(for: entry, fallback: fallbackMetadata))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(title) {
                    if allowsAuthorEditing {
                        TextField("作者（留空使用曲谱原标注）", text: Binding(get: { metadata.authorOverride ?? "" }, set: { metadata.authorOverride = $0 }))
                            .accessibilityIdentifier("catalog.author")
                    }
                    Picker("难度", selection: $metadata.difficulty) {
                        ForEach(CatalogDifficulty.allCases, id: \.self) { value in
                            Text(value.title).tag(value)
                        }
                    }.accessibilityIdentifier("catalog.difficulty")
                    TextField("风格，如流行、古典", text: $metadata.genre)
                        .accessibilityIdentifier("catalog.genre")
                }
                Section("加入教材或曲集") {
                    if catalog.collections.isEmpty {
                        Text("先新建一个曲集，再把曲谱收在一起。")
                            .foregroundStyle(QinXuTheme.muted)
                    }
                    ForEach(catalog.collections) { collection in
                        Toggle(isOn: Binding(get: { selected.contains(collection.id) }, set: { included in
                            if included { selected.insert(collection.id) } else { selected.remove(collection.id) }
                        })) {
                            Label(collection.title, systemImage: collection.kind.symbol)
                        }.accessibilityIdentifier("catalog.membership." + collection.id)
                    }
                    Button { creating = true } label: { Label("新建教材或曲集", systemImage: "folder.badge.plus") }
                        .accessibilityIdentifier("catalog.newCollection")
                }
                if let error = catalog.errorMessage {
                    Text(error).foregroundStyle(QinXuTheme.wrong).accessibilityIdentifier("catalog.error")
                }
            }
            .font(.system(size: 13)).accessibilityIdentifier("catalog.organization.form")
            .navigationTitle("分类与分组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        metadata.genre = metadata.genre.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let author = metadata.authorOverride?.trimmingCharacters(in: .whitespacesAndNewlines) {
                            metadata.authorOverride = author.isEmpty ? nil : author
                        }
                        if catalog.organize(entry, collectionIDs: selected, metadata: metadata) { dismiss() }
                    }.disabled(metadata.genre.count > 40 || (metadata.authorOverride?.count ?? 0) > 120).accessibilityIdentifier("catalog.organization.save")
                }
            }
            .sheet(isPresented: $creating) {
                NewLibraryCollectionView(catalog: catalog) { selected.insert($0.id) }
            }
        }.tint(QinXuTheme.accent).frame(minWidth: 320, minHeight: 280)
    }
}

struct NewLibraryCollectionView: View {
    @ObservedObject var catalog: LibraryCatalogController
    var onCreated: (LibraryCollection) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind: LibraryCollectionKind = .collection

    var body: some View {
        NavigationStack {
            Form {
                Section("名称与类型") {
                    TextField("例如：本周练习", text: $title).accessibilityIdentifier("catalog.collection.title")
                    Picker("类型", selection: $kind) {
                        ForEach(LibraryCollectionKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("catalog.collection.kind")
                }
                Text("从曲谱或阅读资料的“分类与分组”菜单加入内容。")
                    .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
                if let error = catalog.errorMessage { Text(error).foregroundStyle(QinXuTheme.wrong) }
            }.navigationTitle("新建分组")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("创建") {
                            if let collection = catalog.createCollection(title: title, kind: kind) {
                                onCreated(collection); dismiss()
                            }
                        }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 80)
                            .accessibilityIdentifier("catalog.collection.create")
                    }
                }
        }.tint(QinXuTheme.accent).frame(minWidth: 320, minHeight: 260)
    }
}
