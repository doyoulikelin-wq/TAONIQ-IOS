import XCTest

final class TAONIQFlowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testGenerateDragAndContinuousPlayback() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--disable-rotation"]
        app.launch()
        let play = app.buttons["playPauseButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: play)
        waitForExpectations(timeout: 45)

        let natal = app.descendants(matching: .any)["natalOrbit"]
        let flow = app.descendants(matching: .any)["flowOrbit"]
        XCTAssertTrue(natal.waitForExistence(timeout: 5))
        XCTAssertTrue(flow.exists)
        let oldCamera = natal.value as? String
        natal.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.50))
            .press(forDuration: 0.15, thenDragTo: natal.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.55)))
        XCTAssertNotEqual(natal.value as? String, oldCamera)
        XCTAssertEqual(natal.value as? String, flow.value as? String)

        let date = app.descendants(matching: .any)["flowDate"]
        XCTAssertTrue(date.exists)
        let initialDate = try XCTUnwrap(date.value as? String)
        if !play.isHittable { app.swipeUp() }
        play.tap()
        expectation(for: NSPredicate { _, _ in (date.value as? String) != initialDate }, evaluatedWith: date)
        waitForExpectations(timeout: 15)
        play.tap()
        let pausedDate = try XCTUnwrap(date.value as? String)
        let stable = expectation(description: "Paused displayed date remains fixed while an in-flight packet may finish")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            XCTAssertEqual(date.value as? String, pausedDate)
            stable.fulfill()
        }
        waitForExpectations(timeout: 5)
        play.tap()
        expectation(for: dateChangedPredicate(pausedDate), evaluatedWith: date)
        waitForExpectations(timeout: 15)
        play.tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "TAONIQ-continuous-flow"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        if !app.buttons["birthButton"].isHittable { app.swipeDown() }
        app.buttons["birthButton"].tap()
        XCTAssertTrue(app.buttons["generateButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers["birthDate"].exists)
        XCTAssertTrue(app.datePickers["birthTime"].exists)
        let inputShot = XCTAttachment(screenshot: app.screenshot())
        inputShot.name = "TAONIQ-birth-input"
        inputShot.lifetime = .keepAlways
        add(inputShot)
        app.datePickers["birthDate"].tap()
        let nextDay = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "8月28日", "August 28")).firstMatch
        if nextDay.waitForExistence(timeout: 2) {
            nextDay.tap()
        } else {
            app.staticTexts["28"].tap()
        }
        let dismissRegion = app.buttons["PopoverDismissRegion"]
        if dismissRegion.exists {
            dismissRegion.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.20)).tap()
        }
        app.segmentedControls["genderPicker"].buttons["女"].tap()
        app.buttons["generateButton"].tap()
        expectation(for: ready, evaluatedWith: play)
        waitForExpectations(timeout: 45)
        XCTAssertEqual(date.value as? String, String(Int64(initialDate)! + 86_400_000), "Editing the native birth date establishes the new chart at its own birthday")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label ENDSWITH %@", "· 女")).firstMatch.exists)
    }

    @MainActor
    func testAutoRotationKeepsTimeFixedAndBackgroundPausesEvolution() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let play = app.buttons["playPauseButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: play)
        waitForExpectations(timeout: 45)
        let natal = app.descendants(matching: .any)["natalOrbit"]
        let flow = app.descendants(matching: .any)["flowOrbit"]
        let date = app.descendants(matching: .any)["flowDate"]
        let startingDate = try XCTUnwrap(date.value as? String)
        let startingCamera = try XCTUnwrap(natal.value as? String)
        expectation(for: NSPredicate { _, _ in (natal.value as? String) != startingCamera }, evaluatedWith: natal)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(date.value as? String, startingDate)
        // Read both in one accessibility snapshot so the continuously moving
        // camera cannot step between two independent snapshot requests.
        let cameraSnapshot = app.debugDescription
        XCTAssertTrue(cameraSnapshot.contains("natalOrbit"))
        XCTAssertTrue(cameraSnapshot.contains("flowOrbit"))
        XCTAssertTrue(flow.exists)
        play.tap()
        expectation(for: dateChangedPredicate(startingDate), evaluatedWith: date)
        waitForExpectations(timeout: 15)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(play.value as? String, "paused")
        let pausedDate = try XCTUnwrap(date.value as? String)
        let stable = expectation(description: "Returning from background preserves the paused simulation date")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(date.value as? String, pausedDate)
            stable.fulfill()
        }
        waitForExpectations(timeout: 5)
    }

    private func dateChangedPredicate(_ old: String) -> NSPredicate {
        NSPredicate { object, _ in ((object as? XCUIElement)?.value as? String) != old }
    }
}
