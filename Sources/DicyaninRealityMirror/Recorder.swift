#if os(iOS)
import Foundation
import AVFoundation
import ReplayKit

/// Records the phone screen (mirrored scene plus AR camera feed) to a 9:16 1080x1920 .mov.
/// `slowMo(duration:factor:)` retimes the next `duration` seconds by `factor`, in the file itself.
@MainActor
public final class MirrorRecorder {
    public private(set) var isRecording = false
    public var size = CGSize(width: 1080, height: 1920)
    private let writerQueue = DispatchQueue(label: "mirror.recorder")
    private let timeline = Timeline()
    private var writer: AVAssetWriter?
    private var video: AVAssetWriterInput?
    private var audio: AVAssetWriterInput?

    public init() {}

    public func start(to url: URL, appAudio: Bool = true) async throws {
        try? FileManager.default.removeItem(at: url)
        let w = try AVAssetWriter(outputURL: url, fileType: .mov)
        let v = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill])
        v.expectsMediaDataInRealTime = true
        w.add(v)
        var a: AVAssetWriterInput?
        if appAudio {
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100, AVEncoderBitRateKey: 128_000])
            ai.expectsMediaDataInRealTime = true
            w.add(ai); a = ai
        }
        writer = w; video = v; audio = a
        timeline.reset()
        let q = writerQueue, tl = timeline
        nonisolated(unsafe) let wr = w, vi = v, au = a
        try await RPScreenRecorder.shared().startCapture { buffer, type, error in
            guard error == nil, CMSampleBufferDataIsReady(buffer) else { return }
            nonisolated(unsafe) let b = buffer
            q.async { Self.append(b, type: type, writer: wr, video: vi, audio: au, timeline: tl) }
        }
        isRecording = true
    }

    /// Stretches the next `duration` live seconds by `factor` (4 = quarter speed). Audio is muted inside the window.
    public func slowMo(duration: Double = 1.5, factor: Double = 4) {
        guard isRecording else { return }
        let tl = timeline
        writerQueue.async { tl.requestSlowMo(duration: duration, factor: factor) }
    }

    public func stop() async throws {
        try await RPScreenRecorder.shared().stopCapture()
        let q = writerQueue
        nonisolated(unsafe) let w = writer, v = video, a = audio
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            q.async {
                v?.markAsFinished(); a?.markAsFinished()
                if let w, w.status == .writing { w.finishWriting { c.resume() } } else { c.resume() }
            }
        }
        isRecording = false
        writer = nil; video = nil; audio = nil
    }

    nonisolated private static func append(_ b: CMSampleBuffer, type: RPSampleBufferType, writer: AVAssetWriter,
                                           video: AVAssetWriterInput, audio: AVAssetWriterInput?, timeline: Timeline) {
        let pts = CMSampleBufferGetPresentationTimeStamp(b).seconds
        if writer.status == .unknown {
            guard type == .video else { return }
            writer.startWriting(); writer.startSession(atSourceTime: .zero)
            timeline.begin(at: pts)
        }
        guard writer.status == .writing, let out = timeline.map(pts, isVideo: type == .video) else { return }
        guard let retimed = retime(b, to: out) else { return }
        switch type {
        case .video: if video.isReadyForMoreMediaData { video.append(retimed) }
        case .audioApp: if let audio, audio.isReadyForMoreMediaData { audio.append(retimed) }
        default: break
        }
    }

    nonisolated private static func retime(_ b: CMSampleBuffer, to t: Double) -> CMSampleBuffer? {
        var info = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(seconds: t, preferredTimescale: 600),
                                      decodeTimeStamp: .invalid)
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: b, sampleTimingEntryCount: 1,
                                              sampleTimingArray: &info, sampleBufferOut: &out)
        return out
    }
}

#endif

/// Live-to-file time map. Only touched on the writer queue.
final class Timeline: @unchecked Sendable {
    private var origin = 0.0, offset = 0.0, lastOut = -1.0
    private var slowStart: Double?, slowEnd = 0.0, factor = 1.0, pending: (Double, Double)?
    private var now = 0.0

    func reset() { origin = 0; offset = 0; lastOut = -1; slowStart = nil; pending = nil }
    func begin(at t: Double) { origin = t; now = t }
    func requestSlowMo(duration: Double, factor: Double) { pending = (duration, factor) }

    /// Returns file time, or nil to drop (audio inside slow-mo, non-monotonic video).
    func map(_ t: Double, isVideo: Bool) -> Double? {
        // Window opens at the last video frame seen before the request arrived.
        if let (d, f) = pending, slowStart == nil { slowStart = now; slowEnd = now + d; factor = f; pending = nil }
        if isVideo { now = t }
        if let s = slowStart {
            if t < slowEnd {
                guard isVideo else { return nil }
                let out = (s - origin) + offset + (t - s) * factor
                return monotonic(out)
            }
            offset += (slowEnd - s) * (factor - 1); slowStart = nil
        }
        let out = t - origin + offset
        return isVideo ? monotonic(out) : out
    }

    private func monotonic(_ out: Double) -> Double? {
        guard out > lastOut else { return nil }
        lastOut = out; return out
    }
}
