# DicyaninRealityMirror

Records demo footage of a visionOS app from an iPhone. The headset runs the real app.
The phone rebuilds the same RealityKit scene from shared code and replays the headset's
entity transforms, head pose, hand poses and app state at 30 Hz. The phone then films
that scene in AR (walk around the wearer), from the headset POV, or from a virtual
orbit/tripod camera, and saves a .mov with ReplayKit.

Vision Pro capture is limited to the wearer's eye view at fixed framing. A mirrored scene
on the phone gives third-person shots, a real room behind the content, and a second
operator holding the camera.

## Why a protocol

Porting a visionOS app to iOS means rewriting windows, immersive spaces and hand input.
The mirror needs none of that. It needs the scene graph (RealityKit runs on iOS) and a
stream of what changed. `RealityMirrorProviding` is the seam: one type, compiled for both
platforms, that builds the root entity. visionOS-only code stays outside it.

```swift
@MainActor final class OrbMirror: RealityMirrorProviding {
    struct State: Codable, Sendable { var score: Int; var phase: String }
    enum Event: Codable, Sendable { case burst(id: String) }

    var mirrorAppID: String { "org.dicyaninlabs.orbs" }

    func makeMirrorRoot() async throws -> Entity {
        let root = try await Entity(named: "Scene", in: realityKitContentBundle)
        root.findEntity(named: "Orb")?.components.set(MirrorTagComponent("orb"))
        return root
    }

    func captureState() -> State? { State(score: Game.shared.score, phase: Game.shared.phase) } // visionOS
    func apply(_ s: State, root: Entity) { ScoreBoard.update(root, s) }                         // iOS
    func handle(_ e: Event, root: Entity) { if case .burst(let id) = e { FX.burst(root, id) } }  // iOS
}
```

Headset:

```swift
let mirror = MirrorBroadcaster(provider: OrbMirror(),
                               transport: MultipeerTransport(role: .headset, appID: "org.dicyaninlabs.orbs"))
mirror.start(root: sceneRoot)          // inside RealityView make
mirror.head = devicePose               // from WorldTrackingProvider, optional
mirror.send(event: .burst(id: "orb"))  // one-shots that must not be interpolated away
```

Phone (the "Mirror Cam" recorder app, or an iOS target of the same project):

```swift
RealityMirrorView(provider: OrbMirror(), mode: .arAnchored)
let rec = MirrorRecorder(); try await rec.start(); try await rec.stop(to: url)
```

## What streams

- Transforms of entities tagged with `MirrorTagComponent`, relative to the root. Tag ids are
  set in shared code so both sides match. Untagged entities stay at their authored pose.
- `State`: app-level values the phone cannot infer (score, UI phase, selected item).
- `Event`: discrete effects (particles, sounds, spawns) sent on the reliable channel.
- `route`: a DicyaninStageDirector route string, so the phone and headset jump to the
  same scene for a scripted take.
- `hello`: app id and `mirrorVersion`. A mismatch blocks frames and shows on the badge.

Meshes, textures and materials never cross the wire. Both apps bundle the same
RealityKitContent, so a frame is a few KB.

## Transport

`MultipeerTransport` (local network, no account, no FaceTime call) ships by default.
Conform to `MirrorTransport` for GroupActivities/SharePlay or a socket relay. Host
Info.plist needs `NSLocalNetworkUsageDescription` and `NSBonjourServices`
`_dl-mirror._tcp`, `_dl-mirror._udp`. `LoopbackTransport` runs both ends in one process.

## Shared code rules

1. Scene code that builds entities goes in a target both platforms compile.
2. Wrap visionOS-only calls (`ImmersiveSpace`, `HandTrackingProvider`, `ManipulationComponent`)
   in `#if os(visionOS)` outside the provider.
3. Systems that move entities run only on the headset. The phone gets results as transforms,
   so physics and gameplay logic need no iOS port.
4. Entities spawned at runtime need a deterministic tag id; call `refreshTags()` on the
   receiver after the provider spawns its copy (usually from an `Event`).

## Roadmap

- Mirror Cam app (`org.dicyaninlabs.mirrorcam`): generic recorder that loads any provider
  from a dropped-in Swift package and handles takes, slates and export.
- Headset anchor alignment: wearer taps a point, phone taps the same point, so AR mode lines
  the virtual content up with the real room.
- Ghost hands and headset avatar rendered from the streamed poses.
- Timestamped jitter buffer so footage stays smooth under Wi-Fi loss.
- Record frames to disk on the headset and re-render offline on the phone or Mac at any camera.

## Layout

| File | Contents |
|---|---|
| Provider.swift | `RealityMirrorProviding`, `MirrorTagComponent` |
| Frame.swift | wire types |
| Broadcaster.swift | headset sampler |
| Receiver.swift | phone applier with smoothing |
| CameraRig.swift | camera modes |
| MirrorView.swift, Recorder.swift | iOS view and ReplayKit recorder |
| Transport.swift, MultipeerTransport.swift | transports |
