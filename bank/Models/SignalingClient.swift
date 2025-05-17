import Foundation
import WebRTC
import SocketIO

class SignalingClient: ObservableObject {
    static let shared = SignalingClient()
    
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var userId: String?
    private let serverUrl = URL(string: "http://5.227.27.234:3001")!
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    @Published var isConnected: Bool = false
    private var pendingCallRequest: String? = nil
    private var isConnecting: Bool = false

    var onOffer: ((RTCSessionDescription) -> Void)?
    var onAnswer: ((RTCSessionDescription) -> Void)?
    var onIceCandidate: ((RTCIceCandidate) -> Void)?
    var onConnectionStateChanged: ((Bool) -> Void)?

    private init() {
        setupSocket()
    }

    func initialize(userId: String) {
        self.userId = userId
        if isConnected {
            socket?.emit("join", ["userId": userId])
        }
    }

    private func setupSocket() {
        if manager != nil {
            print("[SignalingClient] Socket already exists, reusing")
            return
        }

        let config: SocketIOClientConfiguration = [
            .log(true),
            .compress,
            .reconnects(true),
            .reconnectAttempts(maxReconnectAttempts),
            .forceWebsockets(true),
            .forcePolling(false),
            .path("/socket.io/"),
            .secure(false),
            .selfSigned(true)
        ]
        
        manager = SocketManager(socketURL: serverUrl, config: config)
        
        guard let socket = manager?.defaultSocket else {
            print("[SignalingClient] Failed to create socket")
            return
        }
        
        self.socket = socket
        setupHandlers()
        
        if !isConnecting {
            isConnecting = true
            socket.connect()
        }
    }

    private func setupHandlers() {
        guard let socket = socket else { return }

        socket.on(clientEvent: .connect) { [weak self] data, ack in
            print("[SignalingClient] Socket connected")
            self?.reconnectAttempts = 0
            self?.onConnectionStateChanged?(true)
            self?.isConnected = true
            self?.isConnecting = false
            
            // Отправляем JOIN после подключения
            if let userId = self?.userId {
                print("[SignalingClient] Sending join with userId: \(userId)")
                socket.emit("join", ["userId": userId])
            }
            
            if let pending = self?.pendingCallRequest {
                print("[SignalingClient] Sending pending call request: \(pending)")
                self?.sendCallRequest(name: pending)
                self?.pendingCallRequest = nil
            }
        }

        socket.on(clientEvent: .disconnect) { [weak self] data, ack in
            print("[SignalingClient] Socket disconnected")
            self?.onConnectionStateChanged?(false)
            self?.isConnected = false
            self?.isConnecting = false
        }

        socket.on(clientEvent: .error) { [weak self] data, ack in
            print("[SignalingClient] Socket error: \(data)")
            self?.handleReconnect()
        }

        socket.on(clientEvent: .reconnect) { [weak self] data, ack in
            print("[SignalingClient] Socket reconnecting...")
            self?.reconnectAttempts += 1
        }

        socket.on("signal") { [weak self] data, ack in
            guard let self = self,
                  let dict = data.first as? [String: Any],
                  let type = dict["type"] as? String,
                  let from = dict["from"] as? String,
                  let payload = dict["data"] as? [String: Any] else {
                print("[SignalingClient] Invalid signal format")
                return
            }
            
            print("[SignalingClient] Received signal: \(type) from \(from)")
            
            switch type {
            case "offer":
                if let sdp = payload["sdp"] as? String {
                    let offer = RTCSessionDescription(type: .offer, sdp: sdp)
                    self.onOffer?(offer)
                }
            case "answer":
                if let sdp = payload["sdp"] as? String {
                    let answer = RTCSessionDescription(type: .answer, sdp: sdp)
                    self.onAnswer?(answer)
                }
            case "ice-candidate":
                if let sdp = payload["candidate"] as? String,
                   let sdpMLineIndex = payload["sdpMLineIndex"] as? Int32,
                   let sdpMid = payload["sdpMid"] as? String? {
                    let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
                    self.onIceCandidate?(candidate)
                }
            default:
                print("[SignalingClient] Unknown signal type: \(type)")
            }
        }
    }

    private func handleReconnect() {
        if reconnectAttempts < maxReconnectAttempts {
            print("[SignalingClient] Attempting to reconnect...")
            socket?.connect()
        } else {
            print("[SignalingClient] Max reconnect attempts reached")
            onConnectionStateChanged?(false)
        }
    }

    func sendOffer(_ offer: RTCSessionDescription, to remoteUserId: String) {
        guard let socket = socket, let userId = userId else {
            print("[SignalingClient] Socket or userId is not available")
            return
        }
        
        let payload: [String: Any] = [
            "type": "offer",
            "from": userId,
            "to": remoteUserId,
            "data": ["sdp": offer.sdp]
        ]
        socket.emit("signal", payload)
    }

    func sendAnswer(_ answer: RTCSessionDescription, to remoteUserId: String) {
        guard let socket = socket, let userId = userId else {
            print("[SignalingClient] Socket or userId is not available")
            return
        }
        
        let payload: [String: Any] = [
            "type": "answer",
            "from": userId,
            "to": remoteUserId,
            "data": ["sdp": answer.sdp]
        ]
        socket.emit("signal", payload)
    }

    func sendIceCandidate(_ candidate: RTCIceCandidate, to remoteUserId: String) {
        guard let socket = socket, let userId = userId else {
            print("[SignalingClient] Socket or userId is not available")
            return
        }
        
        let payload: [String: Any] = [
            "type": "ice-candidate",
            "from": userId,
            "to": remoteUserId,
            "data": [
                "candidate": candidate.sdp,
                "sdpMLineIndex": candidate.sdpMLineIndex,
                "sdpMid": candidate.sdpMid as Any
            ]
        ]
        socket.emit("signal", payload)
    }

    func sendCallRequest(name: String?) {
        print("[SignalingClient] sendCallRequest CALLED with name=\(name ?? "nil")")
        guard let userId = userId else {
            print("[SignalingClient] userId is not set")
            return
        }
        
        if isConnected {
            print("[SignalingClient] sendCallRequest: userId=\(userId), name=\(name ?? userId)")
            socket?.emit("call_request", ["userId": userId, "name": name ?? userId])
        } else {
            print("[SignalingClient] sendCallRequest: not connected, will send after connect")
            pendingCallRequest = name
            
            if !isConnecting {
                print("[SignalingClient] Attempting to connect socket...")
                socket?.connect()
            }
        }
    }

    func onCallAccepted(handler: @escaping (String) -> Void) {
        guard let socket = socket else { return }
        socket.on("call_accepted") { data, ack in
            if let dict = data.first as? [String: Any], let operatorId = dict["operatorId"] as? String {
                handler(operatorId)
            }
        }
    }

    func disconnect() {
        socket?.disconnect()
        manager = nil
        socket = nil
        userId = nil
        isConnected = false
        isConnecting = false
    }
} 