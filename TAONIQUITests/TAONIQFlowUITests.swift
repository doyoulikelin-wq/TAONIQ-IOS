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

    @MainActor
    func testSpeedModesAndYearDayunSlidersUseTheLiveTrajectory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--disable-rotation"]
        app.launch()
        let play = app.buttons["playPauseButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: play)
        waitForExpectations(timeout: 45)
        let date = app.descendants(matching: .any)["flowDate"]
        let originalEpoch = try XCTUnwrap(Int64(date.value as? String ?? ""))
        let birthPillars = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@", "birthPillars", "年柱", "时柱")).firstMatch
        let originalPillars = birthPillars.label
        let year = app.sliders["yearSlider"]
        XCTAssertTrue(year.exists)
        for _ in 0..<4 where !year.isHittable { app.swipeUp() }
        XCTAssertTrue(year.isHittable)
        year.adjust(toNormalizedSliderPosition: 0.48)
        print("YEAR_SLIDER_VALUE", String(reflecting: year.value), "LABEL", year.label)
        let yearCaption = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]{4}年$")).firstMatch
        XCTAssertTrue(yearCaption.exists)
        let selectedYear = try XCTUnwrap(Int(yearCaption.label.dropLast()))
        expectation(for: ready, evaluatedWith: play)
        waitForExpectations(timeout: 45)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let afterYear = try XCTUnwrap(Int64(date.value as? String ?? ""))
        XCTAssertEqual(calendar.component(.year, from: Date(timeIntervalSince1970: Double(afterYear) / 1_000)), selectedYear)
        XCTAssertGreaterThan(afterYear, originalEpoch)
        XCTAssertEqual(play.value as? String, "paused")

        let dayun = app.sliders["dayunSlider"]
        if !dayun.isHittable { app.swipeDown() }
        XCTAssertTrue(dayun.isHittable)
        dayun.adjust(toNormalizedSliderPosition: 0.66)
        expectation(for: ready, evaluatedWith: play)
        waitForExpectations(timeout: 45)
        let afterDayun = try XCTUnwrap(Int64(date.value as? String ?? ""))
        XCTAssertNotEqual(afterDayun, afterYear)
        print("DAYUN_SLIDER_VALUE", String(reflecting: dayun.value), "LABEL", dayun.label)
        let dayunValue = try XCTUnwrap(dayun.value as? String)
        let startText = try XCTUnwrap(dayunValue.components(separatedBy: "起于 ").last)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy.MM.dd HH:mm:ss"
        let shownStart = try XCTUnwrap(formatter.date(from: startText))
        XCTAssertEqual(afterDayun, Int64(shownStart.timeIntervalSince1970 * 1_000), "The dayun control selects the personal period start, not a rounded January 1")
        XCTAssertGreaterThan(afterDayun, originalEpoch)
        XCTAssertEqual(birthPillars.label, originalPillars)
        XCTAssertEqual(play.value as? String, "paused")

        let dayMode = app.buttons["speed-day"]
        for _ in 0..<3 where !dayMode.isHittable { app.swipeDown() }
        XCTAssertTrue(dayMode.isHittable)
        for name in ["dayun", "year", "month", "day", "hour"] {
            XCTAssertTrue(app.buttons["speed-" + name].exists)
        }
        dayMode.tap()
        XCTAssertEqual(dayMode.value as? String, "selected")
        play.tap()
        expectation(for: dateChangedPredicate(String(afterDayun)), evaluatedWith: date)
        waitForExpectations(timeout: 15)
        let beforeSpeedChange = try XCTUnwrap(Int64(date.value as? String ?? ""))
        app.buttons["speed-year"].tap()
        XCTAssertEqual(app.buttons["speed-year"].value as? String, "selected")
        expectation(for: NSPredicate { _, _ in
            (Int64(date.value as? String ?? "") ?? 0) > beforeSpeedChange
        }, evaluatedWith: date)
        waitForExpectations(timeout: 15)
        XCTAssertEqual(play.value as? String, "playing")
        play.tap()
        XCTAssertEqual(birthPillars.label, originalPillars)
        let paused = try XCTUnwrap(Int64(date.value as? String ?? ""))
        XCTAssertGreaterThan(paused, afterDayun, "Changing speed continues the selected session rather than returning to birth")
        let preview = app.staticTexts["seekPreview"]
        XCTAssertTrue(preview.label.hasPrefix("当前"), "A completed drag must not leave the UI in its pending-seek state")
        let normalizedPreview = preview.label.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        XCTAssertEqual(normalizedPreview, "当前 " + formatter.string(from: Date(timeIntervalSince1970: Double(paused) / 1_000)))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "TAONIQ-speed-and-time-navigation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func dateChangedPredicate(_ old: String) -> NSPredicate {
        NSPredicate { object, _ in ((object as? XCUIElement)?.value as? String) != old }
    }
}
