import XCTest

final class FlowTests: XCTestCase {
    @MainActor
    func testScriptToRehearsalAndRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["sample-script"].tap()
        app.buttons["טקסט לגלילה"].tap()
        let title = app.textFields["script-title"]
        title.tap()
        title.press(forDuration: 1)
        // The sample content stays readable with a mixed-language title.
        title.typeText(" English 123")
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
            field.tap(); field.typeText(text)
        }
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

}
