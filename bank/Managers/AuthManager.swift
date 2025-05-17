import Foundation
import CoreData
import SwiftUI

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    
    func login(phone: String, password: String, context: NSManagedObjectContext) -> Bool {
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "phone == %@ AND password == %@", phone, password)
        
        do {
            let users = try context.fetch(fetchRequest)
            if let user = users.first {
                currentUser = user
                isAuthenticated = true
                return true
            }
        } catch {
            print("Ошибка при входе: \(error)")
        }
        return false
    }
    
    func register(name: String, phone: String, password: String, dateOfBirth: Date, context: NSManagedObjectContext) -> Bool {
        // ВРЕМЕННО: выводим всех пользователей в базе
        let allUsersRequest: NSFetchRequest<User> = User.fetchRequest()
        let allUsers = try? context.fetch(allUsersRequest)
        print("ВСЕ ПОЛЬЗОВАТЕЛИ В БАЗЕ:")
        allUsers?.forEach { print($0.phone ?? "nil") }
        
        // Проверка на существующий номер телефона
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "phone == %@", phone)
        
        do {
            let existingUsers = try context.fetch(fetchRequest)
            if !existingUsers.isEmpty {
                return false
            }
            
            // Core Data способ создания пользователя
            let user = User(context: context)
            user.id = UUID()
            user.name = name
            user.phone = phone
            user.password = password
            user.dateOfBirth = dateOfBirth
            user.trustCode = generateTrustCode()
            user.balance = 0.0
            user.isDarkMode = false
            user.role = "pensioner"
            
            try context.save()
            
            currentUser = user
            isAuthenticated = true
            return true
        } catch {
            print("Ошибка при регистрации: \(error)")
            return false
        }
    }
    
    private func generateTrustCode() -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let numbers = "0123456789"
        let code = String((0..<3).map { _ in letters.randomElement()! }) +
                   String((0..<3).map { _ in numbers.randomElement()! })
        return code
    }
    
    func logout() {
        currentUser = nil
        isAuthenticated = false
    }
} 