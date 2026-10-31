import XCTest
import RealityKit
@testable import DicyaninRealityMirror

@MainActor
final class UplinkProvider: RealityMirrorProviding {
    enum Input: Codable, Sendable, Equatable { case tap(SIMD3<Float>), cheer }
    var mirrorAppID: String { "org.dicyaninlabs.uplink" }
    func makeMirrorRoot() async throws -> Entity { Entity() }
}

@MainActor
final class InputUplinkTests: XCTestCase {
    func testPhoneInputReachesHeadset() async throws {
        let (a, b) = LoopbackTransport.pair()
        let tx = MirrorBroadcaster(provider: UplinkProvider(), transport: a)
        let rx = MirrorReceiver(provider: UplinkProvider(), transport: b)
        var got: [UplinkProvider.Input] = []
        tx.onInput = { got.append($0) }
        tx.start(root: Entity()); rx.start(root: Entity())
        rx.send(input: .tap([1, 0, -2]))
        rx.send(input: .cheer)
        for _ in 0..<5 where got.count < 2 { await Task.yield() }
        tx.stop()
        XCTAssertEqual(got, [.tap([1, 0, -2]), .cheer])
    }

    func testInputEncodesRoundTrip() throws {
        typealias M = MirrorMessage<MirrorNone, MirrorNone, UplinkProvider.Input>
        let d = try MirrorCodec.encode(M.input(.tap([0, 1, 2])))
        guard case let .input(i) = try MirrorCodec.decode(d, as: M.self) else { return XCTFail() }
        XCTAssertEqual(i, .tap([0, 1, 2]))
    }
}
