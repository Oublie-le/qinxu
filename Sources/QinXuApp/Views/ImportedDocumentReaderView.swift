import SwiftUI
import PDFKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
struct ImportedDocumentReaderView: View {
    @ObservedObject var library: ImportedDocumentLibrary
    let document: ImportedReadingDocument
    let compact: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var displayedPDF: PDFDocument?
    @State private var pageIndex = 0
    @State private var pageInput = "1"
    @State private var fitsWidth = true
    @State private var fitRevision = 0
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 36, height: 36) }
                    .buttonStyle(.plain).accessibilityLabel("关闭阅读资料").accessibilityIdentifier("document.reader.close")
                VStack(alignment: .leading, spacing: 3) {
                    Text(document.title).font(.system(size: compact ? 16 : 20, weight: .semibold)).lineLimit(1)
                        .accessibilityIdentifier("document.reader.title")
                    Text("\(document.formatTitle) · 阅读资料，不自动判音")
                        .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                }
                Spacer(minLength: 4)
            }.padding(.horizontal, compact ? 12 : 20).padding(.vertical, 8)
            Divider()
            if let displayedPDF {
                BookPDFView(document: displayedPDF, pageIndex: document.kind == .pdf ? $pageIndex : .constant(0),
                            fitsWidth: fitsWidth, fitRevision: fitRevision)
                    .accessibilityIdentifier("document.reader.pages")
            } else {
                ContentUnavailableView("资料暂时无法打开", systemImage: "doc.questionmark",
                    description: Text(loadError ?? "正在读取本地文件…"))
                    .accessibilityIdentifier("document.reader.unavailable")
            }
            Divider()
            HStack(spacing: compact ? 8 : 14) {
                Button { pageIndex = max(0, pageIndex - 1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                    .disabled(pageIndex == 0).accessibilityLabel("上一页").accessibilityIdentifier("document.reader.previous")
                TextField("页码", text: $pageInput).textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
                    .frame(width: 48).onSubmit(jump).accessibilityIdentifier("document.reader.pageInput")
                Text("/ \(document.pageCount) 页").font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
                    .accessibilityIdentifier("document.reader.count")
                Button(action: jump) { Image(systemName: "arrow.turn.down.right").frame(width: 32, height: 36) }
                    .accessibilityLabel("前往页码").accessibilityIdentifier("document.reader.jump")
                Button { pageIndex = min(document.pageCount - 1, pageIndex + 1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                    .disabled(pageIndex == document.pageCount - 1).accessibilityLabel("下一页").accessibilityIdentifier("document.reader.next")
                Spacer(minLength: 4)
                Button { fitsWidth.toggle(); fitRevision += 1 } label: {
                    Label(fitsWidth ? "整页" : "适宽", systemImage: "arrow.left.and.right").font(.system(size: 12)).frame(minHeight: 36)
                }.accessibilityIdentifier("document.reader.fit")
            }.buttonStyle(.plain).padding(.horizontal, compact ? 12 : 20).padding(.vertical, 6)
        }
        .background(QinXuTheme.background).foregroundStyle(QinXuTheme.ink)
        .onAppear(perform: loadPage)
        .onChange(of: pageIndex) { _, value in
            pageInput = String(value + 1)
            if document.kind == .images { loadPage() }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 380)
        #endif
    }

    private func jump() {
        guard let page = Int(pageInput), (1...document.pageCount).contains(page) else {
            pageInput = String(pageIndex + 1); return
        }
        pageIndex = page - 1
    }

    private func loadPage() {
        do {
            let url = try library.fileURL(for: document, pageIndex: pageIndex)
            let pdf: PDFDocument
            if document.kind == .pdf {
                guard let loaded = PDFDocument(url: url), !loaded.isLocked,
                      loaded.pageCount == document.pageCount else { throw readerError }
                pdf = loaded
            } else {
                // Only one normalized image page is decoded at a time, including large textbooks.
                let data = try StructuredScoreImport.boundedData(from: url, limit: ImportedDocumentStore.maximumImageBytes)
                #if os(iOS)
                guard let image = UIImage(data: data), let page = PDFPage(image: image) else { throw readerError }
                #else
                guard let image = NSImage(data: data), let page = PDFPage(image: image) else { throw readerError }
                #endif
                pdf = PDFDocument(); pdf.insert(page, at: 0)
            }
            displayedPDF = pdf; loadError = nil; fitRevision += 1
        } catch { displayedPDF = nil; loadError = error.localizedDescription }
    }
    private var readerError: Error { CompressedMusicXML.ImportError.invalid("文件缺失或无法解码，请重新导入这份资料。") }
}
