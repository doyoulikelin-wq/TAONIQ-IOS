import XCTest
import SceneKit
@testable import TAONIQ

final class OrbitViewStateTests: XCTestCase {
    @MainActor
    private func panes(in view: UIView) -> [SCNView] {
        if let pane = view as? SCNView { return [pane] }
        return view.subviews.flatMap { panes(in: $0) }
    }

    @MainActor
    func testFullscreenKeepsTheExistingPoseAndNatalKeyedProjection() throws {
        let state = OrbitViewState()
        let natal: [Double] = [-1, 0, 0, 1, 0, 0]
        let seed: [Double] = [-2, 1, 0, 2, -1, 0]
        let home = DualOrbitView(viewState: state)
        home.update(natal: natal, flow: seed, revision: 1)
        let frozen = state.projection
        let pose = OrbitViewState.Pose(azimuth: 0.8, elevation: -0.2, distance: 4)
        state.setPose(pose)
        home.configure(viewState: state, layout: .horizontal, onTap: nil)

        let fullscreen = DualOrbitView(viewState: state, layout: .vertical)
        // A later, larger flow must not silently change scale when presented.
        fullscreen.update(natal: natal, flow: seed.map { $0 * 10 }, revision: 40)
        XCTAssertEqual(state.projection, frozen)
        XCTAssertEqual(state.projectionRevision, 1)
        XCTAssertEqual(state.pose, pose)
        let homePanes = panes(in: home), fullPanes = panes(in: fullscreen)
        XCTAssertEqual(homePanes.map(\.accessibilityIdentifier), ["natalOrbit", "flowOrbit"])
        XCTAssertEqual(fullPanes.map(\.accessibilityIdentifier), ["fullscreenNatalOrbit", "fullscreenFlowOrbit"])
        XCTAssertEqual((fullscreen.subviews.first as? UIStackView)?.axis, .vertical)
        XCTAssertEqual(homePanes.first?.accessibilityValue, fullPanes.first?.accessibilityValue)
        XCTAssertTrue(fullPanes[0].accessibilityValue?.contains("缩放 0.70×") == true)
        let a = try XCTUnwrap(homePanes[0].pointOfView?.position)
        let b = try XCTUnwrap(fullPanes[0].pointOfView?.position)
        XCTAssertEqual(a.x, b.x); XCTAssertEqual(a.y, b.y); XCTAssertEqual(a.z, b.z)
        home.detach(); fullscreen.detach()
    }

    @MainActor
    func testProjectionSurvivesEmptyNavigationFramesAndChangesOnlyWithNatal() {
        let state = OrbitViewState()
        let natal: [Double] = [-1, 0, 0, 1, 0, 0]
        let seed: [Double] = [-2, 0, 0, 2, 0, 0]
        let original = state.prepareProjection(natal: natal, flow: seed)
        XCTAssertEqual(state.prepareProjection(natal: [], flow: []), original)
        XCTAssertEqual(state.prepareProjection(natal: natal, flow: seed.map { $0 * 100 }), original)
        XCTAssertEqual(state.projectionRevision, 1)
        let changed = state.prepareProjection(natal: natal.map { $0 * 3 }, flow: seed.map { $0 * 3 })
        XCTAssertNotEqual(changed, original)
        XCTAssertEqual(state.projectionRevision, 2)
    }

    @MainActor
    func testBothHomePlotsExposeFullScreenActivationAndFullscreenDoesNotReopen() {
        let state = OrbitViewState()
        var opens = 0
        let home = DualOrbitView(viewState: state, onTap: { opens += 1 })
        for pane in panes(in: home) {
            XCTAssertTrue(pane.accessibilityActivate())
            XCTAssertTrue(pane.accessibilityCustomActions?.contains { $0.name == "全屏查看" } == true)
        }
        XCTAssertEqual(opens, 2)
        let fullscreen = DualOrbitView(viewState: state, layout: .vertical)
        for pane in panes(in: fullscreen) {
            XCTAssertFalse(pane.accessibilityActivate())
            XCTAssertFalse(pane.accessibilityCustomActions?.contains { $0.name == "全屏查看" } == true)
        }
        home.detach(); fullscreen.detach()
    }
}
