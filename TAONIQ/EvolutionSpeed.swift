import Foundation

/// Changes viewing cadence only. All modes retain the same civil/model clock
/// and integrate every intermediate calendar boundary in the numerical engine.
enum EvolutionSpeed: String, CaseIterable, Identifiable, Sendable {
    case dayun, year, month, day, hour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dayun: return "大运"
        case .year: return "年"
        case .month: return "月"
        case .day: return "日"
        case .hour: return "时"
        }
    }

    var detail: String {
        switch self {
        case .dayun: return "约 1 运 / 100 秒 · 连续演化"
        case .year: return "约 1 年 / 20 秒 · 连续演化"
        case .month: return "约 1 月 / 8 秒 · 连续演化"
        case .day: return "1 日 / 4 秒 · 连续演化"
        case .hour: return "1 时辰 / 4 秒 · 连续演化"
        }
    }

    func civilMillisecondsPerFrame(at epochMs: Double) -> Double {
        guard epochMs.isFinite else { return 1 }
        let date = Date(timeIntervalSince1970: epochMs / 1_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let civilSeconds: Double
        let viewingSeconds: Double
        switch self {
        case .dayun:
            civilSeconds = calendar.date(byAdding: .year, value: 10, to: date)!.timeIntervalSince(date)
            viewingSeconds = 100
        case .year:
            civilSeconds = calendar.date(byAdding: .year, value: 1, to: date)!.timeIntervalSince(date)
            viewingSeconds = 20
        case .month:
            civilSeconds = calendar.date(byAdding: .month, value: 1, to: date)!.timeIntervalSince(date)
            viewingSeconds = 8
        case .day:
            civilSeconds = 86_400; viewingSeconds = 4
        case .hour:
            civilSeconds = 7_200; viewingSeconds = 4
        }
        // 40ms display cadence, bounded by the engine's two-model-unit packet.
        return max(1, min(151_200_000, (civilSeconds * 1_000 * 0.04 / viewingSeconds).rounded()))
    }
}
