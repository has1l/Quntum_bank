import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var authManager: AuthManager
    @State private var showTrustedAccountSheet = false
    @State private var trustCode = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Мои доверенные лица (только если этот пользователь не добавил меня)
    var myTrustedUsers: [User] {
        guard let current = authManager.currentUser, let trusted = current.trustedUsers as? Set<User> else { return [] }
        return trusted.filter { user in
            guard let theirTrusted = user.trustedUsers as? Set<User> else { return true }
            return !theirTrusted.contains(where: { $0.id == current.id })
        }
    }
    
    // Я — доверенное лицо для (только если я у них, а их нет у меня)
    var iAmTrustedFor: [User] {
        guard let current = authManager.currentUser, let currentId = current.id else { return [] }
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        let users = (try? viewContext.fetch(fetchRequest)) ?? []
        let myTrusted = (current.trustedUsers as? Set<User>) ?? []
        return users.filter { user in
            guard let trusted = user.trustedUsers as? Set<User> else { return false }
            let iAmTrusted = trusted.contains(where: { $0.id == currentId })
            let theyAreMyTrusted = myTrusted.contains(where: { $0.id == user.id })
            return iAmTrusted && !theyAreMyTrusted
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Внешний вид")) {
                    Toggle("Тёмная тема", isOn: Binding(
                        get: { authManager.currentUser?.isDarkMode ?? false },
                        set: { newValue in
                            authManager.currentUser?.isDarkMode = newValue
                            try? viewContext.save()
                            authManager.objectWillChange.send()
                        }
                    ))
                }
                // Отладочный print для myTrustedUsers
                let _ = {
                    print("myTrustedUsers count:", myTrustedUsers.count)
                    for u in myTrustedUsers {
                        print("myTrustedUser:", u.name ?? "-", u.id?.uuidString ?? "nil")
                    }
                }()
                
                // Секция: Мои доверенные лица (для пенсионера и доверенного лица)
                Section(header: Text("Мои доверенные лица")) {
                    if !myTrustedUsers.isEmpty {
                        ForEach(myTrustedUsers, id: \ .id) { user in
                            HStack {
                                Text(user.name ?? "-")
                                Spacer()
                                Text(user.phone ?? "")
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("Нет доверенных лиц")
                            .foregroundColor(.secondary)
                    }
                    Button("Привязать аккаунт доверия") {
                        showTrustedAccountSheet = true
                    }
                    if let currentUser = authManager.currentUser {
                        HStack {
                            Text("Ваш код доверия")
                            Spacer()
                            Text(currentUser.trustCode ?? "-")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Секция: Я — доверенное лицо для (для любого, если есть такие связи)
                Section(header: Text("Я — доверенное лицо для:")) {
                    if !iAmTrustedFor.isEmpty {
                        ForEach(iAmTrustedFor, id: \ .id) { user in
                            HStack {
                                Text(user.name ?? "-")
                                Spacer()
                                Text(user.phone ?? "")
                                    .foregroundColor(.secondary)
                                Button("Отвязать") {
                                    unbindFrom(user: user)
                                }
                                .foregroundColor(.red)
                            }
                        }
                    } else {
                        Text("Нет пользователей, для которых вы доверенное лицо")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button("Выйти") {
                        authManager.logout()
                    }
                    .foregroundColor(.red)
                }
                // Временная отладочная кнопка для очистки себя из trustedUsers у всех
                Section {
                    Button("Очистить себя из trustedUsers у всех (отладка)") {
                        removeSelfFromAllTrustedUsers()
                    }
                    .foregroundColor(.orange)
                }
                // Временная отладочная кнопка для очистки trustedUsers у Даши
                Section {
                    Button("Очистить trustedUsers у Даши (отладка)") {
                        clearAllTrustedForDasha()
                    }
                    .foregroundColor(.orange)
                }
            }
            .navigationTitle("Настройки")
            .sheet(isPresented: $showTrustedAccountSheet) {
                TrustedAccountView(trustCode: $trustCode, showError: $showError, errorMessage: $errorMessage)
            }
            .alert("Ошибка", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func unbindFrom(user: User) {
        guard let current = authManager.currentUser else { return }
        
        // Проверяем, является ли текущий пользователь доверенным лицом
        if current.role == "trusted" {
            // Удаляем current из trustedUsers у user
            if let trusted = user.trustedUsers?.mutableCopy() as? NSMutableSet {
                trusted.remove(current)
                user.trustedUsers = trusted.copy() as? NSSet
            }
            
            // Проверяем, есть ли еще пользователи, для которых current является доверенным лицом
            let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
            let users = (try? viewContext.fetch(fetchRequest)) ?? []
            let isStillTrusted = users.contains { other in
                guard let trusted = other.trustedUsers as? Set<User> else { return false }
                return trusted.contains(where: { $0.id == current.id })
            }
            
            // Если больше никто не привязал current как доверенное лицо — меняем роль обратно на pensioner
            if !isStillTrusted {
                current.role = "pensioner"
            }
            
            try? viewContext.save()
            viewContext.refreshAllObjects()
            authManager.objectWillChange.send()
            // Проверка trustedUsers у Даши после удаления
            for user in users {
                if user.name == "Даша" {
                    if let trusted = user.trustedUsers as? Set<User> {
                        print("После удаления, trustedUsers у Даши:")
                        for t in trusted {
                            print("  ", t.name ?? "-", t.id?.uuidString ?? "nil")
                        }
                    } else {
                        print("После удаления, trustedUsers у Даши: nil")
                    }
                }
            }
        }
    }
    
    private func removeSelfFromAllTrustedUsers() {
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        let users = (try? viewContext.fetch(fetchRequest)) ?? []
        guard let current = authManager.currentUser, let currentId = current.id else { return }
        for user in users {
            if let trustedUsers = user.trustedUsers as? Set<User> {
                for t in trustedUsers {
                    if t.id == currentId {
                        user.removeFromTrustedUsers(t)
                        print("Удалил себя из trustedUsers у пользователя:", user.name ?? "-", user.id?.uuidString ?? "nil")
                    }
                }
            }
        }
        try? viewContext.save()
        viewContext.refreshAllObjects()
        authManager.objectWillChange.send()
        // Проверка trustedUsers у Даши после удаления
        for user in users {
            if user.name == "Даша" {
                if let trusted = user.trustedUsers as? Set<User> {
                    print("После удаления, trustedUsers у Даши:")
                    for t in trusted {
                        print("  ", t.name ?? "-", t.id?.uuidString ?? "nil")
                    }
                } else {
                    print("После удаления, trustedUsers у Даши: nil")
                }
            }
        }
    }
    
    private func clearAllTrustedForDasha() {
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        let users = (try? viewContext.fetch(fetchRequest)) ?? []
        for user in users {
            if user.name == "Даша" {
                user.trustedUsers = NSSet()
                print("Очистил trustedUsers у Даши")
            }
        }
        try? viewContext.save()
        viewContext.refreshAllObjects()
        authManager.objectWillChange.send()
    }
} 