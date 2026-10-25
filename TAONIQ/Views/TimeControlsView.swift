import SwiftUI

/// Draft slider positions stay separate from the accepted, computed frame.
/// Only releasing a slider (or one accessibility adjustment) starts a seek.
struct TimeControlsView: View {
    @Bindable var store: FlowStore
    @State private var draftDayun = 0.0
    @State private var draftYear = 2000.0
    @State private var dragging: ScrubKind?
    @State private var pendingTarget: Double?

    private enum ScrubKind: Equatable { case dayun, year }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Rectangle().fill(TaoTheme.line).frame(height: 0.5)
            VStack(alignment: .leading, spacing: 10) {
                Text("演化速度").font(.system(size: 12, weight: .semibold))
                HStack(spacing: 3) {
                    ForEach(EvolutionSpeed.allCases) { speed in
                        let selected = store.speed == speed
                        Button { store.setSpeed(speed) } label: {
                            Text(speed.title)
                                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(selected ? TaoTheme.paper : TaoTheme.ink)
                                .background(selected ? TaoTheme.ink : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("speed-\(String(describing: speed))")
                        .accessibilityLabel("\(speed.title)尺度演化")
                        .accessibilityValue(selected ? "selected" : "unselected")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(3)
                .background(TaoTheme.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
                .disabled(store.isLoading || store.isSeeking)
                Text(store.speed.detail)
                    .font(.system(size: 10)).foregroundStyle(TaoTheme.muted)
                    .accessibilityIdentifier("speedDetail")
                Text("五层同时作用，速度只改变观看快慢。")
                    .font(.system(size: 10)).foregroundStyle(TaoTheme.muted)
            }
            if let frame = store.frame {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("定位时间").font(.system(size: 12, weight: .semibold))
                        Spacer()
                        if store.isSeeking { ProgressView().controlSize(.mini).tint(TaoTheme.ink) }
                    }
                    dayunControl(frame)
                    yearControl(frame)
                    Text(previewText(frame))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(dragging == nil && !store.isSeeking ? TaoTheme.muted : TaoTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("seekPreview")
                    Text("松手后定位，从所选时刻继续演化。生辰核保持固定。")
                        .font(.system(size: 10)).foregroundStyle(TaoTheme.muted)
                }
            }
        }
        .onAppear { synchronizeDrafts() }
        .onChange(of: store.frame?.epochMs) { _, _ in
            if dragging == nil && !store.isSeeking { pendingTarget = nil; synchronizeDrafts() }
        }
        .onChange(of: store.isSeeking) { _, seeking in
            if !seeking {
                dragging = nil
                pendingTarget = nil
                synchronizeDrafts()
            }
        }
        .onChange(of: store.isPlaying) { _, playing in
            if playing {
                dragging = nil
                pendingTarget = nil
                synchronizeDrafts()
            }
        }
        .onChange(of: store.frame?.birthMs) { _, _ in
            dragging = nil
            pendingTarget = nil
            synchronizeDrafts()
        }
    }

    private func dayunControl(_ frame: OrbitFrame) -> some View {
        let periods = frame.dayunPeriods
        let index = min(max(0, Int(draftDayun.rounded())), max(0, periods.count - 1))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("大运").font(.system(size: 12))
                Spacer()
                Text(periods.isEmpty ? "—" : periodTitle(periods[index]))
                    .font(.system(size: 12, weight: .medium))
                if !periods.isEmpty {
                    Text(yearRange(periods[index]))
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(TaoTheme.muted)
                }
            }
            Slider(value: Binding(get: { draftDayun }, set: { value in
                draftDayun = value
                if let target = target(for: .dayun) { draftYear = Double(year(target)) }
            }), in: 0...Double(max(1, periods.count - 1)), step: 1) { editing in
                edit(.dayun, active: editing)
            }
            .tint(TaoTheme.ink)
            .frame(minHeight: 44)
            .disabled(periods.count <= 1 || store.isLoading || store.isSeeking)
            .accessibilityIdentifier("dayunSlider")
            .accessibilityLabel("选择大运")
            .accessibilityValue(periods.isEmpty ? "无可选大运" : periodTitle(periods[index]) + "，起于 " + TaoTheme.format(Date(timeIntervalSince1970: periods[index].startMs / 1_000), pattern: "yyyy.MM.dd HH:mm:ss"))
            .accessibilityAdjustableAction { direction in
                store.pause()
                switch direction {
                case .increment: draftDayun = min(Double(max(0, periods.count - 1)), draftDayun + 1)
                case .decrement: draftDayun = max(0, draftDayun - 1)
                @unknown default: return
                }
                commit(.dayun)
            }
            HStack {
                Text(periods.first.map(periodTitle) ?? "出生")
                Spacer()
                Text(periods.last.map(periodTitle) ?? "至今")
            }.font(.system(size: 9)).foregroundStyle(TaoTheme.muted)
        }
    }

    private func yearControl(_ frame: OrbitFrame) -> some View {
        let first = year(frame.birthMs), last = year(frame.nowMs)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("年份").font(.system(size: 12))
                Spacer()
                Text("\(String(Int(draftYear.rounded())))年")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            Slider(value: Binding(get: { draftYear }, set: { value in
                draftYear = value
                if let target = target(for: .year) {
                    draftDayun = Double(frame.dayunPeriods.lastIndex { $0.startMs <= target } ?? 0)
                }
            }), in: Double(first)...Double(max(first + 1, last)), step: 1) { editing in
                edit(.year, active: editing)
            }
            .tint(TaoTheme.ink)
            .frame(minHeight: 44)
            .disabled(first >= last || store.isLoading || store.isSeeking)
            .accessibilityIdentifier("yearSlider")
            .accessibilityLabel("选择年份")
            .accessibilityValue(String(Int(draftYear.rounded())) + "年")
            .accessibilityAdjustableAction { direction in
                store.pause()
                switch direction {
                case .increment: draftYear = min(Double(last), draftYear + 1)
                case .decrement: draftYear = max(Double(first), draftYear - 1)
                @unknown default: return
                }
                commit(.year)
            }
            HStack {
                Text(String(first))
                Spacer()
                Text(String(last))
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(TaoTheme.muted)
        }
    }

    private func edit(_ kind: ScrubKind, active: Bool) {
        if active {
            guard !store.isLoading && !store.isSeeking else { return }
            store.pause()
            dragging = kind
            pendingTarget = nil
        } else {
            commit(kind)
        }
    }

    private func commit(_ kind: ScrubKind) {
        // Accessibility adjustment can be followed by a native editing callback.
        // Do not submit the same selection again while its seek is in flight.
        guard !store.isLoading && !store.isSeeking else { dragging = nil; return }
        guard let target = target(for: kind) else { dragging = nil; return }
        if let frame = store.frame {
            draftDayun = Double(frame.dayunPeriods.lastIndex { $0.startMs <= target } ?? 0)
            draftYear = Double(year(target))
        }
        dragging = nil
        pendingTarget = target
        store.seek(to: target)
    }

    private func target(for kind: ScrubKind) -> Double? {
        guard let frame = store.frame else { return nil }
        let value: Double
        switch kind {
        case .dayun:
            guard !frame.dayunPeriods.isEmpty else { return nil }
            let index = min(max(0, Int(draftDayun.rounded())), frame.dayunPeriods.count - 1)
            value = frame.dayunPeriods[index].startMs
        case .year:
            guard let date = TaoTheme.calendar.date(from: DateComponents(year: Int(draftYear.rounded()), month: 1, day: 1)) else { return nil }
            value = date.timeIntervalSince1970 * 1_000
        }
        return min(frame.nowMs, max(frame.birthMs, value))
    }

    private func synchronizeDrafts() {
        guard let frame = store.frame else { return }
        draftDayun = Double(frame.dayunPeriods.lastIndex { $0.startMs <= frame.epochMs } ?? 0)
        draftYear = Double(year(frame.epochMs))
    }

    private func previewText(_ frame: OrbitFrame) -> String {
        let target = dragging.flatMap { self.target(for: $0) } ?? pendingTarget ?? store.seekTargetMs ?? frame.epochMs
        let date = TaoTheme.format(Date(timeIntervalSince1970: target / 1_000), pattern: "yyyy.MM.dd  HH:mm:ss")
        if store.isSeeking { return "正在定位  \(date)" }
        if dragging != nil { return "待定位  \(date)" }
        return "当前  \(date)"
    }

    private func year(_ ms: Double) -> Int {
        TaoTheme.calendar.component(.year, from: Date(timeIntervalSince1970: ms / 1_000))
    }

    private func periodTitle(_ period: DayunPeriod) -> String {
        period.step == 0 ? "未起运" : "第 \(period.step) 运 · \(period.pillar)"
    }

    private func yearRange(_ period: DayunPeriod) -> String {
        "\(year(period.startMs))–\(year(period.endMs))"
    }
}
