import SwiftUI

struct HomeView: View {
    @Bindable var store: FlowStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingBirth = false

    var body: some View {
        GeometryReader { geometry in
        ZStack {
            TaoTheme.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    orbitSection
                    information
                    TimeControlsView(store: store)
                    if let error = store.errorMessage {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("暂时未能生成", systemImage: "exclamationmark.circle")
                                .font(.subheadline.weight(.medium))
                            Text(error).font(.footnote).foregroundStyle(TaoTheme.muted)
                            Button("重新输入生辰") { showingBirth = true }
                                .font(.subheadline.weight(.semibold)).padding(.vertical, 8)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TaoTheme.line))
                    }
                    Text("历法与动力学的可视化实验 · 不作命运预测")
                        .font(.system(size: 10)).foregroundStyle(TaoTheme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .top) {
            // Keep scrolled content out of the system status area on every device.
            TaoTheme.paper
                .frame(height: geometry.safeAreaInsets.top)
                .offset(y: -geometry.safeAreaInsets.top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        }
        .foregroundStyle(TaoTheme.ink)
        .safeAreaInset(edge: .bottom, spacing: 0) { playbackBar }
        .sheet(isPresented: $showingBirth) {
            BirthSheet(input: store.input) { birth in store.generate(birth) }
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .task { store.loadIfNeeded() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { store.pause() } }
        .onChange(of: reduceMotion) { _, reduced in if reduced { store.pause() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack(spacing: 9) {
                    TaijiMark(size: 25)
                    Text("TAONIQ").font(.system(size: 12, weight: .medium, design: .monospaced)).tracking(4)
                }
                Spacer()
                Button {
                    store.pause()
                    showingBirth = true
                } label: {
                    HStack(spacing: 6) {
                        Text("生辰")
                        Image(systemName: "slider.horizontal.3").font(.system(size: 11))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 15).frame(minHeight: 44)
                    .overlay(Capsule().stroke(TaoTheme.line))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("birthButton")
                .accessibilityLabel("输入生辰")
            }
            HStack(alignment: .lastTextBaseline) {
                Text("智道").font(.system(size: 38, weight: .regular, design: .serif)).tracking(6)
                Spacer()
                Text("一核 · 一流").font(.system(size: 11)).tracking(3).foregroundStyle(TaoTheme.muted)
            }
        }
    }

    private var orbitSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                orbitTitle(number: "01", name: "生辰核", subtitle: "本始不移")
                orbitTitle(number: "02", name: "流盘", subtitle: "随时而生")
            }
            ZStack {
                OrbitStage(natal: store.natal, flow: store.flow, frameID: store.frameID,
                           isActive: scenePhase == .active && !showingBirth && !store.disableRotation,
                           reduceMotion: reduceMotion)
                    .accessibilityIdentifier("orbitStage")
                if store.isLoading || store.isSeeking {
                    HStack(spacing: 10) {
                        ProgressView().tint(TaoTheme.ink)
                        Text(store.isSeeking ? "正在定位流盘" : "正在生成轨迹").font(.footnote)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 13)
                    .background(TaoTheme.paper, in: Capsule())
                }
            }
            .frame(height: 280)
            HStack {
                Text("拖动转向 · 双指缩放").font(.system(size: 10))
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(TaoTheme.ink.opacity(store.isPlaying ? 1 : 0.3)).frame(width: 4, height: 4)
                    Text(store.isPlaying ? "时间流动中" : reduceMotion ? "拖动观察" : "两图同步旋转")
                }.font(.system(size: 10))
            }
            .foregroundStyle(TaoTheme.muted)
        }
    }

    private func orbitTitle(number: String, name: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(number).font(.system(size: 9, design: .monospaced)).foregroundStyle(TaoTheme.muted)
            Text(name).font(.system(size: 15, weight: .medium))
            Spacer(minLength: 2)
            Text(subtitle).font(.system(size: 9)).foregroundStyle(TaoTheme.muted)
        }.frame(maxWidth: .infinity)
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 19) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("生辰").font(.system(size: 12, weight: .semibold))
                    if store.isDemo { Text("示例").font(.system(size: 9)).padding(.horizontal, 6).padding(.vertical, 3).overlay(Capsule().stroke(TaoTheme.line)) }
                    Spacer()
                    Text(birthDescription).font(.system(size: 10, design: .monospaced)).foregroundStyle(TaoTheme.muted)
                }
                pillarRow(names: ["年柱", "月柱", "日柱", "时柱"], values: store.frame?.birthPillars ?? [])
                    .accessibilityIdentifier("birthPillars")
                    .accessibilityElement(children: .combine)
            }
            Rectangle().fill(TaoTheme.line).frame(height: 0.5)
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    Text("流盘").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(store.frame.map { TaoTheme.format($0.date) } ?? "—")
                        .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(TaoTheme.muted)
                        .accessibilityIdentifier("flowDate")
                        .accessibilityValue(store.frame.map { String(Int64($0.epochMs)) } ?? "0")
                }
                pillarRow(names: ["大运", "流年", "流月", "流日", "流时"],
                          values: store.frame.map { [$0.dayun] + $0.flowPillars } ?? [])
                    .accessibilityIdentifier("flowPillars")
                    .accessibilityElement(children: .combine)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(TaoTheme.ink.opacity(0.07))
                        Capsule().fill(TaoTheme.ink.opacity(0.65)).frame(width: max(3, geometry.size.width * store.progress))
                    }
                }.frame(height: 2).accessibilityHidden(true)
                HStack {
                    Text("出生")
                    Spacer()
                    Text("至今")
                }.font(.system(size: 9)).foregroundStyle(TaoTheme.muted)
            }
            if let frame = store.frame, frame.profileLabel.contains("未校准") {
                Text("当前为基础映射预览").font(.system(size: 10)).foregroundStyle(TaoTheme.muted)
            }
        }
    }

    private func pillarRow(names: [String], values: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                VStack(spacing: 6) {
                    Text(name).font(.system(size: 9)).foregroundStyle(TaoTheme.muted)
                    Text(index < values.count ? values[index] : "—")
                        .font(.system(size: values.count > index && values[index].count > 2 ? 15 : 20, weight: .regular, design: .serif))
                        .lineLimit(1).minimumScaleFactor(0.75)
                }.frame(maxWidth: .infinity)
            }
        }
    }

    private var birthDescription: String {
        guard let date = TaoTheme.parse(store.input.birth) else { return "—" }
        return TaoTheme.format(date) + (store.input.gender == "male" ? " · 男" : " · 女")
    }

    private var playbackBar: some View {
        VStack(spacing: 10) {
            Rectangle().fill(TaoTheme.line).frame(height: 0.5)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.status).font(.system(size: 12, weight: .medium))
                        .accessibilityIdentifier("loadingStatus")
                    Text(store.speed.detail)
                        .font(.system(size: 9)).foregroundStyle(TaoTheme.muted)
                }
                Spacer(minLength: 2)
                Button { store.togglePlayback() } label: {
                    HStack(spacing: 9) {
                        Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11))
                        Text(store.isPlaying ? "暂停" : store.reachedPresent ? "重新演化" : "演化")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(TaoTheme.paper)
                    .frame(width: 106, height: 48)
                    .background(TaoTheme.ink.opacity(store.isLoading || store.frame == nil ? 0.3 : 1), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.isLoading || store.isSeeking || store.frame == nil || store.errorMessage != nil || reduceMotion)
                .accessibilityIdentifier("playPauseButton")
                .accessibilityLabel(store.isPlaying ? "暂停演化" : "播放流盘演化")
                .accessibilityValue(store.isPlaying ? "playing" : "paused")
            }
            .padding(.horizontal, 22).padding(.bottom, 10)
            if reduceMotion {
                Text("系统已开启减少动态效果，自动旋转与演化已暂停。")
                    .font(.caption2).foregroundStyle(TaoTheme.muted).padding(.horizontal, 22).padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .background(TaoTheme.paper)
    }
}
