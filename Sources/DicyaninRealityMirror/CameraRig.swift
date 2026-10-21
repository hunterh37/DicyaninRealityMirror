import Foundation
import RealityKit
import simd

/// How the phone frames the mirrored scene.
public enum MirrorCameraMode: Sendable, Equatable {
    /// Phone is an AR window: the scene is anchored on a real surface and the
    /// operator walks around the headset wearer. Best for demo footage.
    case arAnchored
    /// First person from the headset pose. Matches what the wearer sees.
    case headsetPOV
    /// Third person orbit around the headset pose.
    case orbit(distance: Float, height: Float, degreesPerSecond: Float)
    /// Fixed virtual tripod.
    case fixed(position: SIMD3<Float>, lookAt: SIMD3<Float>)
}

/// Computes the virtual camera transform for non-AR modes.
public enum MirrorCameraRig {
    public static func transform(for mode: MirrorCameraMode, head: MirrorPose?, time: Double) -> Transform? {
        switch mode {
        case .arAnchored:
            return nil
        case .headsetPOV:
            guard let head else { return nil }
            return Transform(rotation: head.rotation, translation: head.position)
        case let .orbit(distance, height, dps):
            let center = head?.position ?? .zero
            let a = Float(time) * dps * .pi / 180
            let eye = center + SIMD3(sin(a) * distance, height, cos(a) * distance)
            return lookAt(eye: eye, target: center)
        case let .fixed(position, target):
            return lookAt(eye: position, target: target)
        }
    }

    public static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>) -> Transform {
        var t = Transform(translation: eye)
        let f = simd_normalize(target - eye)
        guard simd_length(f) > 0 else { return t }
        t.rotation = simd_quatf(from: SIMD3(0, 0, -1), to: f)
        return t
    }
}
