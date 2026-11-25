import XCTest

/// These tests use real iOS touch delivery and view state. They do not simulate MIDI or microphone input.
final class QinXuUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTouchPracticeAdvancesPausesAndRestarts() {
        let app = launchFreshApp()
        defer { app.terminate() }
        enterPractice("demo-melody", in: app)
        let play = element("practice.play", in: app)
        play.tap()
        expect(play, "label CONTAINS %@", "暂停")

        let c4 = element("keyboard.key.60", in: app)
        reveal(c4, in: app, towardBottom: true)
        // The lower white-key area avoids the black keys that overlap the upper keyboard.
        c4.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        expect(element("practice.count.correct", in: app), "value == %@", "1")
        expect(element("practice.expected", in: app), "label CONTAINS %@", "D4")
        expect(c4, "value == %@", "未按下")

        let d4 = element("keyboard.key.62", in: app)
        reveal(d4, in: app, towardBottom: true)
        d4.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        expect(element("practice.count.correct", in: app), "value == %@", "2")
        expect(element("practice.expected", in: app), "label CONTAINS %@", "E4")
        capture(app, name: "touch-two-correct-notes")

        reveal(play, in: app, towardBottom: false)
        play.tap()
        expect(play, "label CONTAINS %@", "开始练习")
        expect(element("practice.count.correct", in: app), "value == %@", "2")
        let restart = element("practice.restart", in: app)
        XCTAssertTrue(restart.isHittable)
        restart.tap()
        expect(element("practice.count.correct", in: app), "value == %@", "0")
        expect(element("practice.expected", in: app), "label CONTAINS %@", "C4")
        expect(play, "label CONTAINS %@", "开始练习")
        capture(app, name: "practice-restarted")
    }

    @MainActor
    func testLibrarySelectionAndLandscapeLayout() {
        let app = launchFreshApp()
        defer { app.terminate() }
        let libraryButton = element("library.open", in: app)
        if libraryButton.exists { libraryButton.tap() }
        let rhythm = element("library.score.demo-rhythm", in: app)
        XCTAssertTrue(rhythm.waitForExistence(timeout: 10))
        expect(rhythm, "hittable == true")
        rhythm.tap()
        expect(element("detail.title", in: app), "label == %@", "轻步 · 节奏练习")
        element("detail.practice", in: app).tap()
        let title = element("practice.score.title", in: app)
        expect(title, "label == %@", "轻步 · 节奏练习")
        expect(element("practice.play", in: app), "label CONTAINS %@", "开始练习")
        capture(app, name: "selected-score-detail-to-practice")

        XCUIDevice.shared.orientation = .landscapeRight
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.width > frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
        // Verify a real control remains visible after layout changes, then exercise it.
        let play = element("practice.play", in: app)
        reveal(play, in: app, towardBottom: true)
        play.tap()
        expect(play, "label CONTAINS %@", "暂停")
        capture(app, name: "selected-score-landscape")
    }

    @MainActor
    func testFreshHistoryHasEmptyStateAndCanBeDismissed() {
        let app = launchFreshApp()
        defer { app.terminate() }
        element("history.open", in: app).tap()
        let empty = element("history.empty", in: app)
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        expect(empty, "label == %@", "暂无练习记录")
        capture(app, name: "empty-practice-history")
        let close = element("history.close", in: app)
        XCTAssertTrue(close.isHittable)
        close.tap()
        expect(element("library.search", in: app), "hittable == true")
        XCTAssertFalse(empty.exists)
    }

    @MainActor
    func testFavoriteSearchAndNavigationPausesPractice() {
        let app = launchFreshApp()
        defer { app.terminate() }
        element("library.favorite.demo-melody", in: app).tap()
        element("favorites.open", in: app).tap()
        XCTAssertTrue(element("library.score.demo-melody", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("library.score.demo-rhythm", in: app).exists)
        enterPractice("demo-melody", in: app)
        let play = element("practice.play", in: app)
        play.tap()
        expect(play, "label CONTAINS %@", "暂停")
        element("library.open", in: app).tap()
        element("practice.open", in: app).tap()
        expect(play, "label CONTAINS %@", "开始练习")
        element("library.open", in: app).tap()
        let search = element("library.search", in: app)
        search.tap()
        search.typeText("no-results-123")
        expect(element("library.score.demo-melody", in: app), "exists == false")
        XCTAssertFalse(element("library.score.demo-rhythm", in: app).exists)
        element("library.search.clear", in: app).tap()
        XCTAssertTrue(element("library.score.demo-melody", in: app).waitForExistence(timeout: 5))
        capture(app, name: "library-search-cleared")
    }

    @MainActor
    func testBundledBeyerCanTurnPagesAndClose() {
        let app = launchFreshApp()
        defer { app.terminate() }
        element("library.filter.books", in: app).tap()
        let book = element("library.book.beyer-op101", in: app)
        XCTAssertTrue(book.waitForExistence(timeout: 10))
        book.tap()
        XCTAssertTrue(element("textbook.title", in: app).waitForExistence(timeout: 10))
        element("textbook.source", in: app).tap()
        XCTAssertTrue(element("book.title", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("book.unavailable", in: app).exists)
        let page = element("book.pageInput", in: app)
        expect(page, "value == %@", "1")
        element("book.next", in: app).tap()
        expect(page, "value == %@", "2")
        element("book.previous", in: app).tap()
        expect(page, "value == %@", "1")
        capture(app, name: "beyer-original-book-reader")
        element("book.close", in: app).tap()
        element("textbook.close", in: app).tap()
        expect(element("library.search", in: app), "hittable == true")
    }

    @MainActor
    func testBeyerLessonOpensRealPracticeAndKeepsKeyboardGeometry() {
        let app = launchFreshApp()
        defer { app.terminate() }
        element("library.book.beyer-op101", in: app).tap()
        let firstLesson = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "textbook.practice.")).firstMatch
        XCTAssertTrue(firstLesson.waitForExistence(timeout: 10))
        firstLesson.tap()
        expect(element("practice.score.title", in: app), "label CONTAINS %@", "拜厄")
        let c5 = element("keyboard.key.72", in: app)
        reveal(c5, in: app, towardBottom: true)
        let before = c5.frame
        element("practice.play", in: app).tap()
        c5.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        expect(element("practice.count.correct", in: app), "value == %@", "1")
        XCTAssertEqual(c5.frame.minX, before.minX, accuracy: 1)
        XCTAssertEqual(c5.frame.width, before.width, accuracy: 1)
        capture(app, name: "beyer-chinese-lesson-real-practice")
    }

    @MainActor
    private func enterPractice(_ scoreID: String, in app: XCUIApplication) {
        let shortcut = element("library.practice." + scoreID, in: app)
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10))
        shortcut.tap()
        expect(element("practice.play", in: app), "label CONTAINS %@", "开始练习")
    }

    @MainActor
    private func launchFreshApp() -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let search = element("library.search", in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 20), "新首页应显示曲库")
        expect(element("library.score.demo-melody", in: app), "hittable == true")
        capture(app, name: "fresh-library-landscape")
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func expect(_ element: XCUIElement, _ format: String, _ argument: String? = nil,
                        file: StaticString = #filePath, line: UInt = #line) {
        let predicate = argument.map { NSPredicate(format: format, $0) } ?? NSPredicate(format: format)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed,
                       "未等到界面状态：\(element.identifier), \(format), \(argument ?? "")", file: file, line: line)
    }

    @MainActor
    private func reveal(_ target: XCUIElement, in app: XCUIApplication, towardBottom: Bool,
                        file: StaticString = #filePath, line: UInt = #line) {
        if target.exists && target.isHittable { return }
        let scroll = app.scrollViews["practice.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), file: file, line: line)
        for _ in 0..<8 {
            if target.exists && target.isHittable { return }
            // Start in the scroll view's outer padding, away from piano-key/score gestures.
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: towardBottom ? 0.78 : 0.28))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: towardBottom ? 0.28 : 0.78))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("无法滚动到控件：\(target.identifier)", file: file, line: line)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        // Capture the device surface, including rotation, rather than cropping
        // an application frame whose orientation may differ from the image.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
