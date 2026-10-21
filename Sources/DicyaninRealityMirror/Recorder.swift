#if os(iOS)
import Foundation
import ReplayKit

/// Records the phone screen (mirrored scene plus camera feed in AR mode).
@MainActor
public final class MirrorRecorder {
    public private(set) var isRecording = false
    public init() {}

    public func start(microphone: Bool = false) async throws {
        let r = RPScreenRecorder.shared()
        r.isMicrophoneEnabled = microphone
        try await r.startRecording()
        isRecording = true
    }

    /// Writes the take to `url` (.mov).
    public func stop(to url: URL) async throws {
        try await RPScreenRecorder.shared().stopRecording(withOutput: url)
        isRecording = false
    }
}
#endif
