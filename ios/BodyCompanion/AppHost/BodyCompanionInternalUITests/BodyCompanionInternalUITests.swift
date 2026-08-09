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
    func testTwoDListReachesStructuredIntake() {
        let app = launchApp()
        selectFirstLocationFromTwoDList(in: app)

        assertExists(app.buttons["body-map.next"])
        app.buttons["body-map.next"].tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.signal-intake").firstMatch)
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
    func testDraftResumeAndStartOverConfirmationAreExplicit() {
        let app = launchApp()
        selectFirstLocationFromTwoDList(in: app)
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
        XCTAssertTrue(resume.exists)
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
        assertExists(app.buttons["body-map.2d-list.option-0"])
    }

    @MainActor
    func testRestartDoesNotClaimDraftPersistence() {
        let app = launchApp()
        selectFirstLocationFromTwoDList(in: app)
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
    private func openBodyMap(in app: XCUIApplication) {
        assertExists(app.buttons["intake-entry.start-record"])
        app.buttons["intake-entry.start-record"].tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.body-map").firstMatch)
    }

    @MainActor
    private func selectFirstLocationFromTwoDList(in app: XCUIApplication) {
        openBodyMap(in: app)
        let firstOption = app.buttons["body-map.2d-list.option-0"]
        assertExists(firstOption)
        firstOption.tap()

        let done = app.buttons["body-map.mark-editor-done"]
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
    private func assertExists(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected element to exist: \(element)", file: file, line: line)
    }
}
