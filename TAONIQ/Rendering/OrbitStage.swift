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

    func makeUIView(context: Context) -> DualOrbitView { DualOrbitView() }

    func updateUIView(_ view: DualOrbitView, context: Context) {
        view.update(natal: natal, flow: flow, revision: frameID)
        view.setMotion(active: isActive, reduced: reduceMotion)
    }

    static func dismantleUIView(_ uiView: DualOrbitView, coordinator: ()) {
        uiView.stop()
    }
}

enum OrbitGeometry {
    // A single shared projection; never normalize each plot separately.
    static let center = SIMD3<Double>(-0.3835333153547009, 0.0814441302050235, 0.981558454197919)
    static let radius: Double = 4.158928674224513

    struct Projection {
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

    static func make(_ points: [Double], dark: Bool, projection: Projection = .reference) -> SCNGeometry? {
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
        material.diffuse.contents = dark ? UIColor(white: 0.98, alpha: 0.62) : UIColor(white: 0.08, alpha: 0.56)
        material.isDoubleSided = true
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = false
        material.blendMode = .alpha
        geometry.materials = [material]
        return geometry
    }
}

private final class AccessibleOrbitView: SCNView {
    var adjust: ((Float) -> Void)?
    override func accessibilityIncrement() { adjust?(0.25) }
    override func accessibilityDecrement() { adjust?(-0.25) }
}

final class DualOrbitView: UIView, UIGestureRecognizerDelegate {
    private let panes = [AccessibleOrbitView(), AccessibleOrbitView()]
    private var cameras: [SCNNode] = []
    private var orbits: [SCNNode] = []
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval?
    private var lastRevision: Int?
    private var natalPoints: [Double] = []
    private var projection = OrbitGeometry.Projection.reference
    private var azimuth: Float = -Float.pi * 0.4
    private var elevation: Float = 0.31
    private var distance: Float = 2.8
    private var motionActive = false
    private var reduceMotion = false
    private var interacting = false
    private var resumeRotationAt: CFTimeInterval = 0
    private var panOrigin = SIMD2<Float>(0, 0)
    private var pinchOrigin: Float = 2.8

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let stack = UIStackView(arrangedSubviews: panes)
        stack.axis = .horizontal; stack.distribution = .fillEqually; stack.spacing = 10
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
            pane.isAccessibilityElement = true
            pane.accessibilityIdentifier = dark ? "flowOrbit" : "natalOrbit"
            pane.accessibilityLabel = dark ? "流盘三维轨迹" : "固定生辰核三维轨迹"
            pane.accessibilityHint = "单指拖动改变两幅图的共同视角，双指缩放"
            pane.accessibilityTraits = [.image, .adjustable]
            pane.adjust = { [weak self] in self?.turn($0) }
            pane.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: "向左旋转", actionHandler: { [weak self] _ in self?.turn(-0.25); return true }),
                UIAccessibilityCustomAction(name: "向右旋转", actionHandler: { [weak self] _ in self?.turn(0.25); return true }),
                UIAccessibilityCustomAction(name: "恢复视角", actionHandler: { [weak self] _ in self?.resetCamera(); return true })
            ]
            let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            pan.maximumNumberOfTouches = 1; pane.addGestureRecognizer(pan)
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
            pinch.delegate = self; pane.addGestureRecognizer(pinch)
            let reset = UITapGestureRecognizer(target: self, action: #selector(resetCamera))
            reset.numberOfTapsRequired = 2; pane.addGestureRecognizer(reset)
        }
        applyCamera()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, pane) in panes.enumerated() where index < cameras.count {
            cameras[index].camera?.projectionDirection = pane.bounds.width > pane.bounds.height ? .vertical : .horizontal
        }
    }

    func update(natal: [Double], flow: [Double], revision: Int) {
        if natalPoints != natal {
            natalPoints = natal
            projection = OrbitGeometry.sharedProjection(natal: natal, flow: flow)
            orbits[0].geometry = OrbitGeometry.make(natal, dark: false, projection: projection)
        }
        if lastRevision != revision {
            lastRevision = revision
            orbits[1].geometry = OrbitGeometry.make(flow, dark: true, projection: projection)
        }
        for pane in panes { pane.setNeedsDisplay() }
    }

    func setMotion(active: Bool, reduced: Bool) {
        motionActive = active; reduceMotion = reduced
        if active && !reduced && window != nil {
            if displayLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
                link.add(to: .main, forMode: .common); displayLink = link
            }
        } else { stop() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setMotion(active: motionActive, reduced: reduceMotion)
    }

    func stop() { displayLink?.invalidate(); displayLink = nil; lastTick = nil }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = min(0.1, max(0, link.timestamp - (lastTick ?? link.timestamp)))
        lastTick = link.timestamp
        guard !interacting, link.timestamp >= resumeRotationAt else { return }
        azimuth += Float(dt) * Float.pi / 30 // one gentle revolution per minute
        applyCamera()
    }

    private func applyCamera() {
        let position = SCNVector3(distance * cos(elevation) * sin(azimuth),
                                  distance * sin(elevation), distance * cos(elevation) * cos(azimuth))
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        for camera in cameras { camera.position = position; camera.look(at: SCNVector3Zero) }
        SCNTransaction.commit()
        for pane in panes {
            pane.accessibilityValue = "视角 \(Int(azimuth * 180 / .pi))°，仰角 \(Int(elevation * 180 / .pi))°"
            pane.setNeedsDisplay()
        }
    }

    private func turn(_ amount: Float) {
        resumeRotationAt = CACurrentMediaTime() + 3
        azimuth += amount; applyCamera()
    }

    @objc private func resetCamera() {
        azimuth = -.pi * 0.4; elevation = 0.31; distance = 2.8
        resumeRotationAt = CACurrentMediaTime() + 3; applyCamera()
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            interacting = true; panOrigin = SIMD2(azimuth, elevation)
        case .changed:
            let translation = gesture.translation(in: gesture.view)
            azimuth = panOrigin.x - Float(translation.x) * 0.008
            elevation = min(1.25, max(-1.25, panOrigin.y + Float(translation.y) * 0.008))
            applyCamera()
        default:
            interacting = false; resumeRotationAt = CACurrentMediaTime() + 3
        }
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { interacting = true; pinchOrigin = distance }
        if gesture.state == .changed {
            distance = min(7, max(2, pinchOrigin / Float(gesture.scale))); applyCamera()
        }
        if gesture.state == .ended || gesture.state == .cancelled {
            interacting = false; resumeRotationAt = CACurrentMediaTime() + 3
        }
    }
}
