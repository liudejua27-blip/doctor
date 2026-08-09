import XCTest

final class BodyCompanionInternalUITests: XCTestCase {
    @MainActor
    func testColdStartShowsP0TodayEntry() {
        let app = launchApp()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.today").firstMatch)
        assertExists(app.buttons["intake-entry.start-record"])
        XCTAssertFalse(app.buttons["intake-entry.resume-draft"].exists)
        XCTAssertTrue(app.staticTexts["这不是诊断；每一步都可以保留为未确认草稿，稍后继续。"].exists)
    }

    @MainActor
    func testTwoDTextPickerReachesStructuredIntake() {
        let app = launchApp()
        selectKneeFromTextPicker(in: app)

        assertExists(app.buttons["body-map.next"])
        app.buttons["body-map.next"].tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.signal-intake").firstMatch)
    }

    @MainActor
    func testTextPickerNoResultDoesNotCreateLocationDraft() {
        let app = launchApp()
        openBodyMap(in: app)

        let textPicker = app.buttons["body-map.text-picker-open"]
        assertExists(textPicker)
        textPicker.tap()

        let search = app.textFields["body-map.text-picker.search"]
        assertExists(search)
        search.tap()
        search.typeText("不存在的部位")
        dismissKeyboard(in: app)

        assertExists(app.staticTexts["没有匹配的部位"])
        XCTAssertFalse(app.buttons["body-map.next"].exists)

        let done = app.buttons["body-map.text-picker-done"]
        assertExists(done)
        done.tap()
        XCTAssertFalse(app.buttons["body-map.next"].exists)
    }

    @MainActor
    func testRecordsAndAssistantUseTheSameP0EntryPath() {
        let app = launchApp()

        app.tabBars.buttons["记录"].tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.records").firstMatch)
        assertExists(app.buttons["intake-entry.start-record"])
        app.buttons["intake-entry.start-record"].tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.body-map").firstMatch)

        app.tabBars.buttons["AI 身体助手"].tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.analysis").firstMatch)
        assertExists(app.buttons["intake-entry.start-record"])
        app.buttons["intake-entry.start-record"].tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.body-map").firstMatch)
    }

    @MainActor
    func testStartOverCancellationKeepsCurrentDraftResumable() {
        let app = launchApp()
        selectKneeFromTextPicker(in: app)
        returnToToday(in: app)

        let resume = app.buttons["intake-entry.resume-draft"]
        assertExists(resume)
        resume.tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.signal-intake").firstMatch)
        app.tabBars.buttons["今天"].tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.today").firstMatch)
        assertExists(resume)

        let startOver = app.buttons["intake-entry.start-over"]
        assertExists(startOver)
        startOver.tap()
        assertExists(app.staticTexts["新建一条记录？"])
        tapStartOverCancellation(in: app)

        XCTAssertFalse(app.sheets["新建一条记录？"].waitForExistence(timeout: 1))
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.today").firstMatch)
        assertExists(resume)
        resume.tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.signal-intake").firstMatch)
    }

    @MainActor
    func testStartOverConfirmationClearsCurrentDraft() {
        let app = launchApp()
        selectKneeFromTextPicker(in: app)
        returnToToday(in: app)

        let resume = app.buttons["intake-entry.resume-draft"]
        assertExists(resume)

        let startOver = app.buttons["intake-entry.start-over"]
        assertExists(startOver)
        startOver.tap()
        assertExists(app.staticTexts["新建一条记录？"])

        let confirmDiscard = app.buttons.matching(identifier: "intake-entry.confirm-discard").firstMatch
        assertExists(confirmDiscard)
        confirmDiscard.tap()

        assertExists(app.descendants(matching: .any).matching(identifier: "screen.body-map").firstMatch)
        XCTAssertFalse(app.buttons["body-map.next"].exists)

        returnToToday(in: app)
        assertExists(app.buttons["intake-entry.start-record"])
        XCTAssertFalse(app.buttons["intake-entry.resume-draft"].exists)
    }

    @MainActor
    func testAssistantKeepsOrdinaryChatClosed() {
        let app = launchApp()
        app.tabBars.buttons["AI 身体助手"].tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.analysis").firstMatch)
        assertExists(app.descendants(matching: .any).matching(identifier: "analysis.standard-chat-unavailable").firstMatch)
        XCTAssertFalse(app.staticTexts["行动计划"].exists)
    }

    @MainActor
    func testCandidateThreeDFallsBackToTwoDInUISmoke() {
        let app = launchApp()
        openBodyMap(in: app)

        let modeControl = app.segmentedControls["body-map.mode"]
        assertExists(modeControl)
        modeControl.buttons["3D"].tap()

        assertExists(app.descendants(matching: .any).matching(identifier: "body-map.fallback-notice").firstMatch)
        assertTextPickerCanOpen(in: app)
    }

    @MainActor
    func testExplicitCandidateThreeDProbeKeepsListPath() {
        let app = launchCandidateThreeDProbe()
        openBodyMap(in: app)

        let modeControl = app.segmentedControls["body-map.mode"]
        assertExists(modeControl)
        modeControl.buttons["3D"].tap()

        let candidateReady = app.descendants(matching: .any)
            .matching(identifier: "body-map.candidate-3d-ready")
            .firstMatch
        let fallback = app.descendants(matching: .any)
            .matching(identifier: "body-map.candidate-3d-fallback-notice")
            .firstMatch
        let loadAttempted = app.descendants(matching: .any)
            .matching(identifier: "body-map.candidate-3d-load-attempted")
            .firstMatch
        let terminalState = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ OR identifier == %@",
                    "body-map.candidate-3d-ready",
                    "body-map.candidate-3d-fallback-notice"
                )
            )
            .firstMatch

        assertExists(loadAttempted, timeout: 10)
        assertExists(terminalState, timeout: 10)
        if candidateReady.exists {
            XCTAssertFalse(fallback.exists)
            assertExists(app.descendants(matching: .any).matching(identifier: "body-map.3d-scene").firstMatch)
            assertTextPickerCanOpen(in: app)
        } else {
            assertExists(fallback)
            XCTAssertFalse(candidateReady.exists)
            assertTextPickerCanOpen(in: app)
        }
    }

    @MainActor
    func testRestartDoesNotClaimDraftPersistence() {
        let app = launchApp()
        selectKneeFromTextPicker(in: app)
        app.terminate()
        app.launch()

        assertExists(app.descendants(matching: .any).matching(identifier: "screen.today").firstMatch)
        assertExists(app.buttons["intake-entry.start-record"])
        XCTAssertFalse(app.buttons["intake-entry.resume-draft"].exists)
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BODY_COMPANION_UI_SMOKE"] = "1"
        app.launch()
        return app
    }

    @MainActor
    private func launchCandidateThreeDProbe() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BODY_COMPANION_ENABLE_CANDIDATE_3D"] = "1"
        app.launch()
        return app
    }

    @MainActor
    private func openBodyMap(in app: XCUIApplication) {
        assertExists(app.buttons["intake-entry.start-record"])
        app.buttons["intake-entry.start-record"].tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.body-map").firstMatch)
    }

    @MainActor
    private func selectKneeFromTextPicker(in app: XCUIApplication) {
        openBodyMap(in: app)
        let textPicker = app.buttons["body-map.text-picker-open"]
        assertExists(textPicker)
        textPicker.tap()

        let search = app.textFields["body-map.text-picker.search"]
        assertExists(search)
        search.tap()
        search.typeText("膝")
        dismissKeyboard(in: app)

        let leftKnee = app.buttons["body-map.text-picker.option-body.knee.general-left"]
        assertExists(leftKnee)
        leftKnee.tap()
        assertExists(app.buttons["body-map.next"])
        assertExists(app.staticTexts["已添加待确认位置：左膝附近"])
        XCTAssertFalse(app.buttons["body-map.mark-editor-done"].exists)

        let done = app.buttons["body-map.text-picker-done"]
        assertExists(done)
        done.tap()
    }

    @MainActor
    private func assertTextPickerCanOpen(in app: XCUIApplication) {
        let textPicker = app.buttons["body-map.text-picker-open"]
        assertExists(textPicker)
        textPicker.tap()
        assertExists(app.textFields["body-map.text-picker.search"])
        let done = app.buttons["body-map.text-picker-done"]
        assertExists(done)
        done.tap()
    }

    @MainActor
    private func returnToToday(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        assertExists(back)
        back.tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.today").firstMatch)
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        let returnKey = app.keyboards.buttons["Return"]
        assertExists(returnKey)
        returnKey.tap()
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 1), "Expected the search keyboard to dismiss before choosing a body region")
    }

    @MainActor
    private func tapStartOverCancellation(in app: XCUIApplication) {
        // This iPhone simulator presents SwiftUI's confirmation dialog as a
        // popover with no visible cancel row. Dismissing its system region is
        // the black-box cancellation action; other presentations expose the
        // app's Chinese cancel control instead.
        let candidates = [
            app.otherElements.matching(identifier: "PopoverDismissRegion").firstMatch,
            app.buttons.matching(identifier: "intake-entry.cancel-discard").firstMatch,
            app.buttons["取消"],
            app.buttons["Cancel"],
        ]
        guard let cancel = candidates.first(where: \.exists) else {
            XCTFail("Expected a cancellation control in the start-over confirmation dialog")
            return
        }
        cancel.tap()
    }

    @MainActor
    private func assertExists(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected element to exist: \(element)", file: file, line: line)
    }
}
