import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import QinXuCore

@MainActor
struct PDFScoreConversionView: View {
    @ObservedObject var model: PracticeViewModel
    let document: ImportedReadingDocument
    let compact: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var firstPage: Int
    @State private var lastPage: Int
    @State private var previewPage: Int
    @State private var originalPDF: PDFDocument?
    @State private var originalImage: Image?
    @State private var originalLoadError: String?
    @State private var showOriginal = false
    @State private var result: PDFScoreConversionResult?
    @State private var conversionTask: Task<Void, Never>?
    @State private var attemptID: UUID?
    @State private var isConverting = false
    @State private var message: String?
    @State private var imported = false
    @State private var exporting = false
    @State private var exported = false

    init(model: PracticeViewModel, document: ImportedReadingDocument, initialPage: Int, compact: Bool) {
        self.model = model
        self.document = document
        self.compact = compact
        let page = min(max(initialPage, 1), document.pageCount)
        _firstPage = State(initialValue: page)
        _lastPage = State(initialValue: page)
        _previewPage = State(initialValue: page)
    }

    private var pageIssue: String? {
        if lastPage < firstPage { return "结束页不能早于起始页。" }
        if lastPage - firstPage + 1 > PDFScoreConverter.maximumPages {
            return "每次最多转换 \(PDFScoreConverter.maximumPages) 页，请缩小范围。"
        }
        return nil
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: compact ? 12 : 18) {
                        pageSelection
                        if isConverting { conversionProgress }
                        if let message = message ?? originalLoadError {
                            Label(message, systemImage: "exclamationmark.circle")
                                .font(.system(size: 12)).foregroundStyle(QinXuTheme.wrong)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("pdfConversion.message")
                        }
                        if let result {
                            review(result, wide: geometry.size.width >= 850)
                        } else if !isConverting {
                            originalPreview
                        }
                    }
                    .padding(compact ? 12 : 20).frame(maxWidth: 1180).frame(maxWidth: .infinity)
                }.accessibilityIdentifier("pdfConversion.scroll")
                if result != nil { saveActions }
            }
        }
        .background(QinXuTheme.background).foregroundStyle(QinXuTheme.ink).tint(QinXuTheme.accent)
        .onAppear(perform: refreshOriginalImage)
        .onDisappear(perform: cancelConversion)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { cancelConversion() }
        }
        .onChange(of: firstPage) { _, value in
            clearResult()
            previewPage = value
        }
        .onChange(of: lastPage) { _, _ in clearResult() }
        .onChange(of: previewPage) { _, _ in refreshOriginalImage() }
        .fileExporter(isPresented: $exporting,
                      document: PDFScoreArchiveDocument(data: result?.archive ?? Data()),
                      contentType: PDFScoreArchiveDocument.contentType,
                      defaultFilename: document.title + "-第\(firstPage)-\(lastPage)页") { outcome in
            switch outcome {
            case .success: exported = true
            case .failure(let error): message = "导出失败：\(error.localizedDescription)"
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 340)
        #endif
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(document.kind == .pdf ? "PDF 转 MXL（实验）" : "图片转 MXL（实验）", systemImage: "doc.text.viewfinder")
                .font(.system(size: compact ? 16 : 20, weight: .semibold))
                .accessibilityIdentifier("pdfConversion.title")
            Spacer(minLength: 4)
            Button("关闭") { cancelConversion(); dismiss() }
                .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("pdfConversion.close")
        }
        .padding(.horizontal, compact ? 12 : 20).padding(.vertical, 9)
        .background(QinXuTheme.paper).overlay(alignment: .bottom) { Divider() }
    }

    private var pageSelection: some View {
        PracticeCard(padding: compact ? 12 : 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(document.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                HStack(spacing: compact ? 14 : 24) {
                    Stepper(value: $firstPage, in: 1...document.pageCount) {
                        Text("起始 \(firstPage) 页").monospacedDigit()
                    }
                    .accessibilityLabel("起始页")
                    .accessibilityValue(String(firstPage))
                    .accessibilityIdentifier("pdfConversion.firstPage")
                    Stepper(value: $lastPage, in: 1...document.pageCount) {
                        Text("结束 \(lastPage) 页").monospacedDigit()
                    }
                    .accessibilityLabel("结束页")
                    .accessibilityValue(String(lastPage))
                    .accessibilityIdentifier("pdfConversion.lastPage")
                }.font(.system(size: 12)).disabled(isConverting)
                HStack(spacing: 12) {
                    Text(pageIssue ?? "共 \(document.pageCount) 页，每次最多 \(PDFScoreConverter.maximumPages) 页。")
                        .font(.system(size: 11)).foregroundStyle(pageIssue == nil ? QinXuTheme.muted : QinXuTheme.wrong)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pdfConversion.pageRange")
                    Spacer(minLength: 0)
                    Button(action: startConversion) {
                        Label(result == nil ? "开始转换" : "重新转换", systemImage: "viewfinder")
                    }
                    .buttonStyle(QuietButtonStyle(prominent: true))
                    .disabled(isConverting || pageIssue != nil || originalImage == nil)
                    .accessibilityIdentifier("pdfConversion.start")
                }
                Text("在本机识别。转换可能遗漏或认错音符，导入判音前请对照原谱检查。")
                    .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var conversionProgress: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("正在转换第 \(firstPage)–\(lastPage) 页…")
                .font(.system(size: 13)).accessibilityIdentifier("pdfConversion.progress")
            Spacer(minLength: 4)
            Button("取消转换", action: cancelConversion).buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("pdfConversion.cancel")
        }.padding(.vertical, 6)
    }

    private func review(_ result: PDFScoreConversionResult, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("识别草稿 · 请核对音高、时值、升降号与小节", systemImage: "checkmark.viewfinder")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(QinXuTheme.teal)
                .accessibilityIdentifier("pdfConversion.review")
            Text("\(result.score.measures.count) 小节 · \(result.score.notes.count) 个音符")
                .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                .accessibilityIdentifier("pdfConversion.scoreSummary")
            Text("反复、跳转、连线、延长记号和八度线可能漏识别。请逐小节与原谱核对。")
                .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !result.diagnostics.isEmpty {
                DisclosureGroup("转换说明（\(result.diagnostics.count) 项）") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(result.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                            Text(diagnostic).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.top, 6)
                }.font(.system(size: 12)).accessibilityIdentifier("pdfConversion.diagnostics")
            }
            if wide {
                HStack(alignment: .top, spacing: 16) {
                    originalPreview.frame(maxWidth: .infinity)
                    scorePreview(result.score).frame(maxWidth: .infinity)
                }
            } else {
                Picker("核对视图", selection: $showOriginal) {
                    Text("识别谱").tag(false)
                    Text("原谱").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("pdfConversion.previewMode")
                if showOriginal { originalPreview } else { scorePreview(result.score) }
            }
        }
    }

    private var originalPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("原谱 · 第 \(previewPage) 页").font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                if result != nil && lastPage > firstPage {
                    Button { previewPage = max(firstPage, previewPage - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(previewPage <= firstPage).accessibilityLabel("上一张原谱")
                        .accessibilityIdentifier("pdfConversion.original.previous")
                    Button { previewPage = min(lastPage, previewPage + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(previewPage >= lastPage).accessibilityLabel("下一张原谱")
                        .accessibilityIdentifier("pdfConversion.original.next")
                }
            }.buttonStyle(QuietButtonStyle())
            if let originalImage {
                originalImage.resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(maxHeight: compact ? 320 : 520)
                    .background(Color.white)
                    .accessibilityLabel("原谱第 \(previewPage) 页")
                    .accessibilityIdentifier("pdfConversion.original")
            }
        }
    }

    private func scorePreview(_ score: PianoScore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("识别谱 · 横向滑动查看全部小节").font(.system(size: 12, weight: .medium))
            PracticeScoreView(score: score, hand: .both, currentBeat: 0,
                              expectedNotes: [], verdicts: [:], active: false, compact: compact)
                .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("pdfConversion.score")
        }
    }

    private var saveActions: some View {
        HStack(spacing: 10) {
            if imported || exported {
                Label(imported ? "已加入曲库" : "已导出", systemImage: "checkmark.circle")
                    .font(.system(size: 12)).foregroundStyle(QinXuTheme.teal)
                    .accessibilityIdentifier("pdfConversion.saved")
            } else {
                Text("核对后保存练习谱").font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            }
            Spacer(minLength: 0)
            Button("已核对，导出 MXL") { exporting = true }
                .buttonStyle(QuietButtonStyle()).accessibilityIdentifier("pdfConversion.export")
            Button(imported ? "已导入练习" : "已核对，导入练习", action: importResult)
                .buttonStyle(QuietButtonStyle(prominent: true)).disabled(imported)
                .accessibilityIdentifier("pdfConversion.import")
        }
        .padding(.horizontal, compact ? 12 : 20).padding(.vertical, 9)
        .background(QinXuTheme.paper).overlay(alignment: .top) { Divider() }
    }

    private func refreshOriginalImage() {
        originalImage = nil
        originalLoadError = nil
        do {
            switch document.kind {
            case .images:
                let thumbnail = try model.documentLibrary.imagePreview(for: document, pageIndex: previewPage - 1)
                originalImage = Image(thumbnail, scale: 1, label: Text("原谱"))
            case .pdf:
                if originalPDF == nil {
                    let url = try model.documentLibrary.fileURL(for: document)
                    guard let pdf = PDFDocument(url: url), !pdf.isLocked, pdf.pageCount == document.pageCount else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    originalPDF = pdf
                }
                guard let page = originalPDF?.page(at: previewPage - 1) else { throw CocoaError(.fileReadCorruptFile) }
                let thumbnail = page.thumbnail(of: CGSize(width: 900, height: 1200), for: .cropBox)
                #if os(iOS)
                originalImage = Image(uiImage: thumbnail)
                #else
                originalImage = Image(nsImage: thumbnail)
                #endif
            }
        } catch { originalLoadError = "无法打开原谱第 \(previewPage) 页。\(error.localizedDescription)" }
    }

    private func startConversion() {
        guard !isConverting, pageIssue == nil, originalImage != nil else { return }
        clearResult()
        let pages = firstPage...lastPage
        let id = UUID()
        attemptID = id
        isConverting = true
        conversionTask = Task {
            do {
                let converted = try await model.documentLibrary.convertScore(for: document, pages: pages)
                try Task.checkCancellation()
                guard attemptID == id else { return }
                result = converted
                previewPage = pages.lowerBound
            } catch is CancellationError {
                // Cancellation is an action, not a failed-score warning.
            } catch {
                if attemptID == id { message = error.localizedDescription }
            }
            if attemptID == id { isConverting = false; attemptID = nil; conversionTask = nil }
        }
    }

    private func cancelConversion() {
        conversionTask?.cancel()
        conversionTask = nil
        attemptID = nil
        isConverting = false
    }

    private func clearResult() {
        result = nil
        imported = false
        exported = false
        message = nil
        showOriginal = false
    }

    private func importResult() {
        guard let result, !imported else { return }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("qinxu-converted-\(UUID().uuidString).mxl")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try result.archive.write(to: file, options: .atomic)
            let existing = Set(model.scores.map(\.id))
            model.importScore(from: file)
            if model.scores.contains(where: { !existing.contains($0.id) }) {
                imported = true
                message = nil
            } else { message = model.errorMessage ?? "练习谱未能保存，请重试。" }
        } catch { message = "练习谱未能保存：\(error.localizedDescription)" }
    }
}

struct PDFScoreArchiveDocument: FileDocument {
    static let contentType = UTType(importedAs: "org.musicxml.mxl", conformingTo: .zip)
    static var readableContentTypes: [UTType] { [contentType] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
