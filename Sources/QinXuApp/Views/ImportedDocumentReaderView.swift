import SwiftUI
import PDFKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
struct ImportedDocumentReaderView: View {
    @ObservedObject var model: PracticeViewModel
    let document: ImportedReadingDocument
    let compact: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var displayedPDF: PDFDocument?
    @State private var pageIndex = 0
    @State private var pageInput = "1"
    @State private var fitsWidth = true
    @State private var fitRevision = 0
    @State private var loadError: String?
    @State private var showingMetronomeSettings = false
    @State private var showingConversion = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 36, height: 36) }
                    .buttonStyle(.plain).accessibilityLabel("关闭阅读资料").accessibilityIdentifier("document.reader.close")
                VStack(alignment: .leading, spacing: 3) {
                    Text(document.title).font(.system(size: compact ? 16 : 20, weight: .semibold)).lineLimit(1)
                        .accessibilityIdentifier("document.reader.title")
                    Text("\(document.formatTitle) · 可跟节拍练习，不自动判音")
                        .font(.system(size: 11)).foregroundStyle(QinXuTheme.muted)
                }
                Spacer(minLength: 4)
                if document.kind == .pdf {
                    Button { showingConversion = true } label: {
                        Label("转 MXL", systemImage: "doc.text.viewfinder")
                    }
                    .buttonStyle(QuietButtonStyle()).disabled(displayedPDF == nil)
                    .accessibilityLabel("PDF 转 MXL，实验功能")
                    .accessibilityIdentifier("document.reader.convert")
                }
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
            metronomeControls
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
        .onAppear {
            // Reading has no score engine. Preserve an independently started global click.
            model.pausePractice()
            loadPage()
        }
        .sheet(isPresented: $showingMetronomeSettings) {
            GlobalMetronomeSettingsView(model: model, onClose: { showingMetronomeSettings = false })
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingConversion) {
            PDFScoreConversionView(model: model, document: document, initialPage: pageIndex + 1, compact: compact)
        }
        #else
        .sheet(isPresented: $showingConversion) {
            PDFScoreConversionView(model: model, document: document, initialPage: pageIndex + 1, compact: compact)
        }
        #endif
        .onChange(of: pageIndex) { _, value in
            pageInput = String(value + 1)
            if document.kind == .images { loadPage() }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: compact ? 320 : 380)
        #endif
    }

    private var metronomeControls: some View {
        HStack(spacing: compact ? 12 : 20) {
            Button { model.toggleMetronome() } label: {
                Label(model.metronomeRunning ? "停止节拍" : "跟拍练习",
                      systemImage: model.metronomeRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: compact ? 12 : 14, weight: .medium))
                    .frame(minHeight: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(QinXuTheme.accent)
            .accessibilityLabel(model.metronomeRunning ? "停止节拍器" : "启动节拍器")
            .accessibilityIdentifier("document.metronome.toggle")

            Button {
                model.pausePractice()
                showingMetronomeSettings = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "metronome")
                    Text("\(model.metronomeSettings.beatsPerMeasure)/\(model.metronomeSettings.beatUnit) · \(model.metronomeSettings.tempoNote.symbol) \(Int(model.metronomeSettings.tempoBPM))")
                        .monospacedDigit()
                    Image(systemName: "chevron.down").font(.system(size: 9))
                }.font(.system(size: compact ? 12 : 14)).frame(minHeight: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("全局节拍器设置")
            .accessibilityValue("\(model.metronomeSettings.beatsPerMeasure)/\(model.metronomeSettings.beatUnit)，\(model.metronomeSettings.tempoNote.title)每分钟 \(Int(model.metronomeSettings.tempoBPM)) 次，每响\(model.metronomeSettings.clickNote.title)")
            .accessibilityIdentifier("document.metronome.settings")

            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(model.metronomeRunning ? QinXuTheme.accent : QinXuTheme.line)
                    .frame(width: model.metronomeBeat == 1 ? 9 : 6, height: model.metronomeBeat == 1 ? 9 : 6)
                    .frame(width: 10, height: 10)
                Text(model.metronomeBeat.map { "第 \($0) 拍" } ?? "未运行")
                    .frame(width: compact ? 52 : 62, alignment: .leading)
                if model.metronomeSettings.pulsesPerBeat > 1 {
                    Text("\(model.metronomeSubdivision ?? 0)/\(model.metronomeSettings.pulsesPerBeat)")
                        .foregroundStyle(QinXuTheme.muted)
                }
            }
            .font(.system(size: compact ? 11 : 13)).monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("节拍指示")
            .accessibilityValue(model.metronomeBeat.map { "第 \($0) 拍，第 \(model.metronomeSubdivision ?? 1) 分拍" } ?? "未运行")
            .accessibilityIdentifier("document.metronome.beat")

            Button { model.metronomeEnabled.toggle() } label: {
                Image(systemName: model.metronomeEnabled && model.metronomeSoundAvailable ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: compact ? 14 : 17)).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain).disabled(!model.metronomeSoundAvailable)
            .accessibilityLabel(!model.metronomeSoundAvailable ? "麦克风录音期间仅视觉节拍" : model.metronomeEnabled ? "关闭节拍器声音" : "打开节拍器声音")
            .accessibilityIdentifier("document.metronome.sound")
        }
        .padding(.horizontal, compact ? 12 : 20).padding(.vertical, 4)
        .background(QinXuTheme.paper)
    }

    private func jump() {
        guard let page = Int(pageInput), (1...document.pageCount).contains(page) else {
            pageInput = String(pageIndex + 1); return
        }
        pageIndex = page - 1
    }

    private func loadPage() {
        do {
            let url = try model.documentLibrary.fileURL(for: document, pageIndex: pageIndex)
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
