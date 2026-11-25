import Foundation
import PDFKit
import SwiftUI

/// Reading editions are kept separate from evaluated, symbolic practice scores.
struct BundledBook: Identifiable, Hashable {
    let id: String
    let title: String
    let composer: String
    let edition: String
    let pageCount: Int
    let filename: String
    let sourceURL: URL

    static let beyer = BundledBook(
        id: "beyer-op101", title: "拜厄 Op.101", composer: "Ferdinand Beyer",
        edition: "Edition Peters · Adolf Ruthardt 编订 · 1895", pageCount: 88,
        filename: "Beyer-Op101",
        sourceURL: URL(string: "https://commons.wikimedia.org/wiki/File:Vorschule_im_Klavierspiel,_Op.101_(IA_imslp-im-klavierspiel-op101-beyer-ferdinand).pdf")!
    )
    static let all = [beyer]

    var resourceURL: URL? {
        #if SWIFT_PACKAGE
        // A packaged Mac preview keeps SwiftPM resources in the standard Resources folder.
        let bundle = Bundle.main.resourceURL
            .flatMap { Bundle(url: $0.appendingPathComponent("QinXu_QinXuApp.bundle")) } ?? Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        for directory in ["Resources/Books", "Books"] {
            if let url = bundle.url(forResource: filename, withExtension: "pdf", subdirectory: directory) {
                return url
            }
        }
        return nil
    }

    func loadDocument() -> PDFDocument? {
        guard let url = resourceURL, let document = PDFDocument(url: url),
              !document.isLocked, document.pageCount == pageCount else { return nil }
        return document
    }

    @MainActor func coverImage() -> Image? {
        guard let page = loadDocument()?.page(at: 0) else { return nil }
        let thumbnail = page.thumbnail(of: CGSize(width: 240, height: 340), for: .cropBox)
        #if os(iOS)
        return Image(uiImage: thumbnail)
        #elseif os(macOS)
        return Image(nsImage: thumbnail)
        #else
        return nil
        #endif
    }
}
