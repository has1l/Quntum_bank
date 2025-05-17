import SwiftUI
import CoreData

struct TrustedAccountView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @Binding var trustCode: String
    @Binding var showError: Bool
    @Binding var errorMessage: String
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Информация")) {
                    Text("Доверенное лицо может подтверждать ваши переводы на сумму от 50 000 ₽")
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Код доверия")) {
                    TextField("Введите код доверия", text: $trustCode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Section {
                    Button("Привязать") {
                        bindTrustedAccount()
                    }
                }
            }
            .navigationTitle("Доверенное лицо")
            .navigationBarItems(trailing: Button("Закрыть") {
                dismiss()
            })
        }
    }
    
    private func bindTrustedAccount() {
        guard !trustCode.isEmpty else {
            errorMessage = "Введите код доверия"
            showError = true
            return
        }
        
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "trustCode == %@", trustCode)
        
        do {
            let users = try viewContext.fetch(fetchRequest)
            if let trustedUser = users.first {
                // Проверяем, не пытаемся ли мы привязать свой собственный аккаунт
                if trustedUser.id == authManager.currentUser?.id {
                    errorMessage = "Нельзя привязать свой собственный аккаунт"
                    showError = true
                    return
                }
                
                // Проверяем, не привязан ли уже этот пользователь
                if let currentTrustedUsers = authManager.currentUser?.trustedUsers as? Set<User>,
                   currentTrustedUsers.contains(where: { $0.id == trustedUser.id }) {
                    errorMessage = "Этот пользователь уже привязан"
                    showError = true
                    return
                }
                
                // Проверяем роль текущего пользователя
                guard let currentUser = authManager.currentUser else { return }
                if currentUser.role == "trusted" {
                    errorMessage = "Доверенное лицо не может добавлять других доверенных лиц"
                    showError = true
                    return
                }
                // Проверяем, не являемся ли мы уже доверенным лицом для этого пользователя
                if let trustedUsersOfTrustedUser = trustedUser.trustedUsers as? Set<User>,
                   trustedUsersOfTrustedUser.contains(where: { $0.id == currentUser.id }) {
                    errorMessage = "Нельзя добавить друг друга в доверенные лица"
                    showError = true
                    return
                }
                // Привязываем доверенного пользователя
                currentUser.addToTrustedUsers(trustedUser)
                // Меняем роль только у trustedUser
                trustedUser.role = "trusted"
                try viewContext.save()
                authManager.objectWillChange.send()
                dismiss()
            } else {
                errorMessage = "Пользователь с таким кодом не найден"
                showError = true
            }
        } catch {
            errorMessage = "Ошибка при привязке доверенного лица"
            showError = true
        }
    }
} 