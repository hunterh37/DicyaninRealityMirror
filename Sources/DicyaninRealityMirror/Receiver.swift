import Foundation
import RealityKit
import Observation

/// Phone side. Decodes frames and drives the locally built mirror root.
@MainActor @Observable
public final class MirrorReceiver<Provider: RealityMirrorProviding> {
    public typealias Message = MirrorMessage<Provider.State, Provider.Event, Provider.Input>

    public enum Status: Equatable, Sendable {
        case searching, connected, mismatch(String), live
    }

    public let provider: Provider
    @ObservationIgnored public let transport: MirrorTransport
    public private(set) var status: Status = .searching
    public private(set) var lastTick: UInt64 = 0
    public private(set) var head: MirrorPose?
    public private(set) var leftHand: MirrorPose?
    public private(set) var rightHand: MirrorPose?
    /// 0 snaps, 1 never moves. Applied per frame received.
    public var smoothing: Float = 0.35

    @ObservationIgnored private weak var root: Entity?
    @ObservationIgnored private var tagged: [String: Entity] = [:]

    public init(provider: Provider, transport: MirrorTransport) {
        self.provider = provider; self.transport = transport
    }

    public func start(root: Entity) {
        self.root = root
        tagged = RealityMirror.taggedEntities(in: root)
        transport.onReceive = { [weak self] data in
            Task { @MainActor in self?.receive(data) }
        }
        transport.onPeerChange = { [weak self] up in
            Task { @MainActor in self?.peerChanged(up) }
        }
        transport.start()
    }

    public func stop() { transport.stop() }

    /// Sends a phone input to the headset over the reliable channel.
    public func send(input: Provider.Input) {
        guard let data = try? MirrorCodec.encode(Message.input(input)) else { return }
        transport.sendReliable(data)
    }

    private func peerChanged(_ up: Bool) {
        if case .mismatch = status, up { return }
        if !up { status = .searching } else if status == .searching { status = .connected }
    }

    /// Re-scan after the provider adds tagged entities at runtime.
    public func refreshTags() { if let root { tagged = RealityMirror.taggedEntities(in: root) } }

    func receive(_ data: Data) {
        guard let m = try? MirrorCodec.decode(data, as: Message.self) else { return }
        apply(m)
    }

    public func apply(_ message: Message) {
        guard let root else { return }
        switch message {
        case let .hello(appID, version):
            if appID != provider.mirrorAppID || version != provider.mirrorVersion {
                status = .mismatch("\(appID) v\(version)")
            } else { status = .connected }
        case let .frame(frame):
            if case .mismatch = status { return }
            guard frame.tick > lastTick || frame.tick < 16 else { return }
            lastTick = frame.tick
            for s in frame.entities {
                guard let e = tagged[s.id] else { continue }
                e.isEnabled = s.isEnabled
                let target = Transform(scale: s.scale, rotation: s.rotation, translation: s.position)
                let smooth = e.components[MirrorTagComponent.self]?.smooth ?? true
                e.setTransformMatrix(smooth ? blend(e.transformMatrix(relativeTo: root), target) : target.matrix,
                                     relativeTo: root)
            }
            head = frame.head; leftHand = frame.leftHand; rightHand = frame.rightHand
            if let state = frame.state { provider.apply(state, root: root) }
            status = .live
        case let .event(event):
            provider.handle(event, root: root)
        case let .route(route):
            provider.open(route: route, root: root)
        case .input:
            break
        }
    }

    private func blend(_ current: float4x4, _ target: Transform) -> float4x4 {
        let c = Transform(matrix: current)
        let t = 1 - smoothing
        return Transform(scale: simd_mix(c.scale, target.scale, SIMD3(repeating: t)),
                         rotation: simd_slerp(c.rotation, target.rotation, t),
                         translation: simd_mix(c.translation, target.translation, SIMD3(repeating: t))).matrix
    }
}
