import Foundation

/// Byte pipe between headset and phone. Multipeer ships in the package;
/// GroupActivities or a socket can be dropped in by conforming.
public protocol MirrorTransport: AnyObject, Sendable {
    /// Unreliable, latest-wins channel for frames.
    func sendUnreliable(_ data: Data)
    /// Reliable, ordered channel for hello, events and routes.
    func sendReliable(_ data: Data)
    var onReceive: (@Sendable (Data) -> Void)? { get set }
    var onPeerChange: (@Sendable (Bool) -> Void)? { get set }
    func start()
    func stop()
}

/// Two linked in-process endpoints for tests and previews.
public final class LoopbackTransport: MirrorTransport, @unchecked Sendable {
    public weak var peer: LoopbackTransport?
    public var onReceive: (@Sendable (Data) -> Void)?
    public var onPeerChange: (@Sendable (Bool) -> Void)?

    public init() {}

    public static func pair() -> (LoopbackTransport, LoopbackTransport) {
        let a = LoopbackTransport(), b = LoopbackTransport()
        a.peer = b; b.peer = a
        return (a, b)
    }

    public func sendUnreliable(_ data: Data) { peer?.onReceive?(data) }
    public func sendReliable(_ data: Data) { peer?.onReceive?(data) }
    public func start() { onPeerChange?(peer != nil) }
    public func stop() { onPeerChange?(false) }
}

enum MirrorCodec {
    static func encode<S, E, I>(_ m: MirrorMessage<S, E, I>) throws -> Data {
        try PropertyListEncoder.binary.encode(m)
    }
    static func decode<S, E, I>(_ d: Data, as: MirrorMessage<S, E, I>.Type) throws -> MirrorMessage<S, E, I> {
        try PropertyListDecoder().decode(MirrorMessage<S, E, I>.self, from: d)
    }
}

extension PropertyListEncoder {
    static var binary: PropertyListEncoder {
        let e = PropertyListEncoder(); e.outputFormat = .binary; return e
    }
}
