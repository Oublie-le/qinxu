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
        XCTAssertLessThan(before.height, 100)
        element("practice.play", in: app).tap()
        c5.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        expect(element("practice.count.correct", in: app), "value == %@", "1")
        XCTAssertEqual(c5.frame.minX, before.minX, accuracy: 1)
        XCTAssertEqual(c5.frame.width, before.width, accuracy: 1)
        capture(app, name: "beyer-chinese-lesson-real-practice")
    }

    @MainActor
    func testBundledPopCollectionOpensAndPlaysAGroupedScore() {
        let app = launchFreshApp()
        defer { app.terminate() }
        element("library.filter.collections", in: app).tap()
        let collection = element("library.collection.bundled-pop-piano", in: app)
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        XCTAssertFalse(element("library.score.pop-window-rain", in: app).exists)
        collection.tap()
        expect(element("collection.title", in: app), "label == %@", "流行钢琴")
        let practice = element("collection.practice.pop-window-rain", in: app)
        XCTAssertTrue(practice.waitForExistence(timeout: 10))
        practice.tap()
        expect(element("practice.score.title", in: app), "label == %@", "窗边的雨")
        expect(element("practice.play", in: app), "label CONTAINS %@", "开始练习")
        capture(app, name: "bundled-pop-collection-practice")
    }

    @MainActor
    func testImportSeparatesPracticeScoresFromReadingDocuments() {
        let app = launchFreshApp()
        defer { app.terminate() }
        element("library.import", in: app).tap()
        XCTAssertTrue(element("import.title", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("import.score", in: app).exists)
        XCTAssertTrue(element("import.pdf", in: app).exists)
        XCTAssertTrue(element("import.images", in: app).exists)
        capture(app, name: "score-and-reading-import-choices")
        element("import.close", in: app).tap()
        expect(element("library.search", in: app), "hittable == true")
    }

    @MainActor
    func testImportedPDFCanKeepTimeWhileTurningPages() {
        let app = launchFreshApp(additionalArguments: ["--ui-test-reading-pdf"])
        defer { app.terminate() }
        element("library.filter.books", in: app).tap()
        let pdf = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.document.")).firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout: 10), "应从测试曲库打开实际导入的 PDF")
        pdf.tap()

        expect(element("document.reader.title", in: app), "label == %@", "读谱练习测试谱")
        let toggle = element("document.metronome.toggle", in: app)
        let beat = element("document.metronome.beat", in: app)
        toggle.tap()
        expect(toggle, "label == %@", "停止节拍器")
        expectAdvancingMetronomeBeat(beat)

        let page = element("document.reader.pageInput", in: app)
        expect(page, "value == %@", "1")
        element("document.reader.next", in: app).tap()
        expect(page, "value == %@", "2")
        expectAdvancingMetronomeBeat(beat)
        element("document.metronome.settings", in: app).tap()
        XCTAssertTrue(element("globalMetronome.title", in: app).waitForExistence(timeout: 8))
        element("globalMetronome.cancel", in: app).tap()
        expect(page, "value == %@", "2")
        expect(toggle, "label == %@", "停止节拍器")
        capture(app, name: "imported-pdf-with-metronome")
        toggle.tap()
        expect(beat, "value == %@", "未运行")
    }

    @MainActor
    func testImmersionHidesNavigationAndKeepsKeyboardPlayable() {
        let app = launchFreshApp()
        defer { app.terminate() }
        enterPractice("demo-melody", in: app)
        let immersion = element("practice.immersion", in: app)
        reveal(immersion, in: app, towardBottom: false)
        immersion.tap()
        expect(immersion, "value == %@", "已开启")
        expect(element("library.open", in: app), "exists == false")
        XCTAssertFalse(element("practice.back", in: app).exists)

        let play = element("practice.play", in: app)
        XCTAssertTrue(play.isHittable, "沉浸模式应保留播放控制")
        play.tap()
        let c4 = element("keyboard.key.60", in: app)
        XCTAssertTrue(c4.isHittable, "沉浸模式应保留可触摸键盘")
        tapKey(60, in: app)
        expect(element("practice.count.correct", in: app), "value == %@", "1")
        expect(element("practice.expected", in: app), "label CONTAINS %@", "D4")
        capture(app, name: "immersive-keyboard-real-input")

        reveal(immersion, in: app, towardBottom: false)
        immersion.tap()
        expect(immersion, "value == %@", "已关闭")
        expect(element("library.open", in: app), "hittable == true")
        expect(element("practice.count.correct", in: app), "value == %@", "1")
        expect(play, "label CONTAINS %@", "暂停")
    }

    @MainActor
    func testLongNoteShowsDecreasingBeatsAndSecondsAndPauseClearsIt() {
        let app = launchFreshApp()
        defer { app.terminate() }
        element("library.book.beyer-op101", in: app).tap()
        let lesson = element("textbook.practice.beyer-op101-001-theme", in: app)
        XCTAssertTrue(lesson.waitForExistence(timeout: 10))
        lesson.tap()

        // Use the actual tempo control to make this whole note long enough to inspect.
        // This changes musical duration; there is no test-only clock or fixed sleep.
        element("practice.tempo", in: app).tap()
        let tempo = app.sliders.matching(identifier: "globalMetronome.tempo").firstMatch
        XCTAssertTrue(element("globalMetronome.title", in: app).waitForExistence(timeout: 8))
        reveal(tempo, in: app, towardBottom: true, scrollIdentifier: "globalMetronome.scroll")
        tempo.adjust(toNormalizedSliderPosition: 0)
        expect(tempo, "value == %@", "20")
        element("globalMetronome.save", in: app).tap()
        expect(element("practice.tempo", in: app), "label CONTAINS %@", "四分音符每分钟 20 次")
        element("practice.play", in: app).tap()
        tapKey(72, in: app)

        let hold = element("practice.sustain.72", in: app)
        XCTAssertTrue(hold.waitForExistence(timeout: 5))
        expect(hold, "label CONTAINS %@", "C5")
        let initialValue = hold.value as? String ?? ""
        XCTAssertTrue(initialValue.contains("剩余") && initialValue.contains("拍") && initialValue.contains("秒"))
        let initialSeconds = remainingSeconds(in: initialValue)
        XCTAssertNotNil(initialSeconds)
        XCTAssertGreaterThan(initialSeconds ?? 0, 0)
        XCTAssertLessThanOrEqual(initialSeconds ?? .infinity, 12)
        let decreasing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard hold.exists, let first = initialSeconds,
                  let now = self.remainingSeconds(in: hold.value as? String ?? "") else { return false }
            return now > 0 && now < first
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [decreasing], timeout: 5), .completed,
                       "长音剩余秒数应随实际练习时钟递减")
        expect(element("practice.count.correct", in: app), "value == %@", "1")
        capture(app, name: "long-note-seconds-and-beats-countdown")

        element("practice.play", in: app).tap()
        expect(element("practice.play", in: app), "label CONTAINS %@", "开始练习")
        expect(hold, "exists == false")
    }

    @MainActor
    func testMetronomeVisualBeatRunsAndStopsIndependently() {
        let app = launchFreshApp()
        defer { app.terminate() }
        enterPractice("demo-melody", in: app)
        let toggle = element("practice.metronome.toggle", in: app)
        let beat = element("practice.metronome.beat", in: app)
        expect(toggle, "label == %@", "启动节拍器")
        toggle.tap()
        expect(toggle, "label == %@", "停止节拍器")
        expect(beat, "value BEGINSWITH %@", "第 ")
        let initialBeat = beat.value as? String ?? ""
        let advancing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = beat.value as? String else { return false }
            return value.hasPrefix("第 ") && value != initialBeat
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 5), .completed,
                       "节拍指示应实际推进，不能只改变按钮标题")
        expect(element("practice.play", in: app), "label CONTAINS %@", "开始练习")
        let sound = element("practice.metronome.sound", in: app)
        sound.tap()
        expect(sound, "label == %@", "打开节拍器声音")
        capture(app, name: "metronome-visual-beat-without-playback")
        toggle.tap()
        expect(toggle, "label == %@", "启动节拍器")
        expect(beat, "value == %@", "未运行")
        // --ui-testing disables audio-device access; this validates visual controls, not audible clicks.
    }

    @MainActor
    func testGlobalMetronomeSettingsSurviveSongChangesAndRelaunch() {
        let storeID = UUID()
        let app = launchFreshApp(storeID: storeID)
        defer { app.terminate() }
        element("navigation.metronome", in: app).tap()
        XCTAssertTrue(element("globalMetronome.title", in: app).waitForExistence(timeout: 8))

        let tempo = app.sliders.matching(identifier: "globalMetronome.tempo").firstMatch
        reveal(tempo, in: app, towardBottom: true, scrollIdentifier: "globalMetronome.scroll")
        expect(tempo, "value == %@", "80")
        setGlobalMetronomeTempo(90, in: app)
        chooseGlobalMetronomeOption("tempoNote", value: "quarter", in: app)
        chooseGlobalMetronomeOption("beatsPerMeasure", value: "3", in: app)
        chooseGlobalMetronomeOption("beatUnit", value: "4", in: app)
        chooseGlobalMetronomeOption("clickNote", value: "eighth", in: app)
        element("globalMetronome.save", in: app).tap()
        expect(element("globalMetronome.title", in: app), "exists == false")

        let summary = "3/4，四分音符每分钟 90 次，每响八分音符"
        element("navigation.metronome", in: app).tap()
        expect(element("globalMetronome.summary", in: app), "value == %@", summary)
        let globalToggle = element("globalMetronome.toggle", in: app)
        expect(globalToggle, "label == %@", "启动节拍器")
        globalToggle.tap()
        expect(globalToggle, "label == %@", "停止节拍器")
        expectAdvancingMetronomeBeat(element("globalMetronome.beat", in: app))
        element("globalMetronome.cancel", in: app).tap()

        // These original scores have their own different tempo metadata. Neither
        // selection nor navigation may replace the saved global settings or stop
        // the independently started metronome.
        for scoreID in ["demo-melody", "demo-rhythm"] {
            enterPractice(scoreID, in: app)
            expect(element("practice.tempo", in: app), "label CONTAINS %@", "四分音符每分钟 90 次")
            expect(element("practice.metronome.toggle", in: app), "label == %@", "停止节拍器")
            expectAdvancingMetronomeBeat(element("practice.metronome.beat", in: app))
            expect(element("practice.play", in: app), "label CONTAINS %@", "开始练习")

            element("practice.tempo", in: app).tap()
            expect(element("globalMetronome.summary", in: app), "value == %@", summary)
            expect(element("globalMetronome.toggle", in: app), "label == %@", "停止节拍器")
            element("globalMetronome.cancel", in: app).tap()
            capture(app, name: "global-metronome-preserved-" + scoreID)
            element("library.open", in: app).tap()
        }

        // Reuse only this test's UUID-scoped temporary store. The normal user
        // library and every other test remain isolated.
        app.terminate()
        let relaunched = launchFreshApp(storeID: storeID)
        defer { relaunched.terminate() }
        element("navigation.metronome", in: relaunched).tap()
        expect(element("globalMetronome.summary", in: relaunched), "value == %@", summary)
        expect(element("globalMetronome.toggle", in: relaunched), "label == %@", "启动节拍器")
        expect(element("globalMetronome.beat", in: relaunched), "value == %@", "未运行")
        capture(relaunched, name: "global-metronome-settings-after-relaunch")
        // --ui-testing disables audio-device access; no audible-click claim is made.
    }

    @MainActor
    func testReportShowsRealWrongAndCorrectCountsWithoutInventedRhythmScore() {
        let app = launchFreshApp()
        defer { app.terminate() }
        enterPractice("demo-melody", in: app)
        let report = element("practice.report", in: app)
        XCTAssertFalse(report.isEnabled)
        element("practice.play", in: app).tap()
        tapKey(62, in: app) // D4 is wrong while C4 is expected.
        expect(element("practice.count.wrong", in: app), "value == %@", "1")
        tapKey(60, in: app)
        expect(element("practice.count.correct", in: app), "value == %@", "1")
        report.tap()
        expect(element("report.title", in: app), "label == %@", "晨光 · 右手识谱")
        expect(element("report.metric.correct", in: app), "value == %@", "1")
        expect(element("report.metric.wrong", in: app), "value == %@", "1")
        expect(element("report.metric.pitchAccuracy", in: app), "value == %@", "50.0%")
        XCTAssertFalse(element("report.overallScore", in: app).exists)
        XCTAssertFalse(element("report.metric.rhythmScore", in: app).exists)
        XCTAssertFalse(element("report.metric.missed", in: app).exists)
        let suggestions = element("report.suggestions", in: app)
        reveal(suggestions, in: app, towardBottom: true, scrollIdentifier: "report.scroll")
        XCTAssertTrue(suggestions.exists)
        capture(app, name: "partial-reading-report-real-counts")
        element("report.close", in: app).tap()
        expect(element("practice.play", in: app), "label CONTAINS %@", "开始练习")
        expect(element("practice.count.correct", in: app), "value == %@", "1")
    }

    @MainActor
    func testSavedMeasureCanResumeThroughScoreDetail() {
        let app = launchFreshApp()
        defer { app.terminate() }
        enterPractice("demo-melody", in: app)
        element("practice.play", in: app).tap()
        for (index, pitch) in [60, 62, 64, 67].enumerated() {
            tapKey(pitch, in: app)
            expect(element("practice.count.correct", in: app), "value == %@", String(index + 1))
        }
        expect(element("practice.expected", in: app), "label CONTAINS %@", "A4")
        element("practice.play", in: app).tap()
        element("library.open", in: app).tap()
        element("library.score.demo-melody", in: app).tap()
        expect(element("detail.progress", in: app), "label MATCHES %@", ".*第\\s*2\\s*小节.*")
        let resume = element("detail.resume", in: app)
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        resume.tap()
        expect(element("practice.expected", in: app), "label CONTAINS %@", "A4")
        expect(element("practice.count.correct", in: app), "value == %@", "0")
        element("practice.play", in: app).tap()
        tapKey(69, in: app)
        expect(element("practice.count.correct", in: app), "value == %@", "1")
        expect(element("practice.expected", in: app), "label CONTAINS %@", "G4")
        capture(app, name: "saved-measure-resumed-through-detail")
        // Fresh UI launches intentionally get isolated stores. Cross-launch persistence has separate store tests.
    }

    @MainActor
    private func tapKey(_ pitch: Int, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        let key = element("keyboard.key.\(pitch)", in: app)
        reveal(key, in: app, towardBottom: true, file: file, line: line)
        key.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
    }

    private func remainingSeconds(in value: String) -> Double? {
        guard let comma = value.lastIndex(of: "，"), let seconds = value.lastIndex(of: "秒"), comma < seconds else { return nil }
        return Double(value[value.index(after: comma)..<seconds].trimmingCharacters(in: .whitespaces))
    }

    @MainActor
    private func setGlobalMetronomeTempo(_ target: Int, in app: XCUIApplication,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let tempo = app.sliders.matching(identifier: "globalMetronome.tempo").firstMatch
        // Use the stepper's real one-BPM actions and read every result. Slider
        // coordinates do not map exactly to values across native device layouts.
        for _ in 0..<20 {
            guard let value = tempo.value as? String, let current = Int(value) else {
                XCTFail("无法读取节拍器的实际速度", file: file, line: line)
                return
            }
            if current == target { return }
            let increment = current < target
            let button = element("globalMetronome.tempoStepper-" + (increment ? "Increment" : "Decrement"), in: app)
            reveal(button, in: app, towardBottom: true, scrollIdentifier: "globalMetronome.scroll", file: file, line: line)
            button.tap()
            expect(tempo, "value == %@", String(current + (increment ? 1 : -1)), file: file, line: line)
        }
        expect(tempo, "value == %@", String(target), file: file, line: line)
    }

    @MainActor
    private func chooseGlobalMetronomeOption(_ setting: String, value: String, in app: XCUIApplication,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let picker = element("globalMetronome." + setting, in: app)
        reveal(picker, in: app, towardBottom: true, scrollIdentifier: "globalMetronome.scroll", file: file, line: line)
        picker.tap()
        let option = element("globalMetronome." + setting + "." + value, in: app)
        XCTAssertTrue(option.waitForExistence(timeout: 8), file: file, line: line)
        option.tap()
    }

    @MainActor
    private func expectAdvancingMetronomeBeat(_ beat: XCUIElement,
                                             file: StaticString = #filePath, line: UInt = #line) {
        expect(beat, "value BEGINSWITH %@", "第 ", file: file, line: line)
        let initial = beat.value as? String ?? ""
        let advancing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard beat.exists, let value = beat.value as? String else { return false }
            return value.hasPrefix("第 ") && value != initial
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advancing], timeout: 5), .completed,
                       "独立节拍指示应继续按时钟推进", file: file, line: line)
    }

    @MainActor
    private func enterPractice(_ scoreID: String, in app: XCUIApplication) {
        let shortcut = element("library.practice." + scoreID, in: app)
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10))
        shortcut.tap()
        expect(element("practice.play", in: app), "label CONTAINS %@", "开始练习")
    }

    @MainActor
    private func launchFreshApp(storeID: UUID? = nil, additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // A manually opened app may still be running before the first test.
        // Rotate after closing it, then wait for the newly launched layout.
        if app.state != .notRunning { app.terminate() }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments += ["--ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchArguments += additionalArguments
        if let storeID { app.launchArguments.append("--ui-test-store-id=" + storeID.uuidString) }
        app.launch()
        let search = element("library.search", in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 20), "新首页应显示曲库")
        let melody = app.buttons.matching(identifier: "library.score.demo-melody").firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let window = app.windows.firstMatch
            guard window.exists, search.exists, melody.exists else { return false }
            let frame = window.frame
            return frame.width > frame.height && search.isHittable && melody.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed,
                       "首页横屏布局、搜索框和样谱卡片应就绪")
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
                       "未等到界面状态：\(format), \(argument ?? "")", file: file, line: line)
    }

    @MainActor
    private func reveal(_ target: XCUIElement, in app: XCUIApplication, towardBottom: Bool,
                        scrollIdentifier: String = "practice.scroll",
                        file: StaticString = #filePath, line: UInt = #line) {
        if target.exists && target.isHittable { return }
        let scroll = app.scrollViews[scrollIdentifier]
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
