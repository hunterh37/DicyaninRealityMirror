import XCTest
import RealityKit
@testable import DicyaninRealityMirror

@MainActor
final class DemoProvider: RealityMirrorProviding {
    struct State: Codable, Sendable { var score: Int }
    typealias Event = MirrorNone
    var mirrorAppID: String { "org.dicyaninlabs.demo" }
    var score = 0
    var appliedScore: Int?

    func makeMirrorRoot() async throws -> Entity {
        let root = Entity()
        let cube = Entity(); cube.components.set(MirrorTagComponent("cube", smooth: false))
        root.addChild(cube)
        return root
    }
    func captureState() -> State? { State(score: score) }
    func apply(_ state: State, root: Entity) { appliedScore = state.score }
}

@MainActor
final class RoundTripTests: XCTestCase {
    func testFrameMovesPhoneEntity() async throws {
        RealityMirror.registerComponents()
        let (a, b) = LoopbackTransport.pair()
        let headset = DemoProvider(), phone = DemoProvider()
        let hRoot = try await headset.makeMirrorRoot(), pRoot = try await phone.makeMirrorRoot()
        let tx = MirrorBroadcaster(provider: headset, transport: a)
        let rx = MirrorReceiver(provider: phone, transport: b)
        rx.start(root: pRoot)
        tx.start(root: hRoot); tx.stop()

        hRoot.children[0].position = [1, 2, 3]
        headset.score = 7
        let frame = try XCTUnwrap(tx.makeFrame())
        let data = try MirrorCodec.encode(MirrorMessage<DemoProvider.State, MirrorNone, MirrorNone>.frame(frame))
        rx.receive(data)

        XCTAssertEqual(pRoot.children[0].position, [1, 2, 3])
        XCTAssertEqual(phone.appliedScore, 7)
        XCTAssertEqual(rx.status, .live)
    }

    func testVersionMismatchBlocksFrames() async throws {
        let (a, b) = LoopbackTransport.pair()
        _ = a
        let phone = DemoProvider()
        let rx = MirrorReceiver(provider: phone, transport: b)
        let root = try await phone.makeMirrorRoot()
        rx.start(root: root)
        await Task.yield()
        rx.apply(.hello(appID: "other", version: 1))
        withExtendedLifetime((a, root)) {}
        XCTAssertEqual(rx.status, .mismatch("other v1"))
    }
}
