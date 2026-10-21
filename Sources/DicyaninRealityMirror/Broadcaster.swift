import Foundation
import RealityKit
import QuartzCore

/// Headset side. Samples tagged entities plus provider state at `rate` Hz.
@MainActor
public final class MirrorBroadcaster<Provider: RealityMirrorProviding> {
    public typealias Message = MirrorMessage<Provider.State, Provider.Event>

    public let provider: Provider
    public let transport: MirrorTransport
    public var rate: Double
    /// Set by the app from ARKit WorldTrackingProvider / HandTrackingProvider.
    public var head: MirrorPose?
    public var leftHand: MirrorPose?
    public var rightHand: MirrorPose?
    public private(set) var isConnected = false

    private weak var root: Entity?
    private var timer: Timer?
    private var tick: UInt64 = 0

    public init(provider: Provider, transport: MirrorTransport, rate: Double = 30) {
        self.provider = provider; self.transport = transport; self.rate = rate
    }

    public func start(root: Entity) {
        self.root = root
        transport.onPeerChange = { [weak self] up in
            Task { @MainActor in self?.peerChanged(up) }
        }
        transport.start()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / rate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    public func stop() { timer?.invalidate(); timer = nil; transport.stop() }

    public func send(event: Provider.Event) { sendReliable(.event(event)) }
    public func send(route: String) { sendReliable(.route(route)) }

    private func peerChanged(_ up: Bool) {
        isConnected = up
        if up { sendReliable(.hello(appID: provider.mirrorAppID, version: provider.mirrorVersion)) }
    }

    /// Builds one frame. Public for tests and manual stepping.
    public func makeFrame() -> MirrorFrame<Provider.State>? {
        guard let root else { return nil }
        tick &+= 1
        let entities = RealityMirror.taggedEntities(in: root).map { id, e in
            let t = e.transformMatrix(relativeTo: root)
            let tf = Transform(matrix: t)
            return MirrorEntityState(id: id, position: tf.translation, rotation: tf.rotation,
                                     scale: tf.scale, isEnabled: e.isEnabledInHierarchy)
        }
        return MirrorFrame(tick: tick, time: CACurrentMediaTime(), entities: entities,
                           head: head, leftHand: leftHand, rightHand: rightHand,
                           state: provider.captureState())
    }

    private func sample() {
        guard isConnected, let frame = makeFrame(),
              let data = try? MirrorCodec.encode(Message.frame(frame)) else { return }
        transport.sendUnreliable(data)
    }

    private func sendReliable(_ m: Message) {
        guard let data = try? MirrorCodec.encode(m) else { return }
        transport.sendReliable(data)
    }
}
