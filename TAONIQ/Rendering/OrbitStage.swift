import SwiftUI
import SceneKit

/// Both plots share one perspective and world scale. Camera movement never
/// changes the integrated point arrays or advances the civil clock.
struct OrbitStage: UIViewRepresentable {
    let natal: [Double]
    let flow: [Double]
    let frameID: Int
    let isActive: Bool
    let reduceMotion: Bool
    let viewState: OrbitViewState
    var layout: OrbitLayout = .horizontal
    var onTap: (() -> Void)? = nil

    func makeUIView(context: Context) -> DualOrbitView {
        DualOrbitView(viewState: viewState, layout: layout, onTap: onTap)
    }

    func updateUIView(_ view: DualOrbitView, context: Context) {
        view.configure(viewState: viewState, layout: layout, onTap: onTap)
        view.update(natal: natal, flow: flow, revision: frameID)
        view.setMotion(active: isActive, reduced: reduceMotion)
    }

    static func dismantleUIView(_ uiView: DualOrbitView, coordinator: ()) {
        uiView.detach()
    }
}

enum OrbitGeometry {
    // A single shared projection; never normalize each plot separately.
    static let center = SIMD3<Double>(-0.3835333153547009, 0.0814441302050235, 0.981558454197919)
    static let radius: Double = 4.158928674224513

    struct Projection: Equatable {
        let center: SIMD3<Double>
        let radius: Double
        static let reference = Projection(center: OrbitGeometry.center, radius: OrbitGeometry.radius)
    }

    /// Fit the two seed clouds together once, then freeze the scale for the
    /// entire playback session. Later deformation does not change the camera.
    static func sharedProjection(natal: [Double], flow: [Double]) -> Projection {
        let clouds = [natal, flow]
        var lower = SIMD3<Double>(repeating: .infinity)
        var upper = SIMD3<Double>(repeating: -.infinity)
        for cloud in clouds where cloud.count % 3 == 0 {
            for i in stride(from: 0, to: cloud.count, by: 3) {
                for axis in 0..<3 where cloud[i + axis].isFinite {
                    lower[axis] = min(lower[axis], cloud[i + axis])
                    upper[axis] = max(upper[axis], cloud[i + axis])
                }
            }
        }
        guard lower.x.isFinite, upper.z.isFinite else { return .reference }
        let center = (lower + upper) / 2
        var radiusSquared = 0.0
        for cloud in clouds where cloud.count % 3 == 0 {
            for i in stride(from: 0, to: cloud.count, by: 3) {
                let point = SIMD3<Double>(cloud[i], cloud[i + 1], cloud[i + 2]) - center
                let square = point.x * point.x + point.y * point.y + point.z * point.z
                if square.isFinite { radiusSquared = max(radiusSquared, square) }
            }
        }
        // Keep genuinely tiny trajectories small rather than magnifying a
        // fixed point into a misleading large shape.
        return Projection(center: center, radius: max(0.65, sqrt(radiusSquared) * 1.08))
    }

    static func vertices(_ points: [Double], projection: Projection = .reference) -> [SCNVector3] {
        guard points.count % 3 == 0 else { return [] }
        return stride(from: 0, to: points.count, by: 3).map { i in
            SCNVector3(Float((points[i] - projection.center.x) / projection.radius),
                       Float((points[i + 1] - projection.center.y) / projection.radius),
                       Float((points[i + 2] - projection.center.z) / projection.radius))
        }
    }

    static func indices(_ points: [Double]) -> [UInt32] {
        guard points.count % 3 == 0, points.count >= 6 else { return [] }
        var result: [UInt32] = []
        result.reserveCapacity((points.count / 3 - 1) * 2)
        for i in 1 ..< points.count / 3 {
            let offset = (i - 1) * 3
            guard points[offset ..< offset + 6].allSatisfy(\.isFinite) else { continue }
            result.append(UInt32(i - 1)); result.append(UInt32(i))
        }
        return result
    }

    /// Keep a short, chronological tail visible over the full observation window.
    /// These are actual final samples, including the integrated off-grid head.
    static func recentPoints(_ points: [Double], count: Int = 160) -> [Double] {
        guard points.count >= 6, points.count % 3 == 0, count >= 2,
              points.allSatisfy(\.isFinite) else { return [] }
        return Array(points.suffix(min(count, points.count / 3) * 3))
    }

    static func make(_ points: [Double], dark: Bool, projection: Projection = .reference,
                     opacity: CGFloat? = nil) -> SCNGeometry? {
        guard points.count >= 6, points.allSatisfy(\.isFinite) else { return nil }
        let vertices = vertices(points, projection: projection)
        let indices = indices(points)
        guard !vertices.isEmpty, !indices.isEmpty else { return nil }
        let data = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(data: data, primitiveType: .line,
                                        primitiveCount: indices.count / 2,
                                        bytesPerIndex: MemoryLayout<UInt32>.size)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = dark ? UIColor(white: 0.98, alpha: opacity ?? 0.62) : UIColor(white: 0.08, alpha: opacity ?? 0.56)
        material.isDoubleSided = true
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = false
        material.blendMode = .alpha
        geometry.materials = [material]
        return geometry
    }
}

enum OrbitLayout: Sendable {
    case horizontal, vertical
}

/// Camera and seed scale belong to the screen's observation, not to a particular
/// UIView. Opening a second presentation cannot refit or reset the trajectory.
@MainActor final class OrbitViewState {
    struct Pose: Equatable {
        var azimuth: Float = -Float.pi * 0.4
        var elevation: Float = 0.31
        var distance: Float = 2.8
    }

    private final class WeakView {
        weak var value: DualOrbitView?
        init(_ value: DualOrbitView) { self.value = value }
    }

    private(set) var pose = Pose()
    private(set) var projection = OrbitGeometry.Projection.reference
    private(set) var projectionRevision = 0
    fileprivate var resumeRotationAt: CFTimeInterval = 0
    private var natalKey: [Double] = []
    private var observers: [WeakView] = []
    private weak var animationOwner: DualOrbitView?

    @discardableResult
    func prepareProjection(natal: [Double], flow: [Double]) -> OrbitGeometry.Projection {
        guard natal.count >= 6, flow.count >= 6,
              natal.count % 3 == 0, flow.count % 3 == 0,
              natal.allSatisfy(\.isFinite), flow.allSatisfy(\.isFinite), natal != natalKey else { return projection }
        natalKey = natal
        projection = OrbitGeometry.sharedProjection(natal: natal, flow: flow)
        projectionRevision += 1
        return projection
    }

    func setPose(_ proposed: Pose) {
        guard proposed.azimuth.isFinite, proposed.elevation.isFinite, proposed.distance.isFinite else { return }
        pose = Pose(azimuth: proposed.azimuth,
                    elevation: min(1.25, max(-1.25, proposed.elevation)),
                    distance: min(7, max(2, proposed.distance)))
        observers.removeAll { $0.value == nil }
        for observer in observers { observer.value?.applySharedCameraIfVisible() }
    }

    func resetPose() { setPose(Pose()) }

    fileprivate func observe(_ view: DualOrbitView) {
        observers.removeAll { $0.value == nil || $0.value === view }
        observers.append(WeakView(view))
    }

    fileprivate func removeObserver(_ view: DualOrbitView) {
        observers.removeAll { $0.value == nil || $0.value === view }
        releaseAnimation(view)
    }

    fileprivate func claimAnimation(_ view: DualOrbitView) { animationOwner = view }
    fileprivate func ownsAnimation(_ view: DualOrbitView) -> Bool { animationOwner === view }
    fileprivate func releaseAnimation(_ view: DualOrbitView) {
        if animationOwner === view { animationOwner = nil }
    }
}

private final class AccessibleOrbitView: SCNView {
    var adjust: ((Float) -> Void)?
    var activate: (() -> Bool)?
    override func accessibilityIncrement() { adjust?(0.25) }
    override func accessibilityDecrement() { adjust?(-0.25) }
    override func accessibilityActivate() -> Bool { activate?() ?? super.accessibilityActivate() }
}

final class DualOrbitView: UIView, UIGestureRecognizerDelegate {
    private let panes = [AccessibleOrbitView(), AccessibleOrbitView()]
    private let stack = UIStackView()
    private var cameras: [SCNNode] = []
    private var orbits: [SCNNode] = []
    private let recentFlow = SCNNode()
    private let flowHead = SCNNode()
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval?
    private var lastRevision: Int?
    private var natalPoints: [Double] = []
    private var lastProjectionRevision = -1
    private var viewState: OrbitViewState
    private var layout: OrbitLayout
    private var onTap: (() -> Void)?
    private var singleTaps: [UITapGestureRecognizer] = []
    private var motionActive = false
    private var reduceMotion = false
    private var interacting = false
    private var panOrigin = SIMD2<Float>(0, 0)
    private var pinchOrigin: Float = 2.8

    init(viewState: OrbitViewState, layout: OrbitLayout = .horizontal, onTap: (() -> Void)? = nil) {
        self.viewState = viewState
        self.layout = layout
        self.onTap = onTap
        super.init(frame: .zero)
        backgroundColor = .clear
        panes.forEach(stack.addArrangedSubview)
        stack.distribution = .fillEqually; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        for (index, pane) in panes.enumerated() {
            let dark = index == 1
            pane.backgroundColor = dark ? UIColor(white: 0.055, alpha: 1) : UIColor(white: 0.93, alpha: 1)
            pane.layer.cornerRadius = 22; pane.clipsToBounds = true
            pane.antialiasingMode = .multisampling4X
            pane.preferredFramesPerSecond = 30
            pane.rendersContinuously = false
            pane.isPlaying = false
            pane.allowsCameraControl = false
            pane.scene = SCNScene()
            let camera = SCNNode(); camera.camera = SCNCamera()
            camera.camera?.projectionDirection = .horizontal
            camera.camera?.fieldOfView = 47
            camera.camera?.zNear = 0.1; camera.camera?.zFar = 100
            camera.camera?.wantsHDR = false
            pane.scene?.rootNode.addChildNode(camera); pane.pointOfView = camera
            let orbit = SCNNode(); pane.scene?.rootNode.addChildNode(orbit)
            cameras.append(camera); orbits.append(orbit)
            if dark {
                pane.scene?.rootNode.addChildNode(recentFlow)
                let dot = SCNSphere(radius: 0.018)
                dot.segmentCount = 12
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = UIColor.white
                material.readsFromDepthBuffer = false
                dot.materials = [material]
                flowHead.geometry = dot
                flowHead.renderingOrder = 10
                flowHead.isHidden = true
                pane.scene?.rootNode.addChildNode(flowHead)
            }
            pane.isAccessibilityElement = true
            pane.accessibilityLabel = dark ? "流盘三维轨迹" : "固定生辰核三维轨迹"
            pane.accessibilityTraits = [.image, .adjustable]
            pane.adjust = { [weak self] in self?.turn($0) }
            pane.activate = { [weak self] in
                guard let action = self?.onTap else { return false }
                action(); return true
            }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            pan.maximumNumberOfTouches = 1; pane.addGestureRecognizer(pan)
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
            pinch.delegate = self; pane.addGestureRecognizer(pinch)
            let reset = UITapGestureRecognizer(target: self, action: #selector(resetCamera))
            reset.numberOfTapsRequired = 2
            reset.require(toFail: pan); reset.require(toFail: pinch)
            pane.addGestureRecognizer(reset)
            let open = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            open.numberOfTapsRequired = 1
            open.require(toFail: reset); open.require(toFail: pan); open.require(toFail: pinch)
            pane.addGestureRecognizer(open); singleTaps.append(open)
        }
        viewState.observe(self)
        configure(viewState: viewState, layout: layout, onTap: onTap)
        applyCamera()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(viewState newState: OrbitViewState, layout: OrbitLayout, onTap: (() -> Void)?) {
        if viewState !== newState {
            stop(); viewState.removeObserver(self)
            viewState = newState; viewState.observe(self)
            lastProjectionRevision = -1
        }
        self.layout = layout; self.onTap = onTap
        stack.axis = layout == .vertical ? .vertical : .horizontal
        for (index, pane) in panes.enumerated() {
            let dark = index == 1
            pane.accessibilityIdentifier = layout == .vertical
                ? (dark ? "fullscreenFlowOrbit" : "fullscreenNatalOrbit")
                : (dark ? "flowOrbit" : "natalOrbit")
            pane.accessibilityHint = onTap == nil
                ? "单指拖动改变两幅图的共同视角，双指缩放，双击恢复视角"
                : "轻点全屏查看，单指拖动改变两幅图的共同视角，双指缩放，双击恢复视角"
            var actions = [
                UIAccessibilityCustomAction(name: "向左旋转", actionHandler: { [weak self] _ in self?.turn(-0.25); return true }),
                UIAccessibilityCustomAction(name: "向右旋转", actionHandler: { [weak self] _ in self?.turn(0.25); return true }),
                UIAccessibilityCustomAction(name: "恢复视角", actionHandler: { [weak self] _ in self?.resetCamera(); return true })
            ]
            if onTap != nil {
                actions.insert(UIAccessibilityCustomAction(name: "全屏查看", actionHandler: { [weak self] _ in
                    guard let action = self?.onTap else { return false }
                    action(); return true
                }), at: 0)
            }
            pane.accessibilityCustomActions = actions
            singleTaps[index].isEnabled = onTap != nil
        }
        applyCamera()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, pane) in panes.enumerated() where index < cameras.count {
            cameras[index].camera?.projectionDirection = pane.bounds.width > pane.bounds.height ? .vertical : .horizontal
        }
    }

    func update(natal: [Double], flow: [Double], revision: Int) {
        let projection = viewState.prepareProjection(natal: natal, flow: flow)
        let projectionChanged = lastProjectionRevision != viewState.projectionRevision
        lastProjectionRevision = viewState.projectionRevision
        if natalPoints != natal || projectionChanged {
            natalPoints = natal
            orbits[0].geometry = OrbitGeometry.make(natal, dark: false, projection: projection)
        }
        if lastRevision != revision || projectionChanged {
            lastRevision = revision
            orbits[1].geometry = OrbitGeometry.make(flow, dark: true, projection: projection, opacity: 0.23)
            let recent = OrbitGeometry.recentPoints(flow)
            recentFlow.geometry = OrbitGeometry.make(recent, dark: true, projection: projection, opacity: 1)
            // No decorative animation or interpolation: the marker follows the
            // same computed endpoint as the calendar clock, at every speed.
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            if let endpoint = OrbitGeometry.vertices(Array(recent.suffix(3)), projection: projection).last {
                flowHead.position = endpoint
                flowHead.isHidden = false
            } else { flowHead.isHidden = true }
            SCNTransaction.commit()
        }
        for pane in panes { pane.setNeedsDisplay() }
    }

    func setMotion(active: Bool, reduced: Bool) {
        motionActive = active; reduceMotion = reduced
        if active && !reduced && window != nil && !isHidden {
            if displayLink == nil {
                viewState.claimAnimation(self)
                let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
                link.add(to: .main, forMode: .common); displayLink = link
            }
        } else { stop() }
        if active { applyCamera() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setMotion(active: motionActive, reduced: reduceMotion)
    }

    func stop() {
        displayLink?.invalidate(); displayLink = nil; lastTick = nil
        viewState.releaseAnimation(self)
    }

    func detach() {
        stop(); viewState.removeObserver(self); onTap = nil
        interacting = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = min(0.1, max(0, link.timestamp - (lastTick ?? link.timestamp)))
        lastTick = link.timestamp
        guard viewState.ownsAnimation(self), motionActive, !isHidden,
              !interacting, link.timestamp >= viewState.resumeRotationAt else { return }
        var pose = viewState.pose
        pose.azimuth += Float(dt) * Float.pi / 30 // one gentle revolution per minute
        viewState.setPose(pose)
    }

    fileprivate func applySharedCameraIfVisible() {
        guard motionActive, window != nil, !isHidden else { return }
        applyCamera()
    }

    private func applyCamera() {
        let pose = viewState.pose
        let position = SCNVector3(pose.distance * cos(pose.elevation) * sin(pose.azimuth),
                                  pose.distance * sin(pose.elevation), pose.distance * cos(pose.elevation) * cos(pose.azimuth))
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        for camera in cameras { camera.position = position; camera.look(at: SCNVector3Zero) }
        SCNTransaction.commit()
        for pane in panes {
            pane.accessibilityValue = "视角 \(Int(pose.azimuth * 180 / .pi))°，仰角 \(Int(pose.elevation * 180 / .pi))°，缩放 \(String(format: "%.2f", 2.8 / pose.distance))×"
            pane.setNeedsDisplay()
        }
    }

    private func updatePose(_ pose: OrbitViewState.Pose) {
        viewState.setPose(pose)
        applyCamera()
    }

    private func turn(_ amount: Float) {
        viewState.resumeRotationAt = CACurrentMediaTime() + 3
        var pose = viewState.pose; pose.azimuth += amount; updatePose(pose)
    }

    @objc private func resetCamera() {
        viewState.resumeRotationAt = CACurrentMediaTime() + 3
        viewState.resetPose(); applyCamera()
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        onTap?()
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            interacting = true
            let pose = viewState.pose; panOrigin = SIMD2(pose.azimuth, pose.elevation)
        case .changed:
            let translation = gesture.translation(in: gesture.view)
            var pose = viewState.pose
            pose.azimuth = panOrigin.x - Float(translation.x) * 0.008
            pose.elevation = panOrigin.y + Float(translation.y) * 0.008
            updatePose(pose)
        default:
            interacting = false; viewState.resumeRotationAt = CACurrentMediaTime() + 3
        }
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { interacting = true; pinchOrigin = viewState.pose.distance }
        if gesture.state == .changed, gesture.scale.isFinite, gesture.scale > 0 {
            var pose = viewState.pose; pose.distance = pinchOrigin / Float(gesture.scale)
            updatePose(pose)
        }
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            interacting = false; viewState.resumeRotationAt = CACurrentMediaTime() + 3
        }
    }
}
