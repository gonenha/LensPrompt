import XCTest

final class FlowTests: XCTestCase {
    @MainActor
    func testAISettingsAndMissingKeyDoNotCreateScripts() {
        let app = XCUIApplication(); app.launch()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.navigationBars["הגדרות"].waitForExistence(timeout: 3))
        app.buttons["סיום"].tap()
        reveal(app.buttons["sample-script"], in: app, upwards: true)
        app.buttons["sample-script"].tap()
        app.buttons["script-styles"].tap()
        XCTAssertTrue(app.buttons["generate-styles"].waitForExistence(timeout: 3))
        app.buttons["generate-styles"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["יש לשמור מפתח API בהגדרות לפני היצירה."].exists)
        XCTAssertFalse(app.buttons["save-styles"].exists)
        app.alerts.buttons.firstMatch.tap()
        app.buttons["סגירה"].tap()
        XCTAssertTrue(app.buttons["prepare"].waitForExistence(timeout: 3))
    }

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
    func testRecordingPauseFreezesRehearsalTimerAndCanFinishPaused() {
        let app = XCUIApplication(); app.launch()
        app.buttons["new-script"].tap(); app.buttons["נקודות לדיבור"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "point-opening").firstMatch
        field.tap(); app.typeText("Pause this take"); app.buttons["dismiss-keyboard"].tap()
        app.buttons["prepare"].tap(); app.swipeUp(); app.buttons["rehearse"].tap()
        let timer = app.staticTexts["take-timer"]
        XCTAssertTrue(timer.waitForExistence(timeout: 3))
        app.buttons["pause-recording"].tap()
        let pausedTime = timer.label
        let stayedPaused = expectation(for: NSPredicate { _, _ in timer.label != pausedTime }, evaluatedWith: timer)
        stayedPaused.isInverted = true; wait(for: [stayedPaused], timeout: 1.3)
        app.buttons["pause-recording"].tap()
        let resumes = expectation(for: NSPredicate { _, _ in timer.label != pausedTime }, evaluatedWith: timer)
        wait(for: [resumes], timeout: 3)
        app.buttons["pause-recording"].tap(); app.buttons["finish-take"].tap()
        XCTAssertTrue(app.staticTexts["התרגול הסתיים"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSavedMovieCanPlayAndDeleteWithConfirmation() {
        let app = XCUIApplication(); app.launch(); app.buttons["takes"].tap()
        let fixture = app.staticTexts["בדיקת סרטון — סימולטור"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 3))
        app.otherElements["take-group-legacy-בדיקת סרטון — סימולטור"].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-take-")).firstMatch.tap()
        XCTAssertTrue(app.buttons["play-take"].waitForExistence(timeout: 5))
        app.buttons["play-take"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "take-review-player"; shot.lifetime = .keepAlways; add(shot)
        app.swipeUp(); app.buttons["delete-take"].tap(); app.buttons["ביטול"].tap()
        XCTAssertTrue(app.buttons["delete-take"].exists)
        app.buttons["delete-take"].tap(); app.buttons["מחיקת טייק"].tap()
        XCTAssertTrue(app.navigationBars["הטייקים שלי"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["בדיקת סרטון — סימולטור"].exists)
        app.buttons["סיום"].tap(); XCTAssertTrue(app.buttons["new-script"].exists)
    }

    @MainActor
    func testGroupedTakesCanRateAndShareTwoTogether() {
        let app = XCUIApplication(); app.launch(); app.buttons["takes"].tap()
        let groupID = "script-A580DC69-2F6D-48EB-AFCF-5417C3D0865E"
        let group = app.otherElements["take-group-" + groupID]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        let opens = group.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-take-"))
        XCTAssertEqual(opens.count, 2)
        opens.firstMatch.tap()
        reveal(app.buttons["rating-excellent"], in: app, upwards: true)
        app.buttons["rating-excellent"].tap()
        XCTAssertTrue(app.staticTexts["דירוג: מעולה"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(group.staticTexts["מעולה"].exists)
        let groupShot = XCTAttachment(screenshot: app.screenshot()); groupShot.name = "grouped-takes"; groupShot.lifetime = .keepAlways; add(groupShot)
        app.buttons["select-takes"].tap()
        let selections = group.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "select-take-"))
        selections.element(boundBy: 0).tap(); selections.element(boundBy: 1).tap()
        app.buttons["share-selected"].tap()
        XCTAssertTrue(app.staticTexts["שיתוף 2 סרטונים"].waitForExistence(timeout: 5))
        app.buttons["close-share"].tap()
        app.buttons["select-takes"].tap()
        opens.firstMatch.tap()
        reveal(app.buttons["rating-good"], in: app, upwards: true)
        XCTAssertTrue(app.staticTexts["דירוג: מעולה"].exists)
        app.buttons["rating-good"].tap()
        XCTAssertTrue(app.staticTexts["דירוג: טוב"].exists)
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
