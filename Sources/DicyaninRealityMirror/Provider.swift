import Foundation
import RealityKit

/// Adopted by an app once, in code compiled for both visionOS and iOS.
///
/// The scene-building code is shared. Only `captureState` runs on the headset
/// and only `apply` runs on the phone. Hand tracking, immersive spaces and
/// other visionOS-only APIs stay out of this type.
@MainActor
public protocol RealityMirrorProviding: AnyObject {
    associatedtype State: Codable & Sendable = MirrorNone
    associatedtype Event: Codable & Sendable = MirrorNone

    /// Stable id. Both devices refuse to pair when ids differ.
    var mirrorAppID: String { get }
    /// Bump when `State` or the scene layout changes incompatibly.
    var mirrorVersion: Int { get }

    /// Builds the same root entity on both platforms. Tag entities that should
    /// stream transforms with `MirrorTagComponent`.
    func makeMirrorRoot() async throws -> Entity

    /// Headset side. Called every broadcast tick.
    func captureState() -> State?

    /// Phone side. Called after entity transforms are applied for a frame.
    func apply(_ state: State, root: Entity)

    /// Phone side. Discrete one-shot effects.
    func handle(_ event: Event, root: Entity)

    /// Phone side. Optional route jump (matches DicyaninStageDirector routes).
    func open(route: String, root: Entity)
}

public extension RealityMirrorProviding {
    var mirrorVersion: Int { 1 }
    func captureState() -> State? { nil }
    func apply(_ state: State, root: Entity) {}
    func handle(_ event: Event, root: Entity) {}
    func open(route: String, root: Entity) {}
}

/// Marks an entity for transform streaming. `id` must match on both devices,
/// so set it in shared scene code, not from runtime-generated names.
public struct MirrorTagComponent: Component, Codable, Sendable {
    public var id: String
    /// Interpolate on the phone. Disable for teleports and snaps.
    public var smooth: Bool
    public init(_ id: String, smooth: Bool = true) { self.id = id; self.smooth = smooth }
}

public enum RealityMirror {
    /// Call once at launch on both platforms.
    @MainActor public static func registerComponents() {
        MirrorTagComponent.registerComponent()
    }

    /// Collects every tagged entity under `root`, keyed by mirror id.
    @MainActor public static func taggedEntities(in root: Entity) -> [String: Entity] {
        var out: [String: Entity] = [:]
        func walk(_ e: Entity) {
            if let tag = e.components[MirrorTagComponent.self] { out[tag.id] = e }
            for child in e.children { walk(child) }
        }
        walk(root)
        return out
    }
}
