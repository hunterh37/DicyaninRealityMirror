#if os(iOS)
import SwiftUI
import RealityKit

/// Drop-in phone view. Builds the provider's root, connects, and renders it.
public struct RealityMirrorView<Provider: RealityMirrorProviding>: View {
    @State private var receiver: MirrorReceiver<Provider>
    private let mode: MirrorCameraMode

    public init(provider: Provider, transport: MirrorTransport? = nil, mode: MirrorCameraMode = .arAnchored) {
        let t = transport ?? MultipeerTransport(role: .phone, appID: provider.mirrorAppID)
        _receiver = State(initialValue: MirrorReceiver(provider: provider, transport: t))
        self.mode = mode
    }

    public var body: some View {
        RealityView { content in
            RealityMirror.registerComponents()
            guard let root = try? await receiver.provider.makeMirrorRoot() else { return }
            if mode == .arAnchored {
                let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: [0.3, 0.3]))
                anchor.addChild(root)
                content.add(anchor)
                content.camera = .spatialTracking
            } else {
                content.add(root)
                content.camera = .virtual
                let cam = Entity()
                cam.components.set(PerspectiveCameraComponent())
                cam.name = "mirror.camera"
                content.add(cam)
            }
            receiver.start(root: root)
        } update: { content in
            guard let cam = content.entities.first(where: { $0.name == "mirror.camera" }),
                  let t = MirrorCameraRig.transform(for: mode, head: receiver.head,
                                                    time: Date.timeIntervalSinceReferenceDate)
            else { return }
            cam.transform = t
        }
        .overlay(alignment: .top) { MirrorStatusBadge(status: receiver.status) }
        .ignoresSafeArea()
    }
}

struct MirrorStatusBadge<P: RealityMirrorProviding>: View {
    let status: MirrorReceiver<P>.Status
    var body: some View {
        Text(label).font(.caption.monospaced()).padding(6)
            .background(.black.opacity(0.5), in: Capsule()).foregroundStyle(.white)
            .opacity(status == .live ? 0 : 1)
    }
    private var label: String {
        switch status {
        case .searching: "searching for headset"
        case .connected: "connected"
        case .live: "live"
        case let .mismatch(s): "mismatch: \(s)"
        }
    }
}
#endif
