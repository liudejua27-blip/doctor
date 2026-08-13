import XCTest

final class BodyCompanionInternalUITests: XCTestCase {
    private final class IssueBox: @unchecked Sendable {
        var issue: XCTIssue

        init(_ issue: XCTIssue) {
            self.issue = issue
        }
    }

    private var activeApp: XCUIApplication?
    private var didCaptureFailureDiagnostics = false

    override func record(_ issue: XCTIssue) {
        guard issue.type == .assertionFailure,
              !didCaptureFailureDiagnostics,
              let app = activeApp else {
            super.record(issue)
            return
        }

        didCaptureFailureDiagnostics = true
        let issueBox = IssueBox(issue)
        MainActor.assumeIsolated { [app, issueBox] in
            var enrichedIssue = issueBox.issue

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "failure-screen"
            screenshot.lifetime = .keepAlways
            enrichedIssue.add(screenshot)

            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "failure-accessibility-hierarchy"
            hierarchy.lifetime = .keepAlways
            enrichedIssue.add(hierarchy)
            issueBox.issue = enrichedIssue
        }

        super.record(issueBox.issue)
    }

    override func tearDown() {
        activeApp = nil
        super.tearDown()
    }

    @MainActor
    func testColdStartShowsP0TodayEntry() {
        let app = launchApp()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.today").firstMatch)
        assertExists(app.buttons["intake-entry.start-record"])
        XCTAssertFalse(app.buttons["intake-entry.resume-draft"].exists)
        XCTAssertTrue(app.staticTexts["身体地图只表达“我感觉在这里”，不判断病因或受损组织。"].exists)
        assertExists(app.descendants(matching: .any).matching(identifier: "today.journey").firstMatch)
    }

    @MainActor
    func testTwoDTextPickerReachesStructuredIntake() {
        let app = launchApp()
        selectKneeFromTextPicker(in: app)

        tapMapContinuationAction(in: app)
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.signal-intake").firstMatch)
    }

    @MainActor
    func testMoreSensationsKeepsStructuredInternalDraftFlow() {
        let app = launchApp()
        selectKneeFromTextPicker(in: app)
        tapMapContinuationAction(in: app)
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.signal-intake").firstMatch)

        let moreSensations = app.descendants(matching: .any)
            .matching(identifier: "sensation-picker.more-open")
            .firstMatch
        scrollUntilHittable(moreSensations, in: app)
        moreSensations.tap()

        let numbness = app.switches["麻木"]
        scrollUntilHittable(numbness, in: app)
        // A Form Toggle exposes a full-width accessibility row, while the
        // native switch occupies its trailing edge. Hit the native control so
        // this smoke test verifies a real user toggle instead of tapping only
        // the label portion of the row.
        numbness.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        // Assert the platform UISwitch state here. The standard Toggle
        // semantics provide VoiceOver's localized on/off announcement, while
        // XCTest exposes that state as the stable 0/1 string.
        let selected = expectation(
            for: NSPredicate(format: "value == %@", "1"),
            evaluatedWith: numbness
        )
        wait(for: [selected], timeout: 5)
        XCTAssertFalse(app.staticTexts["行动计划"].exists)
        XCTAssertFalse(app.staticTexts["已保存"].exists)
    }

    @MainActor
    func testAccessibilitySizeKeepsP0ActionsReachableAndAdaptive() {
        let app = launchAccessibilitySizeApp()

        let exerciseCue = app.descendants(matching: .any)
            .matching(identifier: "today.context-cue.exercise")
            .firstMatch
        let workCue = app.descendants(matching: .any)
            .matching(identifier: "today.context-cue.work")
            .firstMatch
        // Context cues are display-only content, not P0 actions. Their stable
        // identifiers and the adaptive vertical container provide the intended
        // structure evidence. Scroll only to materialize the presentation
        // content; `isHittable` would incorrectly turn it into a tappable
        // control requirement.
        app.swipeUp()
        scrollUntilExists(exerciseCue, in: app)
        scrollUntilExists(workCue, in: app)
        assertExists(
            app.descendants(matching: .any)
                .matching(identifier: "today.context-cues.vertical")
                .firstMatch
        )
        XCTAssertFalse(
            app.buttons["today.context-cue.exercise"].exists,
            "Expected the exercise context cue to remain display content, not an action."
        )
        XCTAssertFalse(
            app.buttons["today.context-cue.work"].exists,
            "Expected the work context cue to remain display content, not an action."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: "today.context-cues.horizontal")
                .firstMatch
                .exists
        )

        // The cards are presentation content on the Today scroll view. Switch
        // to the independent Records entry rather than coupling the rest of
        // this test to reversing that long accessibility-size scroll position.
        app.tabBars.buttons["记录"].tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.records").firstMatch)
        selectKneeFromTextPicker(in: app)
        tapMapContinuationAction(in: app)
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.signal-intake").firstMatch)

        let intakeScroll = app.descendants(matching: .any)
            .matching(identifier: "screen.signal-intake")
            .firstMatch
        assertExists(intakeScroll)
        let reviewSensation = app.descendants(matching: .any)
            .matching(identifier: "sensation-picker.review")
            .firstMatch
        let unknownSensation = app.descendants(matching: .any)
            .matching(identifier: "sensation-picker.unknown-all")
            .firstMatch
        scrollUntilHittableEitherDirection(reviewSensation, in: app, within: intakeScroll)
        let sensationActions = app.descendants(matching: .any)
            .matching(identifier: "sensation-picker.actions.vertical")
            .firstMatch
        assertExists(sensationActions)
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: "sensation-picker.actions.horizontal")
                .firstMatch
                .exists
        )
        scrollUntilHittableEitherDirection(unknownSensation, in: app, within: intakeScroll)

        let saveTemporal = app.descendants(matching: .any)
            .matching(identifier: "temporal.save")
            .firstMatch
        let unknownTemporal = app.descendants(matching: .any)
            .matching(identifier: "temporal.unknown")
            .firstMatch
        scrollUntilHittableEitherDirection(saveTemporal, in: app, within: intakeScroll)
        let temporalActions = app.descendants(matching: .any)
            .matching(identifier: "temporal.actions.vertical")
            .firstMatch
        assertExists(temporalActions)
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: "temporal.actions.horizontal")
                .firstMatch
                .exists
        )
        scrollUntilHittableEitherDirection(unknownTemporal, in: app, within: intakeScroll)
    }

    @MainActor
    func testMultipleLocationsKeepPerLocationUnknownDistinctFromGroupUnknown() {
        let app = launchApp()
        selectBothKneesFromTextPicker(in: app)
        tapMapContinuationAction(in: app)
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.signal-intake").firstMatch)

        // SwiftUI Form Toggle rows are exposed as `Switch` on some runtimes
        // and as a combined accessibility row on others. The stable product
        // identifier is the contract; do not bind this smoke test to the
        // native element class.
        let perLocationUnknown = app.descendants(matching: .any)
            .matching(identifier: "sensation-picker.per-location-unknown")
            .firstMatch
        scrollUntilHittable(perLocationUnknown, in: app)
        assertExists(perLocationUnknown)

        let groupUnknown = app.buttons["这些位置的感觉都说不清"]
        scrollUntilHittable(groupUnknown, in: app)
        assertExists(groupUnknown)
        XCTAssertFalse(app.switches["说不清/不想回答"].exists)
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

        let done = app.buttons["body-map.text-picker-done"]
        assertExists(done)
        done.tap()
        XCTAssertFalse(pendingMarkSummary(in: app).exists)
        assertMarkerCountEmpty(in: app)
        XCTAssertFalse(markerCountSummary(in: app).exists)
        assertExists(continuationUnavailableStatus(in: app))
        XCTAssertFalse(mapContinuationAction(in: app).exists, "Closing an empty text picker must not expose the enabled continuation action.")
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
        assertMarkerCountEmpty(in: app)
        XCTAssertFalse(markerCountSummary(in: app).exists)
        assertExists(continuationUnavailableStatus(in: app))
        XCTAssertFalse(mapContinuationAction(in: app).exists, "A reset draft must not expose the enabled continuation action.")

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
            // Let the app-side eight-second watchdog pass. A delayed timeout
            // must not demote a Scene that already acknowledged readiness.
            RunLoop.current.run(until: Date().addingTimeInterval(8.5))
            assertExists(candidateReady)
            XCTAssertFalse(fallback.exists)
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
        activeApp = app
        return app
    }

    @MainActor
    private func launchAccessibilitySizeApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BODY_COMPANION_UI_SMOKE"] = "1"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        activeApp = app
        return app
    }

    @MainActor
    private func launchCandidateThreeDProbe() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["BODY_COMPANION_ENABLE_CANDIDATE_3D"] = "1"
        app.launch()
        activeApp = app
        return app
    }

    @MainActor
    private func openBodyMap(in app: XCUIApplication) {
        let startRecord = app.buttons["intake-entry.start-record"]
        assertExists(startRecord)
        scrollUntilHittable(startRecord, in: app)
        startRecord.tap()
        assertExists(app.descendants(matching: .any).matching(identifier: "screen.body-map").firstMatch)
    }

    @MainActor
    private func selectKneeFromTextPicker(in app: XCUIApplication) {
        openBodyMap(in: app)
        let textPicker = app.buttons["body-map.text-picker-open"]
        assertExists(textPicker)
        scrollUntilHittable(textPicker, in: app)
        textPicker.tap()

        let search = app.textFields["body-map.text-picker.search"]
        assertExists(search)
        search.tap()
        search.typeText("膝")
        dismissKeyboard(in: app)

        let pickerList = app.descendants(matching: .any)
            .matching(identifier: "body-map.text-picker")
            .firstMatch
        assertExists(pickerList)
        let leftKnee = app.buttons["body-map.text-picker.option-body.knee.general-left-lateral"]
        // At accessibility sizes the sheet keeps results below its explanatory
        // text, so the lazy List has not materialized this row until it is
        // scrolled into view. Limit the gesture to the sheet list so the
        // background map never competes for the same vertical swipe.
        scrollPickerOptionIntoView(leftKnee, in: pickerList)
        leftKnee.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertTextRegionSelectionFeedback(in: app)
        // Text selection must not present a competing editor while its Sheet
        // is still in control of the interaction.
        XCTAssertFalse(
            app.buttons["body-map.mark-editor-done"].waitForExistence(timeout: 1),
            "Text selection must not present a competing mark editor."
        )

        let done = app.buttons["body-map.text-picker-done"]
        assertExists(done)
        XCTAssertTrue(done.isHittable)
        done.tap()

        XCTAssertFalse(
            done.waitForExistence(timeout: 5),
            "Expected the text-region picker to dismiss after the explicit completion action."
        )

        // The product-visible pending summary proves the broad location
        // survived the explicit Sheet completion. The marker editor must not
        // automatically cover the map when the Sheet goes away.
        assertExists(pendingMarkSummary(in: app))
        assertMarkerCountSummaryExists(in: app)
        XCTAssertFalse(markerCountEmpty(in: app).exists)
        XCTAssertFalse(continuationUnavailableStatus(in: app).exists)
        XCTAssertFalse(
            app.buttons["body-map.mark-editor-done"].waitForExistence(timeout: 1),
            "Finishing text selection must not automatically present the marker editor."
        )

        // The persistent footer exists even before a selection, but becomes
        // actionable only after the pending summary above proves a location is
        // retained. Do not scroll to compensate for a layout defect.
        let next = mapContinuationAction(in: app)
        assertExists(next)
        XCTAssertTrue(next.isHittable, "Expected the persistent map continuation action to be immediately reachable after the picker closes.")
    }

    @MainActor
    private func selectBothKneesFromTextPicker(in app: XCUIApplication) {
        openBodyMap(in: app)
        let textPicker = app.buttons["body-map.text-picker-open"]
        assertExists(textPicker)
        scrollUntilHittable(textPicker, in: app)
        textPicker.tap()

        let search = app.textFields["body-map.text-picker.search"]
        assertExists(search)
        search.tap()
        search.typeText("膝")
        dismissKeyboard(in: app)

        let pickerList = app.descendants(matching: .any)
            .matching(identifier: "body-map.text-picker")
            .firstMatch
        assertExists(pickerList)
        let leftKnee = app.buttons["body-map.text-picker.option-body.knee.general-left-lateral"]
        let rightKnee = app.buttons["body-map.text-picker.option-body.knee.general-right-lateral"]
        scrollPickerOptionIntoView(leftKnee, in: pickerList)
        leftKnee.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        scrollPickerOptionIntoView(rightKnee, in: pickerList)
        rightKnee.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertTextRegionSelectionFeedback(in: app)
        XCTAssertFalse(
            app.buttons["body-map.mark-editor-done"].waitForExistence(timeout: 1),
            "Text selection must not present a competing mark editor."
        )

        let done = app.buttons["body-map.text-picker-done"]
        assertExists(done)
        XCTAssertTrue(done.isHittable)
        done.tap()

        XCTAssertFalse(
            done.waitForExistence(timeout: 5),
            "Expected the text-region picker to dismiss after the explicit completion action."
        )
        assertExists(pendingMarkSummary(in: app))
        assertMarkerCountSummaryExists(in: app)
        XCTAssertFalse(markerCountEmpty(in: app).exists)
        XCTAssertFalse(continuationUnavailableStatus(in: app).exists)
        XCTAssertFalse(
            app.buttons["body-map.mark-editor-done"].waitForExistence(timeout: 1),
            "Finishing text selection must not automatically present the marker editor."
        )
        let next = mapContinuationAction(in: app)
        assertExists(next)
        XCTAssertTrue(next.isHittable, "Expected the persistent map continuation action to be immediately reachable after the picker closes.")
    }

    @MainActor
    private func assertTextPickerCanOpen(in app: XCUIApplication) {
        let textPicker = app.buttons["body-map.text-picker-open"]
        assertExists(textPicker)
        scrollUntilHittable(textPicker, in: app)
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
    private func mapContinuationAction(in app: XCUIApplication) -> XCUIElement {
        // The persistent native Button must not be queried through a specific
        // XCTest role: the stable identifier—not an accessibility class—is
        // the cross-runtime contract.
        app.descendants(matching: .any)
            .matching(identifier: "body-map.next")
            .firstMatch
    }

    @MainActor
    private func continuationUnavailableStatus(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "body-map.continuation-unavailable")
            .firstMatch
    }

    @MainActor
    private func pendingMarkSummary(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "body-map.pending-mark-summary")
            .firstMatch
    }

    @MainActor
    private func assertTextRegionSelectionFeedback(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let feedback = app.descendants(matching: .any)
            .matching(identifier: "body-map.text-picker.selection-notice")
            .firstMatch
        assertExists(feedback, file: file, line: line)
    }

    @MainActor
    private func assertMarkerCountSummaryExists(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let summary = app.descendants(matching: .any)
            .matching(identifier: "body-map.marker-count-summary")
            .firstMatch
        assertExists(summary, file: file, line: line)
    }

    @MainActor
    private func markerCountSummary(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "body-map.marker-count-summary")
            .firstMatch
    }

    @MainActor
    private func markerCountEmpty(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "body-map.marker-count-empty")
            .firstMatch
    }

    @MainActor
    private func assertMarkerCountEmpty(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertExists(markerCountEmpty(in: app), file: file, line: line)
    }

    @MainActor
    private func tapMapContinuationAction(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let next = mapContinuationAction(in: app)
        assertExists(next, file: file, line: line)
        XCTAssertTrue(
            next.isHittable,
            "Expected the persistent map continuation action to be immediately reachable after the picker closes.",
            file: file,
            line: line
        )
        next.tap()
    }

    @MainActor
    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        within scrollContainer: XCUIElement? = nil,
        maxSwipes: Int = 12,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        func isReachable() -> Bool {
            element.exists && element.isHittable
        }

        for _ in 0..<maxSwipes where !isReachable() {
            if let scrollContainer {
                scrollContainer.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(isReachable(), "Expected element to become hittable: \(element)", file: file, line: line)
    }

    @MainActor
    private func scrollPickerOptionIntoView(
        _ element: XCUIElement,
        in pickerList: XCUIElement,
        maxSwipes: Int = 12,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<maxSwipes {
            guard element.exists else {
                pickerList.swipeUp()
                continue
            }

            let visibleFrame = pickerList.frame.insetBy(dx: 0, dy: 32)
            let elementFrame = element.frame
            if elementFrame.minY >= visibleFrame.minY,
               elementFrame.maxY <= visibleFrame.maxY,
               elementFrame.height > 0,
               element.isHittable {
                return
            }
            pickerList.swipeUp()
        }

        XCTAssertTrue(
            element.exists && element.isHittable,
            "Expected text-picker option to be fully visible and hittable: \(element)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func scrollUntilHittableEitherDirection(
        _ element: XCUIElement,
        in app: XCUIApplication,
        within scrollContainer: XCUIElement,
        maxSwipes: Int = 18,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        func isReachable() -> Bool {
            element.exists && element.isHittable
        }

        func visibleFrame() -> CGRect {
            // Form's content viewport is inset by the navigation and tab bars.
            // Keeping a small guard band avoids treating a partly clipped row as
            // reachable on older Simulator runtimes.
            scrollContainer.frame.insetBy(dx: 0, dy: 110)
        }

        func moveTowardElement() {
            guard element.exists else {
                // A lazy Form row may not be in the accessibility tree yet. The
                // intake screen starts near the top, so discover it by moving
                // down the content (a swipe up).
                scrollContainer.swipeUp()
                return
            }

            let target = element.frame
            let viewport = visibleFrame()
            if target.maxY < viewport.minY {
                scrollContainer.swipeDown()
            } else if target.minY > viewport.maxY {
                scrollContainer.swipeUp()
            } else {
                // The row intersects the viewport but may still be clipped by a
                // Form section boundary. A small upward move usually materializes
                // the complete cell without traversing the entire form.
                scrollContainer.swipeUp()
            }
        }

        for _ in 0..<maxSwipes {
            if isReachable() { return }
            moveTowardElement()
        }

        // If the screen was restored at the bottom, search back toward the top.
        for _ in 0..<maxSwipes {
            if isReachable() { return }
            guard element.exists else {
                scrollContainer.swipeDown()
                continue
            }

            let target = element.frame
            let viewport = visibleFrame()
            if target.maxY < viewport.minY {
                scrollContainer.swipeDown()
            } else if target.minY > viewport.maxY {
                scrollContainer.swipeUp()
            } else {
                scrollContainer.swipeDown()
            }
        }
        XCTAssertTrue(
            isReachable(),
            "Expected intake action to become hittable after scrolling either direction: \(element)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func scrollUntilExists(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 12,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<maxSwipes where !element.exists {
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, "Expected presentation element to exist after scrolling: \(element)", file: file, line: line)
    }

    @MainActor
    private func scrollDownUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 12,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<maxSwipes where !element.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(element.isHittable, "Expected element to become hittable after scrolling down: \(element)", file: file, line: line)
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
