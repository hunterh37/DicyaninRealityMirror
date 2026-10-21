import Foundation
import MultipeerConnectivity

/// Local-network transport. Headset advertises, phone browses and auto-invites.
/// Host app Info.plist needs NSLocalNetworkUsageDescription and
/// NSBonjourServices = ["_dl-mirror._tcp", "_dl-mirror._udp"].
public final class MultipeerTransport: NSObject, MirrorTransport, @unchecked Sendable {
    public enum Role: Sendable { case headset, phone }

    public static let serviceType = "dl-mirror"
    public var onReceive: (@Sendable (Data) -> Void)?
    public var onPeerChange: (@Sendable (Bool) -> Void)?

    private let role: Role
    private let peerID: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private let appID: String

    public init(role: Role, appID: String, displayName: String = ProcessInfo.processInfo.hostName) {
        self.role = role
        self.appID = appID
        peerID = MCPeerID(displayName: String(displayName.prefix(60)))
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    public func start() {
        switch role {
        case .headset:
            let a = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: ["app": appID],
                                              serviceType: Self.serviceType)
            a.delegate = self; a.startAdvertisingPeer(); advertiser = a
        case .phone:
            let b = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
            b.delegate = self; b.startBrowsingForPeers(); browser = b
        }
    }

    public func stop() {
        advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
        session.disconnect()
    }

    public func sendUnreliable(_ data: Data) { send(data, mode: .unreliable) }
    public func sendReliable(_ data: Data) { send(data, mode: .reliable) }

    private func send(_ data: Data, mode: MCSessionSendDataMode) {
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: mode)
    }
}

extension MultipeerTransport: MCSessionDelegate {
    public func session(_ s: MCSession, peer: MCPeerID, didChange state: MCSessionState) {
        onPeerChange?(!s.connectedPeers.isEmpty)
    }
    public func session(_ s: MCSession, didReceive data: Data, fromPeer: MCPeerID) { onReceive?(data) }
    public func session(_ s: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    public func session(_ s: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress) {}
    public func session(_ s: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID,
                        at: URL?, withError: Error?) {}
}

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ a: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer p: MCPeerID,
                           withContext c: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    public func browser(_ b: MCNearbyServiceBrowser, foundPeer p: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard info?["app"] == appID else { return }
        b.invitePeer(p, to: session, withContext: nil, timeout: 10)
    }
    public func browser(_ b: MCNearbyServiceBrowser, lostPeer p: MCPeerID) {}
}
