import XCTest

final class TAONIQFullscreenUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testBothPlotEntrancesShareFullscreenCameraAndPreservePausedBirth() throws {
        let app = launchReady(disableRotation: true)
        let originalEpoch = try epoch(app, "flowDate")
        let originalBirth = birthPillars(app).label
        let originalCamera = try camera(plot(app, "natalOrbit"))

        plot(app, "natalOrbit").tap()
        waitForFullscreen(app)
        let natal = plot(app, "fullscreenNatalOrbit")
        let flow = plot(app, "fullscreenFlowOrbit")
        assertVerticalPair(natal, flow)
        XCTAssertEqual(try camera(natal), originalCamera)
        XCTAssertEqual(try camera(flow), originalCamera)
        XCTAssertEqual(try epoch(app, "fullscreenFlowDate"), originalEpoch)
        XCTAssertEqual(app.buttons["playPauseButton"].value as? String, "paused")

        natal.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.55))
            .press(forDuration: 0.15, thenDragTo: natal.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.62)))
        let dragged = try camera(natal)
        XCTAssertNotEqual(dragged, originalCamera, "Dragging the upper plot must turn the shared camera")
        XCTAssertEqual(try camera(flow), dragged)

        flow.pinch(withScale: 0.65, velocity: -1)
        let zoomedOut = try camera(flow)
        XCTAssertLessThan(zoomedOut.zoom, dragged.zoom)
        natal.pinch(withScale: 1.35, velocity: 1)
        let pinched = try camera(flow)
        XCTAssertGreaterThan(pinched.zoom, zoomedOut.zoom, "Spreading fingers on the upper plot must enlarge both plots")
        XCTAssertNotEqual(pinched.zoom, dragged.zoom, "Pinching the lower plot must change the actual shared zoom")
        XCTAssertEqual(pinched.azimuth, dragged.azimuth, accuracy: 1)
        XCTAssertEqual(pinched.elevation, dragged.elevation, accuracy: 1)
        XCTAssertEqual(try camera(natal), pinched)
        waitWallClock(0.7)
        XCTAssertEqual(try epoch(app, "fullscreenFlowDate"), originalEpoch,
                       "Camera gestures and an open fullscreen view must not advance a paused civil clock")
        XCTAssertEqual(try camera(natal), pinched)
        attachScreenshot(app, name: "TAONIQ-fullscreen-shared-camera")

        returnHome(app)
        XCTAssertEqual(try camera(plot(app, "natalOrbit")), pinched)
        XCTAssertEqual(try camera(plot(app, "flowOrbit")), pinched)
        XCTAssertEqual(try epoch(app, "flowDate"), originalEpoch)
        XCTAssertEqual(birthPillars(app).label, originalBirth)

        // Exercise the second native plot entrance, not only a separate button.
        plot(app, "flowOrbit").tap()
        waitForFullscreen(app)
        assertVerticalPair(plot(app, "fullscreenNatalOrbit"), plot(app, "fullscreenFlowOrbit"))
        XCTAssertEqual(try camera(plot(app, "fullscreenNatalOrbit")), pinched)
        XCTAssertEqual(try camera(plot(app, "fullscreenFlowOrbit")), pinched)
        XCTAssertEqual(try epoch(app, "fullscreenFlowDate"), originalEpoch)
        plot(app, "fullscreenFlowOrbit").doubleTap()
        XCTAssertEqual(try camera(plot(app, "fullscreenNatalOrbit")), originalCamera,
                       "Double tap resets the camera without opening another fullscreen view")
        XCTAssertEqual(try camera(plot(app, "fullscreenFlowOrbit")), originalCamera)
        returnHome(app)
        XCTAssertEqual(birthPillars(app).label, originalBirth)
        XCTAssertEqual(try epoch(app, "flowDate"), originalEpoch)
    }

    @MainActor
    func testFullscreenRotatesAndKeepsThePlayingSessionAcrossPresentation() throws {
        let app = launchReady(disableRotation: false)
        let originalEpoch = try epoch(app, "flowDate")
        let originalBirth = birthPillars(app).label
        plot(app, "natalOrbit").tap()
        waitForFullscreen(app)
        let natal = plot(app, "fullscreenNatalOrbit")
        let firstCamera = natal.value as? String
        expectation(for: NSPredicate { _, _ in (natal.value as? String) != firstCamera }, evaluatedWith: natal)
        waitForExpectations(timeout: 6)
        XCTAssertEqual(try epoch(app, "fullscreenFlowDate"), originalEpoch,
                       "Normal automatic rotation must continue independently of the paused flow")
        XCTAssertEqual(app.buttons["playPauseButton"].value as? String, "paused")
        returnHome(app)

        app.buttons["speed-hour"].tap()
        app.buttons["playPauseButton"].tap()
        waitForEpoch(app, "flowDate", greaterThan: originalEpoch)
        let beforeEntryWall = ProcessInfo.processInfo.systemUptime
        let beforeEntry = try epoch(app, "flowDate")
        plot(app, "flowOrbit").tap()
        waitForFullscreen(app)
        XCTAssertEqual(app.buttons["playPauseButton"].value as? String, "playing",
                       "Presenting fullscreen must not pause the existing session")
        XCTAssertEqual(app.buttons["speed-hour"].value as? String, "selected")
        XCTAssertTrue(app.staticTexts["playbackDate"].exists)
        let afterEntry = try epoch(app, "fullscreenFlowDate")
        assertContinuousHourClock(from: beforeEntry, to: afterEntry, since: beforeEntryWall)
        waitForEpoch(app, "fullscreenFlowDate", greaterThan: afterEntry)
        let fullScreenProgress = try epoch(app, "fullscreenFlowDate")
        XCTAssertGreaterThan(fullScreenProgress, beforeEntry)
        attachScreenshot(app, name: "TAONIQ-fullscreen-live-evolution")

        let beforeReturnWall = ProcessInfo.processInfo.systemUptime
        let beforeReturn = try epoch(app, "fullscreenFlowDate")
        returnHome(app)
        XCTAssertEqual(app.buttons["playPauseButton"].value as? String, "playing",
                       "Returning home must keep the same running flow")
        XCTAssertEqual(app.buttons["speed-hour"].value as? String, "selected")
        let afterReturn = try epoch(app, "flowDate")
        assertContinuousHourClock(from: beforeReturn, to: afterReturn, since: beforeReturnWall)
        waitForEpoch(app, "flowDate", greaterThan: afterReturn)
        app.buttons["playPauseButton"].tap()
        XCTAssertEqual(birthPillars(app).label, originalBirth)
        let paused = try epoch(app, "flowDate")
        waitWallClock(0.7)
        XCTAssertEqual(try epoch(app, "flowDate"), paused)
    }

    private struct Camera: Equatable {
        let azimuth: Double
        let elevation: Double
        let zoom: Double
    }

    @MainActor
    private func launchReady(disableRotation: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"] + (disableRotation ? ["--disable-rotation"] : [])
        app.launch()
        let play = app.buttons["playPauseButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: play)
        waitForExpectations(timeout: 45)
        XCTAssertTrue(plot(app, "natalOrbit").isHittable)
        return app
    }

    @MainActor
    private func waitForFullscreen(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["returnHomeButton"].waitForExistence(timeout: 8))
        XCTAssertTrue(plot(app, "fullscreenNatalOrbit").waitForExistence(timeout: 5))
        XCTAssertTrue(plot(app, "fullscreenFlowOrbit").isHittable)
        XCTAssertTrue(app.staticTexts["fullscreenFlowDate"].exists)
    }

    @MainActor
    private func returnHome(_ app: XCUIApplication) {
        app.buttons["returnHomeButton"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["returnHomeButton"])
        waitForExpectations(timeout: 8)
        XCTAssertTrue(plot(app, "natalOrbit").isHittable)
        XCTAssertFalse(plot(app, "fullscreenNatalOrbit").exists)
    }

    @MainActor
    private func plot(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func birthPillars(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@",
                                            "birthPillars", "年柱", "时柱")).firstMatch
    }

    @MainActor
    private func epoch(_ app: XCUIApplication, _ identifier: String) throws -> Int64 {
        try XCTUnwrap(Int64(app.descendants(matching: .any)[identifier].value as? String ?? ""),
                      "\(identifier) must expose the accepted civil epoch in milliseconds")
    }

    @MainActor
    private func camera(_ plot: XCUIElement) throws -> Camera {
        let value = try XCTUnwrap(plot.value as? String)
        func number(after label: String) throws -> Double {
            let expression = try NSRegularExpression(pattern: label + #"\s*(-?[0-9]+(?:\.[0-9]+)?)"#)
            let match = try XCTUnwrap(expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                                     "Camera accessibility value must expose \(label): \(value)")
            let range = try XCTUnwrap(Range(match.range(at: 1), in: value))
            return try XCTUnwrap(Double(value[range]))
        }
        return try Camera(azimuth: number(after: "视角"), elevation: number(after: "仰角"), zoom: number(after: "缩放"))
    }

    @MainActor
    private func assertVerticalPair(_ natal: XCUIElement, _ flow: XCUIElement) {
        let upper = natal.frame, lower = flow.frame
        XCTAssertGreaterThan(upper.width, 100)
        XCTAssertGreaterThan(upper.height, 100)
        XCTAssertGreaterThan(lower.height, 100)
        XCTAssertLessThanOrEqual(upper.maxY, lower.minY + 1, "The birth core must sit above, without overlapping the flow")
        XCTAssertEqual(upper.midX, lower.midX, accuracy: 2)
        XCTAssertEqual(upper.width, lower.width, accuracy: 2)
    }

    @MainActor
    private func waitForEpoch(_ app: XCUIApplication, _ identifier: String, greaterThan epoch: Int64) {
        let date = app.descendants(matching: .any)[identifier]
        expectation(for: NSPredicate { _, _ in (Int64(date.value as? String ?? "") ?? Int64.min) > epoch }, evaluatedWith: date)
        waitForExpectations(timeout: 15)
    }

    private func assertContinuousHourClock(from start: Int64, to end: Int64, since wallStart: TimeInterval) {
        XCTAssertGreaterThanOrEqual(end, start, "Changing presentation must not reset the simulation to birth")
        // Hour mode advances 1,800,000 civil milliseconds per wall second.
        // Allow query/animation jitter, but reject rebuilding at a distant date.
        let wall = ProcessInfo.processInfo.systemUptime - wallStart
        XCTAssertLessThanOrEqual(Double(end - start), (wall + 3) * 1_800_000 * 2,
                                 "Presentation alone must not jump to another simulation date")
    }

    @MainActor
    private func waitWallClock(_ seconds: TimeInterval) {
        let waited = expectation(description: "Observe the native fullscreen state")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { waited.fulfill() }
        waitForExpectations(timeout: seconds + 5)
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
