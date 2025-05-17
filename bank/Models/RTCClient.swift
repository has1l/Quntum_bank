import Foundation
import WebRTC

class RTCClient: NSObject, RTCPeerConnectionDelegate {
    private var peerConnection: RTCPeerConnection?
    private var signalingClient: SignalingClient?
    private var peerConnectionFactory: RTCPeerConnectionFactory = RTCPeerConnectionFactory()
    private let userId: String
    private let remoteUserId: String
    private var isCallActive = false

    var onConnectionStateChanged: ((RTCIceConnectionState) -> Void)?
    var onError: ((Error) -> Void)?

    init(userId: String, remoteUserId: String) {
        self.userId = userId
        self.remoteUserId = remoteUserId
        super.init()
        setupSignalingClient()
    }

    private func setupSignalingClient() {
        signalingClient = SignalingClient.shared
        signalingClient?.initialize(userId: userId)
        signalingClient?.onOffer = { [weak self] offer in
            self?.handleOffer(offer)
        }
        signalingClient?.onAnswer = { [weak self] answer in
            self?.handleAnswer(answer)
        }
        signalingClient?.onIceCandidate = { [weak self] candidate in
            self?.handleIceCandidate(candidate)
        }
        signalingClient?.onConnectionStateChanged = { [weak self] isConnected in
            if !isConnected {
                self?.handleDisconnection()
            }
        }
    }

    func startCall(completion: @escaping (Bool) -> Void) {
        print("[RTCClient] startCall called")
        
        guard !isCallActive else {
            print("[RTCClient] Call is already active")
            completion(false)
            return
        }

        // Создание и настройка RTCPeerConnection
        let configuration = RTCConfiguration()
        configuration.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        guard let peerConnection = peerConnectionFactory.peerConnection(with: configuration, constraints: constraints, delegate: nil) else {
            print("[RTCClient] Failed to create peer connection")
            completion(false)
            return
        }
        
        self.peerConnection = peerConnection
        peerConnection.delegate = self

        // Создание и отправка offer
        peerConnection.offer(for: constraints, completionHandler: { [weak self] offer, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[RTCClient] Failed to create offer: \(error)")
                self.onError?(error)
                completion(false)
                return
            }
            
            guard let offer = offer else {
                print("[RTCClient] Offer is nil")
                completion(false)
                return
            }
            
            print("[RTCClient] Created offer: \(offer)")
            
            self.peerConnection?.setLocalDescription(offer, completionHandler: { error in
                if let error = error {
                    print("[RTCClient] Failed to set local description: \(error)")
                    self.onError?(error)
                    completion(false)
                    return
                }
                
                print("[RTCClient] Local description set, sending offer")
                self.signalingClient?.sendOffer(offer, to: self.remoteUserId)
                self.isCallActive = true
                completion(true)
            })
        })
    }

    private func handleOffer(_ offer: RTCSessionDescription) {
        guard let peerConnection = peerConnection else {
            print("[RTCClient] No peer connection available")
            return
        }
        
        peerConnection.setRemoteDescription(offer, completionHandler: { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                print("[RTCClient] Failed to set remote description: \(error)")
                self.onError?(error)
                return
            }
            
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            self.peerConnection?.answer(for: constraints, completionHandler: { answer, error in
                if let error = error {
                    print("[RTCClient] Failed to create answer: \(error)")
                    self.onError?(error)
                    return
                }
                
                guard let answer = answer else {
                    print("[RTCClient] Answer is nil")
                    return
                }
                
                self.peerConnection?.setLocalDescription(answer, completionHandler: { error in
                    if let error = error {
                        print("[RTCClient] Failed to set local description: \(error)")
                        self.onError?(error)
                        return
                    }
                    
                    self.signalingClient?.sendAnswer(answer, to: self.remoteUserId)
                })
            })
        })
    }

    private func handleAnswer(_ answer: RTCSessionDescription) {
        guard let peerConnection = peerConnection else {
            print("[RTCClient] No peer connection available")
            return
        }
        
        peerConnection.setRemoteDescription(answer) { [weak self] error in
            if let error = error {
                print("[RTCClient] Failed to set remote description: \(error)")
                self?.onError?(error)
            }
        }
    }

    private func handleIceCandidate(_ candidate: RTCIceCandidate) {
        guard let peerConnection = peerConnection else {
            print("[RTCClient] No peer connection available")
            return
        }
        peerConnection.add(candidate) { error in
            if let error = error {
                print("Failed to add ICE candidate: \(error)")
            }
        }
    }

    private func handleDisconnection() {
        print("[RTCClient] Handling disconnection")
        isCallActive = false
        peerConnection?.close()
        peerConnection = nil
    }

    func endCall() {
        print("[RTCClient] Ending call")
        isCallActive = false
        peerConnection?.close()
        peerConnection = nil
        signalingClient?.disconnect()
        signalingClient = nil
    }

    // MARK: - RTCPeerConnectionDelegate

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("[RTCClient] Signaling state changed: \(stateChanged)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("[RTCClient] Stream added")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("[RTCClient] Stream removed")
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("[RTCClient] Should negotiate")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("[RTCClient] ICE connection state changed: \(newState)")
        onConnectionStateChanged?(newState)
        
        if newState == .disconnected || newState == .failed {
            handleDisconnection()
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("[RTCClient] ICE gathering state changed: \(newState)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("[RTCClient] Generated ICE candidate: \(candidate)")
        signalingClient?.sendIceCandidate(candidate, to: remoteUserId)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("[RTCClient] ICE candidates removed")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("[RTCClient] Data channel opened")
    }
} 