import XCTest
@testable import TAONIQ

final class PlaybackTests: XCTestCase {
    @MainActor
    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(predicate(), "The requested real engine state did not arrive")
    }

    private func epoch(_ value: String) -> Double {
        ISO8601DateFormatter().date(from: value)!.timeIntervalSince1970 * 1_000
    }

    func testCalendarSpeedsRespectLeapMonthsAndEngineBatchLimit() {
        let leapFebruary = epoch("2024-02-01T00:00:00+08:00")
        let normalFebruary = epoch("2023-02-01T00:00:00+08:00")
        XCTAssertEqual(EvolutionSpeed.month.civilMillisecondsPerFrame(at: leapFebruary), 12_528_000)
        XCTAssertEqual(EvolutionSpeed.month.civilMillisecondsPerFrame(at: normalFebruary), 12_096_000)
        let durations = EvolutionSpeed.allCases.map { $0.civilMillisecondsPerFrame(at: leapFebruary) }
        XCTAssertEqual(durations.sorted(by: >), durations)
        for duration in durations {
            XCTAssertEqual(duration, duration.rounded())
            XCTAssertGreaterThan(duration, 0)
            XCTAssertLessThanOrEqual(duration, 151_200_000)
        }
    }

    @MainActor
    func testChangingSpeedRetainsTheExactContinuousPathAndNatalBytes() async throws {
        let store = FlowStore()
        store.generate(.demo, userSubmitted: false)
        try await waitUntil { !store.isLoading && store.frame != nil }
        let seed = try XCTUnwrap(store.frame)
        let natal = store.natal
        store.setSpeed(.hour)
        store.play()
        try await waitUntil { (store.frame?.epochMs ?? 0) > seed.epochMs }
        let afterHour = try XCTUnwrap(store.frame).epochMs
        XCTAssertEqual(store.frame?.flow.count, 27_006, "Slow mode exposes a genuinely integrated off-grid head")
        store.setSpeed(.year)
        try await waitUntil { (store.frame?.epochMs ?? 0) > afterHour }
        let afterYear = try XCTUnwrap(store.frame).epochMs
        store.setSpeed(.dayun)
        try await waitUntil { (store.frame?.epochMs ?? 0) > afterYear }
        store.pause()
        let displayed = try XCTUnwrap(store.frame)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(store.frame?.epochMs, displayed.epochMs)
        XCTAssertEqual(store.natal, natal)
        XCTAssertFalse(store.isLoading, "Speed changes never create a frozen starting view")

        let reference = OrbitEngine()
        _ = try await reference.generate(.demo)
        var expected = try await reference.startContinuous()
        while expected.epochMs < displayed.epochMs {
            expected = try await reference.advance(civilMilliseconds: min(151_200_000, displayed.epochMs - expected.epochMs))
        }
        XCTAssertEqual(displayed.flow, expected.flow, "Changing display cadence may neither reset nor skip the canonical numerical path")
        XCTAssertNil(store.errorMessage)
        reference.invalidate()
    }

    @MainActor
    func testSeekUsesRealDayunStartPreservesNatalAndRejectsObsoleteResults() async throws {
        let store = FlowStore()
        store.generate(.demo, userSubmitted: false)
        try await waitUntil { !store.isLoading && store.frame != nil }
        let original = try XCTUnwrap(store.frame)
        let natal = store.natal
        let period = try XCTUnwrap(original.dayunPeriods.first { $0.step == 2 })
        store.seek(to: period.startMs)
        XCTAssertTrue(store.isSeeking)
        XCTAssertEqual(store.frame?.epochMs, original.epochMs, "Pending seeks keep the last accepted view")
        XCTAssertEqual(store.natal, natal)
        try await waitUntil { !store.isLoading && store.frame?.epochMs == period.startMs }
        XCTAssertEqual(store.frame?.dayun, period.pillar)
        XCTAssertEqual(store.frame?.mode, "frozen-seed")
        store.setSpeed(.hour)
        store.play()
        try await waitUntil { (store.frame?.epochMs ?? 0) > period.startMs }
        let firstSeek = epoch("2018-01-01T00:00:00+08:00")
        let finalSeek = epoch("2001-01-01T00:00:00+08:00")
        store.seek(to: firstSeek)
        store.seek(to: finalSeek)
        try await waitUntil { !store.isLoading && store.frame?.epochMs == finalSeek }
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.natal, natal)
        let finalFrame = try XCTUnwrap(store.frame)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(store.frame?.epochMs, finalSeek)
        XCTAssertEqual(store.flow, finalFrame.flow, "An obsolete seek or playback packet cannot replace the final chosen time")
        XCTAssertNil(store.errorMessage)
    }
}
