import SwiftUI
import PDFKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct BookReaderView: View {
    let book: BundledBook
    let compact: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var document: PDFDocument?
    @State private var pageIndex = 0
    @State private var pageInput = "1"
    @State private var fitsWidth = true
    @State private var fitRevision = 0

    init(book: BundledBook, compact: Bool) {
        self.book = book
        self.compact = compact
        _document = State(initialValue: book.loadDocument())
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, compact ? 12 : 20).padding(.vertical, compact ? 8 : 14)
            Divider().overlay(QinXuTheme.line)
            if let document {
                BookPDFView(document: document, pageIndex: $pageIndex,
                            fitsWidth: fitsWidth, fitRevision: fitRevision)
                    .accessibilityIdentifier("book.pages")
                Divider().overlay(QinXuTheme.line)
                controls.padding(.horizontal, compact ? 12 : 20).padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.questionmark").font(.system(size: 30))
                    Text("教材文件无法打开").font(.headline)
                    Text("请重新安装包含完整教材资源的版本。")
                        .font(.system(size: 13)).foregroundStyle(QinXuTheme.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("book.unavailable")
            }
        }
        .foregroundStyle(QinXuTheme.ink).background(QinXuTheme.background)
        .onChange(of: pageIndex) { _, value in pageInput = String(value + 1) }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 380)
        #endif
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").frame(width: 36, height: 36)
            }.buttonStyle(.plain).accessibilityLabel("关闭教材")
                .accessibilityIdentifier("book.close")
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title + " · 公版").font(.system(size: compact ? 16 : 20, weight: .semibold))
                    .accessibilityIdentifier("book.title")
                Text("原版扫描谱，暂不自动判音").font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
            }
            Spacer(minLength: 8)
            Menu {
                Text(book.composer)
                Text(book.edition)
                Text("\(book.pageCount) 页 · 德文、英文、法文旧版")
                Text("原版扫描页尚未译成中文")
                Text("公版原谱，不是上海音乐出版社版本")
                Link("查看来源与公版说明", destination: book.sourceURL)
            } label: {
                Image(systemName: "info.circle").frame(width: 36, height: 36)
            }.accessibilityLabel("教材版本与来源").accessibilityIdentifier("book.source")
        }
    }

    private var controls: some View {
        HStack(spacing: compact ? 8 : 14) {
            Button { pageIndex = max(0, pageIndex - 1) } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }.disabled(pageIndex == 0).accessibilityLabel("上一页")
                .accessibilityIdentifier("book.previous")
            HStack(spacing: 5) {
                TextField("页码", text: $pageInput)
                    .multilineTextAlignment(.center).textFieldStyle(.plain)
                    .frame(width: 42, height: 34)
                    .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(QinXuTheme.line))
                    .onSubmit(jumpToPage)
                    .accessibilityLabel("跳转页码").accessibilityIdentifier("book.pageInput")
                Text("/ \(book.pageCount) 页").font(.system(size: 12)).foregroundStyle(QinXuTheme.muted)
                    .accessibilityIdentifier("book.pageCount")
                Button(action: jumpToPage) { Image(systemName: "arrow.turn.down.right").frame(width: 32, height: 36) }
                    .disabled(Int(pageInput).map { !(1...book.pageCount).contains($0) } ?? true)
                    .accessibilityLabel("前往页码").accessibilityIdentifier("book.jump")
            }
            Button { pageIndex = min(book.pageCount - 1, pageIndex + 1) } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }.disabled(pageIndex == book.pageCount - 1).accessibilityLabel("下一页")
                .accessibilityIdentifier("book.next")
            Spacer(minLength: 8)
            Button {
                fitsWidth.toggle()
                fitRevision += 1
            } label: {
                Label(fitsWidth ? "整页" : "适宽", systemImage: fitsWidth ? "arrow.down.right.and.arrow.up.left" : "arrow.left.and.right")
                    .font(.system(size: 12)).frame(minHeight: 36)
            }.accessibilityIdentifier("book.fit")
        }
        .buttonStyle(.plain)
    }

    private func jumpToPage() {
        guard let page = Int(pageInput), (1...book.pageCount).contains(page) else {
            pageInput = String(pageIndex + 1)
            return
        }
        pageIndex = page - 1
    }
}

struct BookPDFView {
    let document: PDFDocument
    @Binding var pageIndex: Int
    let fitsWidth: Bool
    let fitRevision: Int

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makePDFView(context: Context) -> PDFView {
        let view = BookPDFSurface()
        view.document = document
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.autoScales = false
        view.maxScaleFactor = 5
        #if os(iOS)
        view.backgroundColor = UIColor(red: 0.973, green: 0.969, blue: 0.953, alpha: 1)
        #else
        view.backgroundColor = NSColor(red: 0.973, green: 0.969, blue: 0.953, alpha: 1)
        #endif
        context.coordinator.observe(view)
        view.didLayout = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.applyFit(to: view)
        }
        return view
    }

    func updatePDFView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if view.document !== document { view.document = document }
        if let page = document.page(at: pageIndex), view.currentPage !== page { view.go(to: page) }
        context.coordinator.applyFit(to: view)
    }

    final class Coordinator: NSObject {
        var parent: BookPDFView
        private var pageObserver: NSObjectProtocol?
        private var lastBounds = CGSize.zero
        private var lastFitRevision = -1
        private var fitScheduled = false

        init(parent: BookPDFView) { self.parent = parent }
        deinit { if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) } }

        func observe(_ view: PDFView) {
            pageObserver = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self, weak view] _ in
                guard let self, let page = view?.currentPage else { return }
                let index = self.parent.document.index(for: page)
                guard index != NSNotFound else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.parent.pageIndex != index else { return }
                    self.parent.pageIndex = index
                }
            }
        }

        func applyFit(to view: PDFView) {
            guard !fitScheduled else { return }
            fitScheduled = true
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.fitScheduled = false
                let size = view.bounds.size
                guard size.width > 0, size.height > 0,
                      size != self.lastBounds || self.lastFitRevision != self.parent.fitRevision,
                      let page = view.currentPage ?? self.parent.document.page(at: 0) else { return }
                self.lastBounds = size
                self.lastFitRevision = self.parent.fitRevision
                let bounds = page.bounds(for: .cropBox)
                let widthScale = max(0.1, (size.width - 24) / bounds.width)
                let wholePageScale = min(widthScale, max(0.1, (size.height - 24) / bounds.height))
                view.minScaleFactor = min(wholePageScale, 0.25)
                view.scaleFactor = self.parent.fitsWidth ? widthScale : wholePageScale
            }
        }
    }
}

private final class BookPDFSurface: PDFView {
    var didLayout: (() -> Void)?
    #if os(iOS)
    override func layoutSubviews() { super.layoutSubviews(); didLayout?() }
    #elseif os(macOS)
    override func layout() { super.layout(); didLayout?() }
    #endif
}

#if os(iOS)
extension BookPDFView: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView { makePDFView(context: context) }
    func updateUIView(_ uiView: PDFView, context: Context) { updatePDFView(uiView, context: context) }
}
#elseif os(macOS)
extension BookPDFView: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView { makePDFView(context: context) }
    func updateNSView(_ nsView: PDFView, context: Context) { updatePDFView(nsView, context: context) }
}
#endif
