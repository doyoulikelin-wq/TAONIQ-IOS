import XCTest
import SceneKit
@testable import TAONIQ

final class OrbitGeometryTests: XCTestCase {
    func testFullTrajectoryKeepsEveryOriginalAdjacentSegment() throws {
        let points = (0..<9_001).flatMap { i -> [Double] in
            let t = Double(i) / 100
            return [cos(t), sin(t), sin(t * 0.13)]
        }
        let geometry = try XCTUnwrap(OrbitGeometry.make(points, dark: true))
        let element = try XCTUnwrap(geometry.elements.first)
        XCTAssertEqual(element.primitiveType, .line)
        XCTAssertEqual(element.primitiveCount, 9_000)
        let indices = element.data.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        for i in 0..<9_000 {
            XCTAssertEqual(indices[2 * i], UInt32(i))
            XCTAssertEqual(indices[2 * i + 1], UInt32(i + 1))
        }
        XCTAssertEqual(geometry.sources(for: .vertex).first?.vectorCount, 9_001)
    }

    func testSeedFitUsesOneProjectionForBothClouds() {
        let natal: [Double] = [-1, 0, 0, 1, 0, 0]
        let flow: [Double] = [-10, 0, 0, 10, 0, 0]
        let projection = OrbitGeometry.sharedProjection(natal: natal, flow: flow)
        let a = OrbitGeometry.vertices(natal, projection: projection)
        let b = OrbitGeometry.vertices(flow, projection: projection)
        XCTAssertEqual(b[1].x - b[0].x, 10 * (a[1].x - a[0].x), accuracy: 0.000_001)
        XCTAssertGreaterThan(projection.radius, 10)
        XCTAssertLessThanOrEqual(abs(b[1].x), 1)
    }

    func testSharedWorldScaleDoesNotNormalizeDifferentShapesToEqualSize() {
        let small = OrbitGeometry.vertices([0, 0, 0, 1, 0, 0])
        let large = OrbitGeometry.vertices([0, 0, 0, 2, 0, 0])
        XCTAssertEqual(small[0].x, large[0].x)
        XCTAssertEqual(large[1].x - large[0].x, 2 * (small[1].x - small[0].x), accuracy: 0.000_001)
        XCTAssertNil(OrbitGeometry.make([0, 0, 0, .nan, 1, 0], dark: true))
        XCTAssertNil(OrbitGeometry.make([0, 0, 0, 1], dark: false))
    }
}
