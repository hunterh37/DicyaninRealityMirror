import Foundation
import simd

/// Transform of one mirrored entity, keyed by a stable id shared by both devices.
public struct MirrorEntityState: Codable, Sendable, Equatable {
    public var id: String
    public var position: SIMD3<Float>
    public var rotation: simd_quatf
    public var scale: SIMD3<Float>
    public var isEnabled: Bool

    public init(id: String, position: SIMD3<Float>, rotation: simd_quatf,
                scale: SIMD3<Float>, isEnabled: Bool) {
        self.id = id; self.position = position; self.rotation = rotation
        self.scale = scale; self.isEnabled = isEnabled
    }
}

/// Pose of the headset or a hand joint in world space.
public struct MirrorPose: Codable, Sendable, Equatable {
    public var position: SIMD3<Float>
    public var rotation: simd_quatf
    public init(position: SIMD3<Float>, rotation: simd_quatf) {
        self.position = position; self.rotation = rotation
    }
}

/// One snapshot sent from the headset to the phone.
public struct MirrorFrame<State: Codable & Sendable>: Codable, Sendable {
    public var tick: UInt64
    public var time: TimeInterval
    public var entities: [MirrorEntityState]
    public var head: MirrorPose?
    public var leftHand: MirrorPose?
    public var rightHand: MirrorPose?
    /// App-defined state (score, phase, selected item). Applied by the provider.
    public var state: State?

    public init(tick: UInt64, time: TimeInterval, entities: [MirrorEntityState],
                head: MirrorPose? = nil, leftHand: MirrorPose? = nil,
                rightHand: MirrorPose? = nil, state: State? = nil) {
        self.tick = tick; self.time = time; self.entities = entities
        self.head = head; self.leftHand = leftHand; self.rightHand = rightHand
        self.state = state
    }
}

/// Wire envelope. Events are discrete one-shots (play sound, spawn burst) that
/// must not be lost to interpolation.
public enum MirrorMessage<State: Codable & Sendable, Event: Codable & Sendable,
                          Input: Codable & Sendable>: Codable, Sendable {
    case hello(appID: String, version: Int)
    case frame(MirrorFrame<State>)
    case event(Event)
    case route(String)
    /// Phone to headset. The headset stays authoritative and decides what to do.
    case input(Input)
}

extension simd_quatf: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.init(vector: SIMD4<Float>(try c.decode(Float.self), try c.decode(Float.self),
                                       try c.decode(Float.self), try c.decode(Float.self)))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(vector.x); try c.encode(vector.y); try c.encode(vector.z); try c.encode(vector.w)
    }
}

/// Placeholder for apps without custom state or events.
public struct MirrorNone: Codable, Sendable, Equatable { public init() {} }
