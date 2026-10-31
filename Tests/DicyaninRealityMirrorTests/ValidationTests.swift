import XCTest
import RealityKit
import simd
@testable import DicyaninRealityMirror

@MainActor
final class FullProvider: RealityMirrorProviding {
    struct State: Codable, Sendable, Equatable { var phase: String }
    enum Event: Codable, Sendable, Equatable { case burst(String) }
    var mirrorAppID: String { "org.dicyaninlabs.full" }
    var mirrorVersion: Int { 3 }
    var events: [Event] = []
    var routes: [String] = []
    var states: [State] = []

    func makeMirrorRoot() async throws -> Entity {
        let root = Entity()
        let parent = Entity(); parent.position = [10, 0, 0]
        parent.components.set(MirrorTagComponent("parent", smooth: false))
        let child = Entity(); child.components.set(MirrorTagComponent("child", smooth: false))
        let smooth = Entity(); smooth.components.set(MirrorTagComponent("smooth"))
        parent.addChild(child); root.addChild(parent); root.addChild(smooth)
        return root
    }
    func captureState() -> State? { State(phase: "play") }
    func apply(_ s: State, root: Entity) { states.append(s) }
    func handle(_ e: Event, root: Entity) { events.append(e) }
    func open(route: String, root: Entity) { routes.append(route) }
}

typealias Msg = MirrorMessage<FullProvider.State, FullProvider.Event, MirrorNone>

@MainActor
final class ValidationTests: XCTestCase {
    var roots: [Entity] = []
    var keep: [AnyObject] = []

    override func setUp() async throws { RealityMirror.registerComponents() }

    func makeReceiver() async throws -> (MirrorReceiver<FullProvider>, FullProvider, Entity) {
        let (a, b) = LoopbackTransport.pair(); keep += [a, b]
        let p = FullProvider(); let root = try await p.makeMirrorRoot(); roots.append(root)
        let rx = MirrorReceiver(provider: p, transport: b)
        rx.start(root: root)
        return (rx, p, root)
    }

    func frame(_ tick: UInt64, _ entities: [MirrorEntityState]) -> Msg {
        .frame(MirrorFrame(tick: tick, time: 0, entities: entities, state: .init(phase: "t\(tick)")))
    }

    func ent(_ id: String, _ p: SIMD3<Float>, enabled: Bool = true,
             rot: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) -> MirrorEntityState {
        MirrorEntityState(id: id, position: p, rotation: rot, scale: [1, 1, 1], isEnabled: enabled)
    }

    func testCodecRoundTripsEveryCase() throws {
        let q = simd_quatf(angle: 1.2, axis: simd_normalize([1, 2, 3]))
        let f = MirrorFrame<FullProvider.State>(tick: 9, time: 1.5, entities: [ent("a", [1, 2, 3], rot: q)],
                                                head: MirrorPose(position: [0, 1.6, 0], rotation: q),
                                                state: .init(phase: "x"))
        for m: Msg in [.hello(appID: "id", version: 2), .frame(f), .event(.burst("b")), .route("menu/play")] {
            let back = try MirrorCodec.decode(try MirrorCodec.encode(m), as: Msg.self)
            switch (m, back) {
            case let (.hello(a, v), .hello(b, w)): XCTAssertEqual(a, b); XCTAssertEqual(v, w)
            case let (.frame(x), .frame(y)):
                XCTAssertEqual(x.entities, y.entities); XCTAssertEqual(x.head, y.head)
                XCTAssertEqual(x.state, y.state); XCTAssertEqual(x.tick, y.tick)
            case let (.event(x), .event(y)): XCTAssertEqual(x, y)
            case let (.route(x), .route(y)): XCTAssertEqual(x, y)
            default: XCTFail("case changed")
            }
        }
    }

    func testFrameSizeFor100Entities() throws {
        let f = MirrorFrame<MirrorNone>(tick: 1, time: 0, entities: (0..<100).map { ent("e\($0)", [1, 2, 3]) })
        let size = try MirrorCodec.encode(MirrorMessage<MirrorNone, MirrorNone, MirrorNone>.frame(f)).count
        XCTAssertLessThan(size, 60_000, "frame \(size) B")
    }

    func testNestedEntityUsesRootRelativeTransform() async throws {
        let (rx, _, root) = try await makeReceiver()
        rx.apply(frame(1, [ent("parent", [10, 0, 0]), ent("child", [12, 0, 0])]))
        let child = try XCTUnwrap(RealityMirror.taggedEntities(in: root)["child"])
        XCTAssertEqual(RealityMirror.taggedEntities(in: root)["child"]!.position, [2, 0, 0])
        XCTAssertEqual(child.position(relativeTo: root), [12, 0, 0])
    }

    func testBroadcasterReportsRootRelativeTransform() async throws {
        let (a, _) = LoopbackTransport.pair(); keep.append(a)
        let p = FullProvider(); let root = try await p.makeMirrorRoot()
        root.position = [100, 0, 0]
        RealityMirror.taggedEntities(in: root)["child"]!.position = [1, 0, 0]
        let tx = MirrorBroadcaster(provider: p, transport: a)
        tx.start(root: root); tx.stop()
        let f = try XCTUnwrap(tx.makeFrame())
        let child = try XCTUnwrap(f.entities.first { $0.id == "child" })
        XCTAssertEqual(child.position, [11, 0, 0])
        XCTAssertEqual(f.state, .init(phase: "play"))
        XCTAssertEqual(f.entities.count, 3)
    }

    func testStaleFrameDropped() async throws {
        let (rx, p, root) = try await makeReceiver()
        rx.apply(frame(30, [ent("parent", [1, 0, 0])]))
        rx.apply(frame(20, [ent("parent", [9, 0, 0])]))
        XCTAssertEqual(RealityMirror.taggedEntities(in: root)["parent"]!.position, [1, 0, 0])
        XCTAssertEqual(p.states.map(\.phase), ["t30"])
        XCTAssertEqual(rx.lastTick, 30)
    }

    func testTickRestartAccepted() async throws {
        let (rx, _, root) = try await makeReceiver()
        rx.apply(frame(500, [ent("parent", [1, 0, 0])]))
        rx.apply(frame(1, [ent("parent", [2, 0, 0])]))
        XCTAssertEqual(RealityMirror.taggedEntities(in: root)["parent"]!.position, [2, 0, 0])
    }

    func testDisabledFlagApplied() async throws {
        let (rx, _, root) = try await makeReceiver()
        rx.apply(frame(1, [ent("parent", [10, 0, 0], enabled: false)]))
        XCTAssertFalse(RealityMirror.taggedEntities(in: root)["parent"]!.isEnabled)
    }

    func testUnknownTagIgnored() async throws {
        let (rx, _, _) = try await makeReceiver()
        rx.apply(frame(1, [ent("ghost", [1, 1, 1])]))
        XCTAssertEqual(rx.status, .live)
    }

    func testSmoothingConvergesWithoutOvershoot() async throws {
        let (rx, _, root) = try await makeReceiver()
        let e = RealityMirror.taggedEntities(in: root)["smooth"]!
        var last: Float = 0
        for t in 1...40 {
            rx.apply(frame(UInt64(t), [ent("smooth", [1, 0, 0])]))
            XCTAssertGreaterThanOrEqual(e.position.x, last); XCTAssertLessThanOrEqual(e.position.x, 1.0001)
            last = e.position.x
        }
        XCTAssertEqual(e.position.x, 1, accuracy: 1e-4)
        XCTAssertEqual(RealityMirror.taggedEntities(in: root)["smooth"]!.position.x, last)
    }

    func testSmoothingZeroSnaps() async throws {
        let (rx, _, root) = try await makeReceiver()
        rx.smoothing = 0
        rx.apply(frame(1, [ent("smooth", [5, 0, 0])]))
        XCTAssertEqual(RealityMirror.taggedEntities(in: root)["smooth"]!.position, [5, 0, 0])
    }

    func testEventsAndRoutesDispatched() async throws {
        let (rx, p, _) = try await makeReceiver()
        rx.apply(.event(.burst("a"))); rx.apply(.route("level/2"))
        XCTAssertEqual(p.events, [.burst("a")]); XCTAssertEqual(p.routes, ["level/2"])
    }

    func testVersionMismatchBlocksFrames() async throws {
        let (rx, p, root) = try await makeReceiver()
        rx.apply(.hello(appID: "org.dicyaninlabs.full", version: 2))
        rx.apply(frame(1, [ent("parent", [0, 9, 0])]))
        XCTAssertEqual(rx.status, .mismatch("org.dicyaninlabs.full v2"))
        XCTAssertEqual(RealityMirror.taggedEntities(in: root)["parent"]!.position, [10, 0, 0])
        XCTAssertTrue(p.states.isEmpty)
    }

    func testMatchingHelloConnects() async throws {
        let (rx, _, _) = try await makeReceiver()
        rx.apply(.hello(appID: "org.dicyaninlabs.full", version: 3))
        XCTAssertEqual(rx.status, .connected)
    }

    func testGarbageDataIgnored() async throws {
        let (rx, _, _) = try await makeReceiver()
        rx.receive(Data([0, 1, 2, 3]))
        XCTAssertEqual(rx.lastTick, 0)
    }

    func testEndToEndOverLoopback() async throws {
        let (a, b) = LoopbackTransport.pair(); keep += [a, b]
        let hp = FullProvider(), pp = FullProvider()
        let hRoot = try await hp.makeMirrorRoot(), pRoot = try await pp.makeMirrorRoot()
        let rx = MirrorReceiver(provider: pp, transport: b); rx.start(root: pRoot)
        let tx = MirrorBroadcaster(provider: hp, transport: a, rate: 60); tx.start(root: hRoot)
        RealityMirror.taggedEntities(in: hRoot)["parent"]!.position = [3, 4, 5]
        tx.send(event: .burst("e2e"))
        for _ in 0..<50 where rx.status != .live { try await Task.sleep(for: .milliseconds(20)) }
        tx.stop()
        XCTAssertEqual(rx.status, .live)
        XCTAssertEqual(RealityMirror.taggedEntities(in: pRoot)["parent"]!.position, [3, 4, 5])
        XCTAssertEqual(pp.events, [.burst("e2e")])
    }

    func testCameraRigModes() {
        let head = MirrorPose(position: [0, 1.6, 0], rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0]))
        XCTAssertNil(MirrorCameraRig.transform(for: .arAnchored, head: head, time: 0))
        XCTAssertNil(MirrorCameraRig.transform(for: .headsetPOV, head: nil, time: 0))
        XCTAssertEqual(MirrorCameraRig.transform(for: .headsetPOV, head: head, time: 0)?.translation, head.position)
        let o = MirrorCameraRig.transform(for: .orbit(distance: 2, height: 0, degreesPerSecond: 90), head: head, time: 1)!
        XCTAssertEqual(simd_distance(o.translation, head.position), 2, accuracy: 1e-4)
        let fwd = o.rotation.act([0, 0, -1])
        XCTAssertEqual(simd_dot(fwd, simd_normalize(head.position - o.translation)), 1, accuracy: 1e-4)
        let same = MirrorCameraRig.lookAt(eye: [1, 1, 1], target: [1, 1, 1])
        XCTAssertFalse(same.rotation.vector.x.isNaN)
    }
}
