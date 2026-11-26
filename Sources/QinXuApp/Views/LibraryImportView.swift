import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LibraryImportView: View {
    @ObservedObject var model: PracticeViewModel
    let onScoreImported: (String) -> Void
    let onDocumentImported: (ImportedReadingDocument) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .score
    @State private var choosingFiles = false
    @State private var sources: [URL] = []
    @State private var title = ""
    @State private var busy = false
    @State private var failure: String?

    private enum Kind { case score, pdf, images }
    private var contentTypes: [UTType] {
        switch kind {
        case .score: return [.xml, UTType(filenameExtension: "musicxml") ?? .xml, UTType(filenameExtension: "mxl") ?? .zip, .data]
        case .pdf: return [.pdf]
        case .images: return [.image]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("导入曲谱与资料", systemImage: "square.and.arrow.down")
                    .font(.system(size: 18, weight: .semibold)).accessibilityIdentifier("import.title")
                Spacer()
                Button("关闭") { dismiss() }.disabled(busy).accessibilityIdentifier("import.close")
            }.padding(16).background(QinXuTheme.paper)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    importChoice("可判音曲谱", detail: "MusicXML / XML / MXL · 导入后检查音高与时值", symbol: "music.note.list", kind: .score)
                    importChoice("PDF 乐谱", detail: "阅读、跟拍，也可在阅读页尝试转 MXL", symbol: "doc.richtext", kind: .pdf)
                    importChoice("图片教材", detail: "从“文件”选择谱页图片，可排序成册和转 MXL", symbol: "photo.on.rectangle.angled", kind: .images)
                    if !sources.isEmpty {
                        Divider()
                        TextField("资料名称", text: $title).textFieldStyle(.roundedBorder)
                            .disabled(busy)
                            .accessibilityIdentifier("import.document.title")
                        if kind == .images {
                            Text("页序 · 可用箭头调整；图片以最长边 3200 像素保存")
                                .font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
                            ForEach(Array(sources.enumerated()), id: \.offset) { index, url in
                                HStack(spacing: 10) {
                                    Text("\(index + 1)").monospacedDigit().frame(width: 28)
                                    Text(url.lastPathComponent).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    Button { sources.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up").frame(width: 36, height: 36) }
                                        .disabled(busy || index == 0).accessibilityLabel("第 \(index + 1) 页前移")
                                    Button { sources.swapAt(index, index + 1) } label: { Image(systemName: "arrow.down").frame(width: 36, height: 36) }
                                        .disabled(busy || index == sources.count - 1).accessibilityLabel("第 \(index + 1) 页后移")
                                }.font(.system(size: 12)).buttonStyle(.plain)
                            }
                        } else { Text(sources[0].lastPathComponent).font(.system(size: 12)).foregroundStyle(QinXuTheme.muted) }
                        Button(action: saveDocument) {
                            Label(busy ? "正在保存…" : "保存阅读资料", systemImage: "books.vertical")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(QuietButtonStyle(prominent: true))
                            .disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("import.document.save")
                    }
                    if busy { ProgressView("正在处理本地文件…") }
                    if sources.isEmpty { scoreFormatHelp }
                }.padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("import.scroll")
        }
        .background(QinXuTheme.background).foregroundStyle(QinXuTheme.ink).tint(QinXuTheme.accent)
        .interactiveDismissDisabled(busy)
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: contentTypes, allowsMultipleSelection: kind == .images) { result in
            switch result {
            case .success(let urls): selected(urls)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { failure = error.localizedDescription }
            }
        }
        .alert("无法导入", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("知道了", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 400)
        #endif
    }

    private var scoreFormatHelp: some View {
        DisclosureGroup("哪里找 MusicXML？") {
            VStack(alignment: .leading, spacing: 9) {
                Text("搜「曲名 + 钢琴 + MusicXML」，找 .musicxml 或 .mxl。已有 .mscz 时，用 MuseScore Studio 打开，选「文件 → 导出 → MusicXML」。")
                    .foregroundStyle(QinXuTheme.muted)
                Link("下载示例：欢乐颂（MXL）", destination: URL(string: "https://musetrainer.github.io/library/scores/Ode_to_Joy_Easy_variation.mxl")!)
                Link("MusicXML 曲谱目录", destination: URL(string: "https://www.musicxml.com/music-in-musicxml/")!)
                Text("手头有 PDF 或图片谱时，在阅读页点「转 MXL」，核对识别谱后可导出或导入练习。")
                    .foregroundStyle(QinXuTheme.muted)
            }
            .font(.system(size: 12))
            .padding(.top, 8)
        }
        .font(.system(size: 13, weight: .medium))
        .accessibilityIdentifier("import.musicXMLHelp")
    }

    private func importChoice(_ name: String, detail: String, symbol: String, kind selectedKind: Kind) -> some View {
        Button {
            kind = selectedKind; sources = []; title = ""; choosingFiles = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 21)).frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.system(size: 14, weight: .medium))
                    Text(detail).font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 11))
            }.padding(14).background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(busy)
            .accessibilityIdentifier(selectedKind == .score ? "import.score" : selectedKind == .pdf ? "import.pdf" : "import.images")
    }

    private func selected(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if kind == .score {
            let oldIDs = Set(model.scores.map(\.id))
            model.importScore(from: urls[0])
            if !oldIDs.contains(model.selectedScoreID) {
                onScoreImported(model.selectedScoreID); dismiss()
            } else { failure = model.errorMessage ?? "曲谱未能导入。"; model.errorMessage = nil }
            return
        }
        if kind == .images && urls.count > ImportedDocumentStore.maximumImagePages {
            failure = "一次最多选择 200 张图片，请分批导入。"; return
        }
        // Files providers do not guarantee selection order. Present a predictable
        // initial order, then let the user explicitly move pages before copying.
        sources = kind == .images ? urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } : [urls[0]]
        title = kind == .pdf || urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "图片教材"
    }

    private func saveDocument() {
        guard !busy, !sources.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let imported: ImportedReadingDocument
                if kind == .pdf { imported = try await model.documentLibrary.importPDF(from: sources[0], title: title) }
                else { imported = try await model.documentLibrary.importImages(from: sources, title: title) }
                onDocumentImported(imported); dismiss()
            } catch { failure = error.localizedDescription }
        }
    }
}
