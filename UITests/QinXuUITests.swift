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

        XCTAssertTrue(play.isHittable, "滚动到琴键后，底部播放按钮应保持可用")
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
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let libraryButton = element("library.open", in: app)
        if libraryButton.exists { libraryButton.tap() }
        let rhythm = element("library.score.demo-rhythm", in: app)
        XCTAssertTrue(rhythm.waitForExistence(timeout: 10))
        expect(rhythm, "hittable == true")
        rhythm.tap()
        let title = element("practice.score.title", in: app)
        expect(title, "label == %@", "轻步 · 节奏练习")
        expect(element("practice.play", in: app), "label CONTAINS %@", "开始练习")
        capture(app, name: "selected-score-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.width > frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 10), .completed)
        // Verify a real control remains visible after layout changes, then exercise it.
        let play = element("practice.play", in: app)
        XCTAssertTrue(play.isHittable, "横屏时底部播放按钮应保持可用")
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
        expect(element("practice.play", in: app), "hittable == true")
        XCTAssertFalse(empty.exists)
    }

    @MainActor
    func testPracticeSettingsCanEnableLoopAndReturnToScore() {
        let app = launchFreshApp()
        defer { app.terminate() }
        element("practice.settings", in: app).tap()

        let loop = element("practice.loop.toggle", in: app)
        expect(loop, "hittable == true")
        loop.tap()
        XCTAssertTrue(element("practice.loop.start", in: app).waitForExistence(timeout: 8))
        capture(app, name: "practice-settings-loop")

        element("practice.settings.done", in: app).tap()
        expect(element("practice.play", in: app), "hittable == true")
        XCTAssertFalse(loop.exists)
    }

    @MainActor
    private func launchFreshApp() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let play = element("practice.play", in: app)
        XCTAssertTrue(play.waitForExistence(timeout: 20), "练习主页应在隔离的触屏模式下启动")
        expect(play, "label CONTAINS %@", "开始练习")
        expect(element("practice.score.title", in: app), "label == %@", "晨光 · 右手识谱")
        capture(app, name: "fresh-practice-home")
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
        let scroll = app.scrollViews["practice.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), file: file, line: line)
        for _ in 0..<8 {
            if target.exists && target.isHittable && scroll.frame.contains(target.frame) { return }
            // Start in the scroll view's outer padding, away from piano-key/score gestures.
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: towardBottom ? 0.78 : 0.28))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: towardBottom ? 0.28 : 0.78))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("无法滚动到控件：\(target.identifier)", file: file, line: line)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
