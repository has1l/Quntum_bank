import SwiftUI
import WebRTC

struct SupportChatView: View {
    @State private var isCallActive = false
    @State private var rtcClient: RTCClient?
    @State private var callStatus: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showCallView = false
    @EnvironmentObject var authManager: AuthManager
    
    // Укажите идентификатор оператора (например, phone или UUID)
    let operatorId = "operator" // Замените на реальный id оператора
    private let signalingClient = SignalingClient.shared

    var body: some View {
        VStack {
            // Заголовок чата
            Text("Поддержка")
                .font(.title)
                .padding()

            ScrollView {
                // Ваши сообщения чата
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    if isCallActive {
                        endCall()
                    } else {
                        startCall()
                    }
                }) {
                    Image(systemName: isCallActive ? "phone.down.fill" : "phone.fill")
                        .font(.title)
                        .foregroundColor(isCallActive ? .red : .green)
                }
            }
        }
        .sheet(isPresented: $showCallView) {
            CallView(onEnd: {
                showCallView = false
                endCall()
            }, callStatus: $callStatus)
        }
        .alert("Ошибка", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            if let user = authManager.currentUser {
                signalingClient.initialize(userId: user.phone ?? user.id?.uuidString ?? "unknown")
            }
        }
    }

    private func startCall() {
        guard let user = authManager.currentUser else {
            errorMessage = "Не удалось получить идентификатор пользователя"
            showError = true
            return
        }
        let userId = user.phone ?? user.id?.uuidString ?? "unknown"
        let userName = user.name ?? userId
        callStatus = "Ожидание ответа оператора..."
        showCallView = true
        signalingClient.sendCallRequest(name: userName)
        signalingClient.onCallAccepted { operatorId in
            DispatchQueue.main.async {
                callStatus = "Оператор принял звонок, соединение..."
                rtcClient = RTCClient(userId: userId, remoteUserId: operatorId)
                rtcClient?.onConnectionStateChanged = { state in
                    DispatchQueue.main.async {
                        switch state {
                        case .connected:
                            callStatus = "Звонок активен"
                            isCallActive = true
                        case .disconnected, .failed:
                            callStatus = "Звонок прерван"
                            isCallActive = false
                        case .checking:
                            callStatus = "Проверка соединения..."
                        default:
                            callStatus = "Статус: \(state)"
                        }
                    }
                }
                rtcClient?.onError = { error in
                    DispatchQueue.main.async {
                        errorMessage = "Ошибка: \(error.localizedDescription)"
                        showError = true
                        callStatus = "Ошибка соединения"
                        isCallActive = false
                    }
                }
                rtcClient?.startCall { success in
                    DispatchQueue.main.async {
                        if !success {
                            errorMessage = "Не удалось начать звонок"
                            showError = true
                            callStatus = "Ошибка"
                        }
                    }
                }
            }
        }
    }
    
    private func endCall() {
        rtcClient?.endCall()
        isCallActive = false
        callStatus = "Звонок завершен"
        rtcClient = nil
    }
}

struct CallView: View {
    var onEnd: () -> Void
    @Binding var callStatus: String

    var body: some View {
        VStack(spacing: 30) {
            Text("Звонок в поддержку")
                .font(.title)
            Text(callStatus)
                .foregroundColor(.blue)
            Button(action: onEnd) {
                Image(systemName: "phone.down.fill")
                    .font(.largeTitle)
                    .foregroundColor(.red)
            }
            .padding(.top, 40)
        }
        .padding()
    }
} 