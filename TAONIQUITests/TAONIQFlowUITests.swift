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

    /// Measure the rendered screen's actual civil clock while normal 3D rotation
    /// remains enabled. Selection styling alone is not proof that speed changed.
    @MainActor
    func testMeasuredPlaybackRatesChangeWithEverySpeedWhileRotating() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let play = app.buttons["playPauseButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: play)
        waitForExpectations(timeout: 45)
        let date = app.descendants(matching: .any)["flowDate"]
        let firstMode = app.buttons["speed-hour"]
        for _ in 0..<4 where !firstMode.isHittable { app.swipeUp() }
        XCTAssertTrue(firstMode.isHittable)
        firstMode.tap()
        play.tap()

        func readClock() throws -> (epoch: Double, wall: TimeInterval, querySeconds: TimeInterval) {
            let before = ProcessInfo.processInfo.systemUptime
            let raw = date.value as? String
            let after = ProcessInfo.processInfo.systemUptime
            let epoch = try XCTUnwrap(raw.flatMap(Double.init), "flowDate must expose its accepted epoch in milliseconds")
            return (epoch, (before + after) / 2, after - before)
        }
        func waitWallClock(_ seconds: TimeInterval) {
            let waited = expectation(description: "Observe real playback for \(seconds) wall seconds")
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { waited.fulfill() }
            waitForExpectations(timeout: seconds + 8)
        }

        let modes = ["hour", "day", "month", "year", "dayun", "hour"]
        var measurements: [[String: Any]] = []
        var rates: [Double] = []
        var selectedStates: [Bool] = []
        var playingStates: [Bool] = []
        var monotonicStates: [Bool] = []
        for (index, mode) in modes.enumerated() {
            let beforeSwitch = try readClock()
            let button = app.buttons["speed-" + mode]
            button.tap()
            let selected = (button.value as? String) == "selected"
            let playingAfterTap = (play.value as? String) == "playing"
            // A single packet already in flight may retain the previous mode.
            // Exclude that bounded transition from the steady-rate measurement.
            waitWallClock(0.4)
            let start = try readClock()
            waitWallClock(2.0)
            let end = try readClock()
            let wall = end.wall - start.wall
            let delta = end.epoch - start.epoch
            let rate = delta / 1_000 / max(wall, 0.000_001)
            let playing = playingAfterTap && (play.value as? String) == "playing"
            selectedStates.append(selected)
            playingStates.append(playing)
            monotonicStates.append(start.epoch >= beforeSwitch.epoch && end.epoch > start.epoch)
            rates.append(rate)
            let record: [String: Any] = [
                "index": index, "mode": mode,
                "detail": app.staticTexts["speedDetail"].label,
                "selected": selected, "playing": playing,
                "epochBeforeSwitchMs": beforeSwitch.epoch,
                "startEpochMs": start.epoch, "endEpochMs": end.epoch,
                "wallSeconds": wall, "civilDeltaMs": delta,
                "civilSecondsPerWallSecond": rate,
                "civilDaysPerWallSecond": rate / 86_400,
                "startQuerySeconds": start.querySeconds, "endQuerySeconds": end.querySeconds
            ]
            measurements.append(record)
            let json = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            print("TAONIQ_SPEED_SAMPLE", String(decoding: json, as: UTF8.self))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "measured-speed-\(index)-\(mode)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        if (play.value as? String) == "playing" { play.tap() }
        let data = try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
        let report = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        report.name = "measured-playback-rates-normal-rotation.json"
        report.lifetime = .keepAlways
        add(report)

        // Collect every mode before reporting failures, including the return to
        // hour mode. Loose ratio floors tolerate a busy simulator but reject
        // identical effective speeds or a fast-mode packet stream that sticks.
        for index in modes.indices {
            XCTAssertTrue(selectedStates[index], "Mode \(index) \(modes[index]) was not selected")
            XCTAssertTrue(playingStates[index], "Switching to \(modes[index]) stopped playback")
            XCTAssertTrue(monotonicStates[index], "Switching to \(modes[index]) reset or stalled the displayed clock")
            XCTAssertGreaterThan(rates[index], 0, "No actual progress for \(modes[index])")
        }
        XCTAssertGreaterThan(rates[1], rates[0] * 3, "Day should be visibly faster than hour")
        XCTAssertGreaterThan(rates[2], rates[1] * 3, "Month should be visibly faster than day")
        XCTAssertGreaterThan(rates[3], rates[2] * 1.6, "Year should be visibly faster than month")
        XCTAssertGreaterThan(rates[4], rates[3] * 1.2, "Dayun and year must not collapse to the same effective speed")
        XCTAssertGreaterThan(rates[5], rates[0] * 0.4, "Returning to hour mode must keep progressing")
        XCTAssertLessThan(rates[5], rates[0] * 2.5, "Returning to hour mode must restore its slow cadence")
        XCTAssertLessThan(rates[5], rates[4] / 20, "The final hour selection must slow the real clock, not only the button")
    }

    private func dateChangedPredicate(_ old: String) -> NSPredicate {
        NSPredicate { object, _ in ((object as? XCUIElement)?.value as? String) != old }
    }
}
