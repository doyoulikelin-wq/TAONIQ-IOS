import Foundation

struct BirthInput: Codable, Equatable, Sendable {
    var birth: String
    var gender: String

    static let demo = BirthInput(birth: "1975-08-27T04:00:00", gender: "male")
}

struct DayunPeriod: Codable, Equatable, Identifiable, Sendable {
    let step: Int
    let pillar: String
    let startMs: Double
    let endMs: Double

    var id: Int { step }
}

struct OrbitFrame: Decodable, Sendable {
    let natal: [Double]?
    let flow: [Double]
    let birthPillars: [String]
    let flowPillars: [String]
    let dayun: String
    let dayunPeriods: [DayunPeriod]
    let epochMs: Double
    let birthMs: Double
    let nowMs: Double
    let seedPointsRemaining: Int
    let profileLabel: String
    let mode: String

    var date: Date { Date(timeIntervalSince1970: epochMs / 1_000) }
}

enum OrbitEngineError: LocalizedError, Sendable {
    case unavailable(String)
    case invalidResponse
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .invalidResponse: return "轨迹计算返回无效数据，请重新生成。"
        case .cancelled: return "本次计算已取消。"
        }
    }
}
