import SwiftUI
import CoreData

struct PaymentsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var authManager: AuthManager
    @State private var recipientPhone = ""
    @State private var amount = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Перевод")) {
                    TextField("Телефон получателя", text: $recipientPhone)
                        .keyboardType(.phonePad)
                    
                    TextField("Сумма", text: $amount)
                        .keyboardType(.decimalPad)
                }
                
                Section {
                    Button("Перевести") {
                        performTransfer()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .listRowBackground(Color.blue)
                }
            }
            .navigationTitle("Платежи")
            .alert("Ошибка", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Успешно", isPresented: $showSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Перевод выполнен успешно")
            }
        }
    }
    
    private func performTransfer() {
        guard let amountDouble = Double(amount),
              amountDouble > 0,
              amountDouble <= (authManager.currentUser?.balance ?? 0) else {
            errorMessage = "Неверная сумма"
            showError = true
            return
        }
        
        guard !recipientPhone.isEmpty else {
            errorMessage = "Введите номер телефона получателя"
            showError = true
            return
        }
        
        // Ищем пользователя-получателя
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "phone == %@", recipientPhone)
        var recipientUser: User?
        do {
            let users = try viewContext.fetch(fetchRequest)
            recipientUser = users.first
        } catch {
            errorMessage = "Ошибка поиска получателя"
            showError = true
            return
        }
        guard let receiver = recipientUser else {
            errorMessage = "Пользователь с таким телефоном не найден"
            showError = true
            return
        }
        
        let current = authManager.currentUser!
        let isPensioner = (current.role == "pensioner")
        
        if isPensioner && amountDouble >= 50000 {
            // Создаем транзакцию, требующую подтверждения
            let transaction = Transaction(context: viewContext)
            transaction.id = UUID()
            transaction.amount = amountDouble
            transaction.date = Date()
            transaction.recipientPhone = recipientPhone
            transaction.sender = current
            transaction.status = "pending"
            transaction.requiresApproval = true
            transaction.isApproved = false
            
            do {
                try viewContext.save()
                showSuccess = true
                recipientPhone = ""
                amount = ""
            } catch {
                errorMessage = "Ошибка при создании перевода"
                showError = true
            }
        } else {
            // Выполняем перевод сразу
            let transaction = Transaction(context: viewContext)
            transaction.id = UUID()
            transaction.amount = amountDouble
            transaction.date = Date()
            transaction.recipientPhone = recipientPhone
            transaction.sender = current
            transaction.status = "completed"
            transaction.requiresApproval = false
            transaction.isApproved = true
            
            // Обновляем балансы
            current.balance -= amountDouble
            receiver.balance += amountDouble
            
            do {
                try viewContext.save()
                showSuccess = true
                recipientPhone = ""
                amount = ""
            } catch {
                errorMessage = "Ошибка при сохранении транзакции"
                showError = true
            }
        }
    }
} 