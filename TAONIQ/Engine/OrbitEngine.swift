import Foundation
import JavaScriptCore

/// A single JavaScriptCore VM, confined to one serial queue. Numerical work never
/// runs on the main thread; the existing web equations and calendar are unchanged.
final class OrbitEngine: @unchecked Sendable {
    private struct Response: Decodable {
        let id: Int
        let ok: Bool
        let frame: FrameMetadata?
        let error: String?
    }

    private struct FrameMetadata: Decodable {
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
    }

    private struct GenerationRequest: Encodable {
        let input: BirthInput
        let epochMs: Double?
    }

    private let queue = DispatchQueue(label: "app.taoniq.engine", qos: .userInitiated)
    private let resourceDirectory: URL?
    private var context: JSContext?
    private var pending: [Int: CheckedContinuation<OrbitFrame, Error>] = [:]
    private var nextID = 0

    init(resourceDirectory: URL? = nil) {
        self.resourceDirectory = resourceDirectory
    }

    func generate(_ input: BirthInput, at epochMs: Double? = nil) async throws -> OrbitFrame {
        if let epochMs, !epochMs.isFinite || epochMs.rounded() != epochMs {
            invalidate()
            throw OrbitEngineError.unavailable("观测时间必须是有效的整数毫秒。")
        }
        let data = try JSONEncoder().encode(GenerationRequest(input: input, epochMs: epochMs))
        return try await request("generate", payload: String(decoding: data, as: UTF8.self), replacesSession: true)
    }

    func startContinuous() async throws -> OrbitFrame {
        try await request("start", payload: "{}")
    }

    func advance(civilMilliseconds: Double) async throws -> OrbitFrame {
        guard civilMilliseconds.isFinite, civilMilliseconds > 0,
              civilMilliseconds.rounded() == civilMilliseconds else {
            throw OrbitEngineError.unavailable("演化时间必须是正整数毫秒。")
        }
        return try await request("advance", payload: "{\"civilMilliseconds\":\(civilMilliseconds)}")
    }

    /// Call before discarding a session or replacing its birth input. Late
    /// callbacks are ignored and all outstanding Swift continuations are resumed.
    func invalidate() {
        queue.async { [self] in invalidateOnQueue() }
    }

    private func request(_ operation: String, payload: String, replacesSession: Bool = false) async throws -> OrbitFrame {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try prepareContext()
                    if replacesSession { invalidateOnQueue() }
                    nextID += 1
                    let id = nextID
                    pending[id] = continuation
                    context?.exception = nil
                    context?.evaluateScript("TaoNative.request(\(id), '\(operation)', \(payload));")
                    if let exception = context?.exception {
                        finishFailure(id, message: exception.toString())
                        context?.exception = nil
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func resource(named name: String) throws -> String {
        let url: URL?
        if let resourceDirectory { url = resourceDirectory.appendingPathComponent(name) }
        else {
            url = Bundle.main.url(forResource: name, withExtension: nil)
                ?? Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Resources")
        }
        guard let url else { throw OrbitEngineError.unavailable("未找到本地算法资源：\(name)") }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func prepareContext() throws {
        dispatchPrecondition(condition: .onQueue(queue))
        if context != nil { return }
        guard let created = JSContext() else { throw OrbitEngineError.unavailable("无法创建本地计算引擎。") }
        let result: @convention(block) (String, JSValue, JSValue) -> Void = { [weak self] json, flow, natal in
            self?.receive(json, flow: flow, natal: natal)
        }
        let schedule: @convention(block) (JSValue, Double) -> Void = { [weak self] callback, milliseconds in
            guard let self else { return }
            let delay = milliseconds.isFinite ? max(0, min(milliseconds, 60_000)) / 1_000 : 0
            self.queue.asyncAfter(deadline: .now() + delay) { [weak self, callback] in
                guard let self, let context = self.context else { return }
                context.exception = nil
                callback.call(withArguments: [])
                if let error = context.exception {
                    self.failAll(message: error.toString())
                    context.exception = nil
                }
            }
        }
        created.setObject(result, forKeyedSubscript: "nativeResult" as NSString)
        created.setObject(schedule, forKeyedSubscript: "nativeSchedule" as NSString)
        created.evaluateScript("globalThis.setTimeout = function(callback, ms) { nativeSchedule(callback, ms || 0); return 0; };")
        do {
            let model = try resource(named: "taoniq-engine.js")
            let bridge = try resource(named: "native-bridge.js")
            created.evaluateScript(model, withSourceURL: URL(string: "taoniq-local://engine"))
            if let error = created.exception { throw OrbitEngineError.unavailable(error.toString()) }
            created.evaluateScript(bridge, withSourceURL: URL(string: "taoniq-local://bridge"))
            if let error = created.exception { throw OrbitEngineError.unavailable(error.toString()) }
            context = created
        } catch { throw error }
    }

    /// Copy the original Float64Array buffer while still inside its JS callback.
    /// No JSValue or borrowed memory ever crosses the engine queue boundary.
    private func copyPoints(_ value: JSValue) throws -> [Double]? {
        if value.isNull || value.isUndefined { return nil }
        guard let context else { throw OrbitEngineError.invalidResponse }
        let ctx = context.jsGlobalContextRef
        var exception: JSValueRef?
        guard let object = JSValueToObject(ctx, value.jsValueRef, &exception), exception == nil,
              JSValueGetTypedArrayType(ctx, value.jsValueRef, &exception) == kJSTypedArrayTypeFloat64Array,
              exception == nil else { throw OrbitEngineError.invalidResponse }
        let count = JSObjectGetTypedArrayLength(ctx, object, &exception)
        guard exception == nil, count >= 6, count % 3 == 0,
              let bytes = JSObjectGetTypedArrayBytesPtr(ctx, object, &exception), exception == nil else {
            throw OrbitEngineError.invalidResponse
        }
        let copy = Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: Double.self), count: count))
        guard copy.allSatisfy(\.isFinite) else { throw OrbitEngineError.invalidResponse }
        return copy
    }

    private func receive(_ json: String, flow: JSValue, natal: JSValue) {
        dispatchPrecondition(condition: .onQueue(queue))
        do {
            let response = try JSONDecoder().decode(Response.self, from: Data(json.utf8))
            guard pending[response.id] != nil else { return }
            if response.ok, let metadata = response.frame, let flowPoints = try copyPoints(flow) {
                let natalPoints = try copyPoints(natal)
                let frame = OrbitFrame(natal: natalPoints, flow: flowPoints,
                    birthPillars: metadata.birthPillars, flowPillars: metadata.flowPillars,
                    dayun: metadata.dayun, dayunPeriods: metadata.dayunPeriods,
                    epochMs: metadata.epochMs, birthMs: metadata.birthMs,
                    nowMs: metadata.nowMs, seedPointsRemaining: metadata.seedPointsRemaining,
                    profileLabel: metadata.profileLabel, mode: metadata.mode)
                guard let continuation = pending.removeValue(forKey: response.id) else { return }
                continuation.resume(returning: frame)
            } else {
                finishFailure(response.id, message: response.error ?? "轨迹数据无效。")
            }
        } catch { failAll(message: "无法读取本地轨迹结果：\(error.localizedDescription)") }
    }

    private func finishFailure(_ id: Int, message: String?) {
        pending.removeValue(forKey: id)?.resume(throwing: OrbitEngineError.unavailable(message ?? "本地计算失败。"))
    }

    private func failAll(message: String?) {
        let tasks = Array(pending.values)
        pending.removeAll()
        for continuation in tasks { continuation.resume(throwing: OrbitEngineError.unavailable(message ?? "本地计算失败。")) }
    }

    private func invalidateOnQueue() {
        dispatchPrecondition(condition: .onQueue(queue))
        let tasks = Array(pending.values)
        pending.removeAll()
        context?.evaluateScript("TaoNative.invalidate();")
        for continuation in tasks { continuation.resume(throwing: OrbitEngineError.cancelled) }
    }
}
