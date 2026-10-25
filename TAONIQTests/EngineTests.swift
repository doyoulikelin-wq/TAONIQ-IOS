import XCTest
@testable import TAONIQ

final class EngineTests: XCTestCase {
    func testActualJavaScriptCoreBirthAndContinuousRollingTail() async throws {
        let engine = OrbitEngine()
        let seed = try await engine.generate(.demo)
        let natal = try XCTUnwrap(seed.natal)
        XCTAssertEqual(seed.birthPillars, ["乙卯", "甲申", "乙巳", "戊寅"])
        XCTAssertEqual(natal.count, 27_003)
        XCTAssertEqual(seed.flow.count, 27_003)
        XCTAssertEqual(seed.epochMs, seed.birthMs)
        XCTAssertEqual(seed.mode, "frozen-seed")
        XCTAssertTrue(natal.allSatisfy(\.isFinite))
        let beginning = try await engine.startContinuous()
        XCTAssertNil(beginning.natal)
        XCTAssertEqual(beginning.flow, seed.flow)
        let advanced = try await engine.advance(civilMilliseconds: 24_192_000)
        XCTAssertEqual(advanced.epochMs - beginning.epochMs, 24_192_000)
        XCTAssertEqual(advanced.seedPointsRemaining, 8_969)
        XCTAssertEqual(Array(advanced.flow.prefix((9_001 - 32) * 3)), Array(seed.flow.dropFirst(32 * 3)))
        XCTAssertNotEqual(Array(advanced.flow.suffix(3)), Array(seed.flow.suffix(3)))
        XCTAssertNil(advanced.natal)
        XCTAssertEqual(seed.natal, natal)
        XCTAssertEqual(advanced.mode, "continuous")
        XCTAssertTrue(advanced.flow.allSatisfy(\.isFinite))
        // start is idempotent: resuming cannot rewind the active numerical state.
        let resumed = try await engine.startContinuous()
        XCTAssertEqual(resumed.epochMs, advanced.epochMs)
        XCTAssertEqual(resumed.flow, advanced.flow)
        engine.invalidate()
    }

    func testSchedulingAndPartialPacketsPreserveTheSamePath() async throws {
        let whole = OrbitEngine(), split = OrbitEngine()
        async let a = whole.generate(.demo)
        async let b = split.generate(.demo)
        _ = try await (a, b)
        _ = try await whole.startContinuous()
        _ = try await split.startContinuous()
        let once = try await whole.advance(civilMilliseconds: 48_384_123)
        _ = try await split.advance(civilMilliseconds: 12_345)
        _ = try await split.advance(civilMilliseconds: 24_192_000)
        let many = try await split.advance(civilMilliseconds: 24_179_778)
        XCTAssertEqual(once.epochMs, many.epochMs)
        XCTAssertEqual(once.flow, many.flow)
        XCTAssertEqual(once.flow.count, 27_006) // actual, off-grid endpoint included
        whole.invalidate()
        split.invalidate()
    }

    func testInvalidInputDoesNotReuseAnOldChart() async throws {
        let engine = OrbitEngine()
        _ = try await engine.generate(.demo)
        do {
            _ = try await engine.generate(BirthInput(birth: "2001-02-29T08:00:00", gender: "male"))
            XCTFail("Impossible Gregorian date must fail")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        do {
            _ = try await engine.startContinuous()
            XCTFail("Invalid replacement must not keep the previous chart")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        do {
            _ = try await engine.advance(civilMilliseconds: .nan)
            XCTFail("NaN must be rejected before entering JavaScript")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        engine.invalidate()
    }

    func testInvalidatingAnInFlightGenerationResumesItsContinuation() async throws {
        let engine = OrbitEngine()
        let task = Task { try await engine.generate(.demo) }
        try await Task.sleep(nanoseconds: 20_000_000)
        engine.invalidate()
        do {
            _ = try await task.value
            XCTFail("Invalidated generation must be cancelled")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
    }

    func testNearNowTailEndsAtTheFixedGenerationHorizon() async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let engine = OrbitEngine()
        let birth = formatter.string(from: Date().addingTimeInterval(-2))
        let seed = try await engine.generate(BirthInput(birth: birth, gender: "male"))
        let first = try await engine.startContinuous()
        XCTAssertEqual(first.nowMs, seed.nowMs)
        let remaining = first.nowMs - first.epochMs
        XCTAssertGreaterThan(remaining, 0)
        XCTAssertLessThan(remaining, 151_200_000)
        let last = try await engine.advance(civilMilliseconds: remaining)
        XCTAssertEqual(last.epochMs, seed.nowMs)
        XCTAssertEqual(last.nowMs, seed.nowMs)
        XCTAssertTrue(last.flow.allSatisfy(\.isFinite))
        do {
            _ = try await engine.advance(civilMilliseconds: 1)
            XCTFail("The fixed viewing horizon must not move after wall-clock time passes")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        engine.invalidate()
    }
}
