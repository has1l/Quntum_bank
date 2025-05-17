import SwiftUI
import CoreData

@main
struct QuantumBankApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var authManager = AuthManager()
    
    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                MainTabView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(authManager)
                    .preferredColorScheme(authManager.currentUser?.isDarkMode == true ? .dark : .light)
            } else {
                AuthView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(authManager)
                    .preferredColorScheme(authManager.currentUser?.isDarkMode == true ? .dark : .light)
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: Message.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Message.date, ascending: false)]
    ) var allMessages: FetchedResults<Message>

    var unreadCount: Int {
        guard let current = authManager.currentUser else { return 0 }
        return allMessages.filter { $0.recipient?.id == current.id && $0.isRead == false }.count
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Главная", systemImage: "house.fill")
                }
            
            PaymentsView()
                .tabItem {
                    Label("Платежи", systemImage: "creditcard.fill")
                }
            
            ChatsView()
                .tabItem {
                    Label("Чаты", systemImage: "message.fill")
                        .badge(unreadCount > 0 ? unreadCount : 0)
                }
            
            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gear")
                }
        }
    }
}

class PersistenceController {
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    
    init() {
        container = NSPersistentContainer(name: "QuantumBank")
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Error: \(error.localizedDescription)")
            }
        }
    }
} 