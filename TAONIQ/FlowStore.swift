import Foundation
import Observation

/// Owns the displayed frame. A computed future frame is never shown while paused.
@MainActor @Observable final class FlowStore {
    private(set) var input: BirthInput
    private(set) var natal: [Double] = []
    private(set) var flow: [Double] = []
    private(set) var frame: OrbitFrame?
    private(set) var frameID = 0
    private(set) var isLoading = false
    private(set) var isPlaying = false
    private(set) var isDemo: Bool
    private(set) var errorMessage: String?

    let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
    let disableRotation = ProcessInfo.processInfo.arguments.contains("--disable-rotation")
    private let storageKey = "TAONIQ.birth.v1"
    private var engine = OrbitEngine()
    private var generation = 0
    private var sessionStarted = false
    private var buffered: OrbitFrame?
    private var generationTask: Task<Void, Never>?
    private var playTask: Task<Void, Never>?
    private var hasLoaded = false

    init() {
        if !ProcessInfo.processInfo.arguments.contains("--uitesting"),
           let data = UserDefaults.standard.data(forKey: "TAONIQ.birth.v1"),
           let saved = try? JSONDecoder().decode(BirthInput.self, from: data) {
            input = saved
            isDemo = false
        } else {
            input = .demo
            isDemo = true
        }
    }

    var progress: Double {
        guard let frame, frame.nowMs > frame.birthMs else { return 0 }
        return min(1, max(0, (frame.epochMs - frame.birthMs) / (frame.nowMs - frame.birthMs)))
    }

    var reachedPresent: Bool { frame.map { $0.epochMs >= $0.nowMs } ?? false }

    var status: String {
        if isLoading { return "正在生成轨迹" }
        if errorMessage != nil { return "请重新输入生辰" }
        if reachedPresent { return "已演化至今" }
        if isPlaying { return "流盘正在连续演化" }
        if sessionStarted { return "已暂停 · 可从此刻继续" }
        return "生辰为核，时间成流"
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        generate(input, userSubmitted: false)
    }

    func generate(_ birth: BirthInput, userSubmitted: Bool = true, playWhenReady: Bool = false) {
        generation += 1
        let request = generation
        isPlaying = false
        playTask?.cancel()
        generationTask?.cancel()
        playTask = nil
        engine.invalidate()
        engine = OrbitEngine()
        let currentEngine = engine
        isLoading = true
        errorMessage = nil
        buffered = nil
        sessionStarted = false
        frame = nil
        natal = []
        flow = []
        frameID += 1
        generationTask = Task { [weak self] in
            do {
                let result = try await currentEngine.generate(birth)
                guard let self, request == self.generation, !Task.isCancelled else { return }
                self.input = birth
                self.isDemo = userSubmitted ? false : self.isDemo
                self.accept(result)
                self.isLoading = false
                if userSubmitted, !self.testing,
                   let data = try? JSONEncoder().encode(birth) {
                    UserDefaults.standard.set(data, forKey: self.storageKey)
                }
                if playWhenReady { self.play() }
            } catch {
                guard let self, request == self.generation, !Task.isCancelled else { return }
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard !isLoading, frame != nil, errorMessage == nil else { return }
        if reachedPresent {
            generate(input, userSubmitted: !isDemo, playWhenReady: true)
            return
        }
        isPlaying = true
        guard playTask == nil else { return }
        let request = generation
        let currentEngine = engine
        playTask = Task { [weak self] in
            guard let self else { return }
            defer { if request == self.generation { self.playTask = nil } }
            do {
                if !self.sessionStarted {
                    let first = try await currentEngine.startContinuous()
                    guard request == self.generation, !Task.isCancelled else { return }
                    self.sessionStarted = true
                    if self.isPlaying { self.accept(first) } else { self.buffered = first }
                }
                while self.isPlaying, request == self.generation, !Task.isCancelled {
                    let began = ContinuousClock.now
                    let next: OrbitFrame
                    if let prefetched = self.buffered {
                        next = prefetched
                    } else {
                        guard let displayed = self.frame else { return }
                        let remaining = displayed.nowMs - displayed.epochMs
                        guard remaining > 0 else { self.pause(); return }
                        // 7 calendar days / wall second; every frame covers .32 model units.
                        next = try await currentEngine.advance(civilMilliseconds: min(24_192_000, remaining))
                    }
                    guard request == self.generation, !Task.isCancelled else { return }
                    self.buffered = next
                    let elapsed = began.duration(to: .now)
                    if elapsed < .milliseconds(40) {
                        try await Task.sleep(for: .milliseconds(40) - elapsed)
                    }
                    guard request == self.generation, !Task.isCancelled else { return }
                    guard self.isPlaying else { return }
                    self.buffered = nil
                    self.accept(next)
                    if self.reachedPresent { self.pause() }
                }
            } catch {
                guard request == self.generation, !Task.isCancelled else { return }
                self.isPlaying = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func pause() {
        // Let an in-flight calculation finish into `buffered`; do not change the screen.
        isPlaying = false
    }

    private func accept(_ next: OrbitFrame) {
        if natal.isEmpty, let seed = next.natal { natal = seed }
        flow = next.flow
        frame = next
        frameID += 1
    }
}
