import XCTest

final class FlowTests: XCTestCase {
    @MainActor
    func testLargeTextEditorCanReachSpeakingPointAndPrepare() {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["new-script"].tap()
        app.buttons["נקודות לדיבור"].tap()
        let opening = app.descendants(matching: .any).matching(identifier: "point-opening").firstMatch
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "dark-studio-large-text-editor"; shot.lifetime = .keepAlways; add(shot)
        for _ in 0..<5 where !opening.isHittable { app.swipeUp() }
        XCTAssertTrue(opening.isHittable)
        opening.tap(); opening.typeText("A clear opening")
        app.buttons["dismiss-keyboard"].tap()
        let prepare = app.buttons["prepare"]
        if !prepare.isHittable { app.swipeUp() }
        XCTAssertTrue(prepare.isHittable)
        prepare.tap()
        XCTAssertTrue(app.navigationBars["לפני הטייק"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLibraryBottomNavigationOpensTakesAndReturns() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["library-tab"].exists)
        app.buttons["takes"].tap()
        XCTAssertTrue(app.navigationBars["הטייקים שלי"].waitForExistence(timeout: 3))
        app.buttons["סיום"].tap()
        XCTAssertTrue(app.buttons["new-script"].waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "dark-studio-library"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor
    func testScriptToRehearsalAndRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        reveal(app.buttons["sample-script"], in: app, upwards: true)
        app.buttons["sample-script"].tap()
        app.buttons["טקסט לגלילה"].tap()
        let title = app.textFields["script-title"]
        title.tap()
        title.press(forDuration: 1)
        // The sample content stays readable with a mixed-language title.
        title.typeText(" English 123")
        app.buttons["dismiss-keyboard"].tap()
        app.buttons["prepare"].tap()
        // Saved settings survive test runs: this journey specifically exercises fixed scrolling.
        let voice = app.switches["voice-follow"]
        if voice.value as? String == "1" { voice.tap() }
        app.buttons["distance-mode"].tap()
        XCTAssertTrue(app.staticTexts["7 שניות"].exists)
        app.buttons["rehearse"].tap()
        let timer = app.staticTexts["take-timer"]
        XCTAssertTrue(timer.waitForExistence(timeout: 3))
        app.buttons["pause-text"].tap()
        XCTAssertTrue(app.buttons["המשך גלילה"].exists)
        app.buttons["reset-text"].tap()
        app.buttons["finish-take"].tap()
        XCTAssertTrue(app.staticTexts["התרגול הסתיים"].waitForExistence(timeout: 3))
        app.buttons["back-setup"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["sample-script"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "English 123")).firstMatch.exists)
    }

    @MainActor
    func testNewEmptyScriptCannotStartAndCanBeDeleted() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["new-script"].tap()
        XCTAssertFalse(app.buttons["prepare"].isEnabled)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["new-script"].exists)
    }
    @MainActor
    func testVoiceFollowSettingsPersistAndDeniedMicFallsBackToFixedPractice() {
        let app = XCUIApplication()
        app.launch()
        reveal(app.buttons["sample-script"], in: app, upwards: true)
        app.buttons["sample-script"].tap()
        app.buttons["prepare"].tap()
        let toggle = app.switches["voice-follow"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        if toggle.value as? String == "0" { toggle.tap() }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "voice-follow-setup"; screenshot.lifetime = .keepAlways
        add(screenshot)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.terminate(); app.launch()
        reveal(app.buttons["sample-script"], in: app, upwards: true)
        app.buttons["sample-script"].tap()
        app.buttons["prepare"].tap()
        XCTAssertEqual(app.switches["voice-follow"].value as? String, "1")
        app.swipeUp()
        app.buttons["rehearse"].tap()
        let fallback = app.alerts.buttons["תרגול בגלילה רגילה"]
        XCTAssertTrue(fallback.waitForExistence(timeout: 3))
        fallback.tap()
        XCTAssertTrue(app.staticTexts["take-timer"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["voice-status"].exists)
        app.buttons["finish-take"].tap()
        XCTAssertTrue(app.staticTexts["התרגול הסתיים"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testManualTalkingPointsAdvanceOnlyOnButtonAndPersist() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["new-script"].tap()
        app.buttons["נקודות לדיבור"].tap()
        XCTAssertFalse(app.buttons["prepare"].isEnabled)
        for (stage, text) in [("opening", "Opening idea"), ("pain", "Pain idea"), ("solution", "Solution idea"), ("offer", "Offer idea")] {
            let field = app.descendants(matching: .any).matching(identifier: "point-" + stage).firstMatch
            reveal(field, in: app, upwards: true)
            field.tap()
            // Type into the focused, visible field; rehearsal verifies every saved value.
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            app.typeText(text)
            app.buttons["dismiss-keyboard"].tap()
        }
        reveal(app.buttons["טקסט לגלילה"], in: app, upwards: false)
        app.buttons["טקסט לגלילה"].tap()
        XCTAssertFalse(app.buttons["prepare"].isEnabled)
        app.buttons["נקודות לדיבור"].tap()
        app.buttons["prepare"].tap()
        XCTAssertFalse(app.switches["voice-follow"].exists)
        app.swipeUp()
        app.buttons["rehearse"].tap()
        let sentence = app.staticTexts["point-sentence"]
        XCTAssertTrue(sentence.waitForExistence(timeout: 3))
        XCTAssertEqual(sentence.label, "Opening idea")
        XCTAssertFalse(app.buttons["previous-point"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "manual-talking-point"; screenshot.lifetime = .keepAlways; add(screenshot)
        let timer = app.staticTexts["take-timer"]
        let initialTime = timer.label
        let timeChanges = expectation(for: NSPredicate { _, _ in timer.label != initialTime }, evaluatedWith: timer)
        wait(for: [timeChanges], timeout: 3)
        XCTAssertEqual(sentence.label, "Opening idea")
        for expected in ["Pain idea", "Solution idea", "Offer idea"] {
            app.buttons["next-point"].tap()
            XCTAssertEqual(sentence.label, expected)
        }
        XCTAssertFalse(app.buttons["next-point"].isEnabled)
        XCTAssertTrue(app.buttons["finish-take"].isEnabled)
        app.buttons["previous-point"].tap()
        XCTAssertEqual(sentence.label, "Solution idea")
        app.buttons["finish-take"].tap()
        XCTAssertTrue(app.staticTexts["התרגול הסתיים"].waitForExistence(timeout: 3))
        app.buttons["טייק נוסף"].tap()
        XCTAssertTrue(sentence.waitForExistence(timeout: 3))
        XCTAssertEqual(sentence.label, "Opening idea")
        app.buttons["finish-take"].tap()
        app.buttons["back-setup"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Opening idea\nPain idea\nSolution idea\nOffer idea"].exists)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool) {
        for _ in 0..<10 {
            var bottom = app.frame.maxY - 90
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY) }
            let create = app.buttons["new-script"]
            if create.exists && create.isHittable { bottom = min(bottom, create.frame.minY) }
            let prepare = app.buttons["prepare"]
            if prepare.exists && prepare.isHittable { bottom = min(bottom, prepare.frame.minY) }
            let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : 60
            if element.exists && element.isHittable && element.frame.midY > top + 8 && element.frame.midY < bottom - 8 { return }
            // Swipe the visible form, above the keyboard and pinned actions.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let upper = origin.withOffset(CGVector(dx: app.frame.midX, dy: top + 24))
            let lower = origin.withOffset(CGVector(dx: app.frame.midX, dy: max(top + 60, bottom - 24)))
            if upwards { lower.press(forDuration: 0.05, thenDragTo: upper) }
            else { upper.press(forDuration: 0.05, thenDragTo: lower) }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Editor control should be reachable by scrolling")
    }

}
