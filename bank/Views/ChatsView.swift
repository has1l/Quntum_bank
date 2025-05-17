import SwiftUI
import CoreData

// Добавляем enum вне структур
enum ChatType {
    case support
    case trusted(User)
}

struct ChatsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var authManager: AuthManager
    @State private var showCallView = false
    @State private var isIncomingCall = false
    
    @FetchRequest(
        entity: User.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \User.name, ascending: true)]
    ) var allUsers: FetchedResults<User>

    var trustedUsers: [User] {
        guard let current = authManager.currentUser, let trusted = current.trustedUsers as? Set<User> else { return [] }
        return Array(trusted)
    }

    var usersWhereCurrentIsTrusted: [User] {
        guard let current = authManager.currentUser, let currentId = current.id else { return [] }
        return allUsers.filter { user in
            guard let trusted = user.trustedUsers as? Set<User> else { return false }
            return trusted.contains(where: { $0.id == currentId })
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                List {
                    let userId = authManager.currentUser?.phone ?? authManager.currentUser?.id?.uuidString ?? "unknown"
                    NavigationLink(destination: ChatDetailView(chatType: .support, userId: userId)) {
                        HStack {
                            Image(systemName: "headphones")
                                .foregroundColor(.blue)
                            Text("Поддержка")
                        }
                    }
                    
                    let currentId = authManager.currentUser?.id
                    let trustedByIds = Set(usersWhereCurrentIsTrusted.map { $0.id })
                    let onlyTrusted = trustedUsers.filter { $0.id != currentId && !trustedByIds.contains($0.id) }
                    let onlyTrustedBy = usersWhereCurrentIsTrusted.filter { $0.id != currentId }
                    
                    ForEach(onlyTrustedBy, id: \.id) { user in
                        NavigationLink(destination: ChatDetailView(chatType: .trusted(user), userId: userId)) {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.orange)
                                Text(user.name ?? "-")
                            }
                        }
                    }
                    
                    ForEach(onlyTrusted, id: \.id) { user in
                        NavigationLink(destination: ChatDetailView(chatType: .trusted(user), userId: userId)) {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.green)
                                Text(user.name ?? "-")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Чаты")
        }
    }
}

struct ChatDetailView: View {
    let chatType: ChatType
    let userId: String
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var authManager: AuthManager
    @State private var messageText = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var rtcClient: RTCClient? = nil
    @State private var showCallView = false
    @State private var callStatus: String = ""
    @StateObject private var signalingClient: SignalingClient
    
    @FetchRequest(
        entity: Transaction.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
    ) var pendingTransactions: FetchedResults<Transaction>
    
    @FetchRequest(
        entity: Message.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Message.date, ascending: true)]
    ) var allMessages: FetchedResults<Message>
    
    var chatMessages: [Message] {
        switch chatType {
        case .support:
            return [] // support messages are not stored
        case .trusted(let user):
            guard let current = authManager.currentUser else { return [] }
            return allMessages.filter { ( ($0.sender == current && $0.recipient == user) || ($0.sender == user && $0.recipient == current) ) }
        }
    }
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if case .support = chatType {
                        ForEach(supportMessages) { message in
                            ChatBubble(message: message)
                        }
                    } else {
                        ForEach(chatMessages, id: \.id) { message in
                            ChatBubble(message: ChatMessage(id: message.id ?? UUID(), text: message.text ?? "", isFromUser: message.sender == authManager.currentUser, date: message.date ?? Date()))
                        }
                    }
                    
                    if case .trusted(let trustedUser) = chatType {
                        if isTrustedPerson {
                            ForEach(pendingTransactions.filter { transaction in
                                transaction.requiresApproval && 
                                !transaction.isApproved && 
                                transaction.status == "pending" &&
                                transaction.sender?.id == trustedUser.id
                            }, id: \.id) { transaction in
                                PendingTransferView(transaction: transaction, viewContext: viewContext)
                            }
                        }
                    }
                }
                .padding()
            }
            
            HStack {
                TextField("Сообщение", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
        }
        .navigationTitle(chatTitle)
        .toolbar {
            if case .support = chatType {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        startCall()
                    }) {
                        Image(systemName: "phone.fill")
                            .font(.title)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .sheet(isPresented: $showCallView) {
            CallView(onEnd: {
                showCallView = false
                rtcClient?.endCall()
            }, callStatus: $callStatus)
        }
        .onAppear {
            signalingClient.initialize(userId: userId)
            markMessagesAsRead()
        }
        .alert("Ошибка", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var isTrustedPerson: Bool {
        if case .trusted(let trustedUser) = chatType {
            return trustedUser.trustedUsers?.contains(where: { ($0 as? User)?.id == authManager.currentUser?.id }) == true
        }
        return false
    }
    
    private var chatTitle: String {
        switch chatType {
        case .support:
            return "Поддержка"
        case .trusted(let user):
            return user.name ?? "Чат"
        }
    }
    
    // Для поддержки — имитация сообщений
    private var supportMessages: [ChatMessage] {
        [
            ChatMessage(id: UUID(), text: "Здравствуйте! Чем можем помочь?", isFromUser: false, date: Date()),
        ]
    }
    
    private func markMessagesAsRead() {
        guard case .trusted(let user) = chatType, let current = authManager.currentUser else { return }
        let unread = allMessages.filter { $0.sender == user && $0.recipient == current && $0.isRead == false }
        for msg in unread {
            msg.isRead = true
        }
        if !unread.isEmpty {
            try? viewContext.save()
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        switch chatType {
        case .support:
            // Для поддержки — имитация ответа
            let userMessage = ChatMessage(id: UUID(), text: messageText, isFromUser: true, date: Date())
            messageText = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let response = ChatMessage(
                    id: UUID(),
                    text: "Спасибо за ваше сообщение. Мы обработаем его в ближайшее время.",
                    isFromUser: false,
                    date: Date()
                )
                // Можно добавить в массив supportMessages, если нужно хранить историю
            }
        case .trusted(let user):
            guard let current = authManager.currentUser else { return }
            let newMessage = Message(context: viewContext)
            newMessage.id = UUID()
            newMessage.text = messageText
            newMessage.date = Date()
            newMessage.sender = current
            newMessage.recipient = user
            newMessage.isRead = false
            do {
                try viewContext.save()
                messageText = ""
            } catch {
                errorMessage = "Ошибка при отправке сообщения"
                showError = true
            }
        }
    }
    
    private func startCall() {
        print("[ChatDetailView] startCall tapped")
        switch chatType {
        case .support:
            guard let user = authManager.currentUser else {
                print("[ChatDetailView] Нет userId для звонка")
                return
            }
            let userId = user.phone ?? user.id?.uuidString ?? "unknown"
            let userName = user.name ?? userId
            let operatorId = "operator" // Замените на реальный id оператора
            callStatus = "Ожидание ответа оператора..."
            showCallView = true
            signalingClient.sendCallRequest(name: userName)
            signalingClient.onCallAccepted { operatorId in
                DispatchQueue.main.async {
                    callStatus = "Оператор принял звонок, соединение..."
                    rtcClient = RTCClient(userId: userId, remoteUserId: operatorId)
                    rtcClient?.startCall { success in
                        print("[ChatDetailView] startCall completion: \(success)")
                        // Можно обновлять callStatus здесь
                    }
                }
            }
        case .trusted(let user):
            guard let current = authManager.currentUser, let currentId = current.id?.uuidString, let remoteId = user.id?.uuidString else {
                print("[ChatDetailView] Нет id для trusted звонка")
                return
            }
            rtcClient = RTCClient(userId: currentId, remoteUserId: remoteId)
            callStatus = "Звонок..."
            showCallView = true
            rtcClient?.startCall { success in
                print("[ChatDetailView] startCall completion: \(success)")
                // Можно обновлять callStatus здесь
            }
        }
    }
    
    init(chatType: ChatType, userId: String) {
        self.chatType = chatType
        self.userId = userId
        _signalingClient = StateObject(wrappedValue: SignalingClient.shared)
    }
}

struct PendingTransferView: View {
    let transaction: Transaction
    let viewContext: NSManagedObjectContext
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Перевод на сумму \(String(format: "%.2f", transaction.amount)) ₽")
                .font(.headline)
            
            if let sender = transaction.sender {
                Text("От: \(sender.name ?? "-")")
                    .font(.subheadline)
            }
            
            if let date = transaction.date {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                Button("Одобрить") {
                    approveTransfer()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Отклонить") {
                    rejectTransfer()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 2)
        .alert("Ошибка", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func approveTransfer() {
        transaction.isApproved = true
        transaction.status = "completed"
        // Зачисляем деньги получателю
        if let recipient = transaction.recipientPhone {
            let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "phone == %@", recipient)
            if let recipientUser = try? viewContext.fetch(fetchRequest).first {
                recipientUser.balance += transaction.amount
            }
        }
        // Списываем деньги у отправителя
        if let sender = transaction.sender {
            sender.balance -= transaction.amount
        }
        do {
            try viewContext.save()
        } catch {
            errorMessage = "Ошибка при одобрении перевода"
            showError = true
        }
    }
    
    private func rejectTransfer() {
        transaction.isApproved = false
        transaction.status = "rejected"
        do {
            try viewContext.save()
        } catch {
            errorMessage = "Ошибка при отклонении перевода"
            showError = true
        }
    }
}

struct ChatMessage: Identifiable {
    let id: UUID
    let text: String
    let isFromUser: Bool
    let date: Date
}

struct ChatBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isFromUser {
                Spacer()
            }
            
            Text(message.text)
                .padding()
                .background(message.isFromUser ? Color.blue : Color(.systemGray5))
                .foregroundColor(message.isFromUser ? .white : .primary)
                .cornerRadius(20)
            
            if !message.isFromUser {
                Spacer()
            }
        }
    }
} 