import SwiftUI
import CoreData

struct HomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var authManager: AuthManager
    @State private var isEditingBalance = false
    @State private var tempBalance: String = ""
    @State private var showSpendingSheet = false
    
    @FetchRequest(
        entity: Transaction.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
    ) var allTransactions: FetchedResults<Transaction>
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Приветствие
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "person.crop.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .foregroundColor(.blue)
                        }
                        VStack(alignment: .leading) {
                            Text("Добро пожаловать,")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(authManager.currentUser?.name ?? "")
                                .font(.title2).bold()
                        }
                        Spacer()
                    }
                    .padding(.horizontal)

                    // Блок с тратами за месяц (интерактивный)
                    Button(action: { showSpendingSheet = true }) {
                        monthSpendingCard
                    }
                    .buttonStyle(PlainButtonStyle())
                    .sheet(isPresented: $showSpendingSheet) {
                        SpendingHistorySheet(allTransactions: allTransactions, currentUser: authManager.currentUser)
                    }

                    // Карточка баланса
                    balanceCard
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
        }
    }
    
    private var monthSpendingCard: some View {
        let user = authManager.currentUser
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let outgoing = allTransactions.filter {
            $0.sender == user &&
            $0.date != nil &&
            $0.date! >= startOfMonth &&
            $0.status == "completed"
        }
        let totalSpent = outgoing.reduce(0.0) { $0 + $1.amount }
        let limit: Double = 100_000
        let progress = min(totalSpent / limit, 1.0)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundColor(.purple)
                    .font(.title2)
                Text("Траты за месяц")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            HStack(alignment: .lastTextBaseline) {
                Text("\(String(format: "%.0f", totalSpent)) ₽")
                    .font(.system(size: 32, weight: .bold))
                Spacer()
                Text("Лимит: \(Int(limit)) ₽")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: progress)
                .accentColor(progress < 0.8 ? .blue : .red)
            Text("\(outgoing.count) операций за месяц")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
    
    private var balanceCard: some View {
        VStack {
            if isEditingBalance {
                TextField("Баланс", text: $tempBalance)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .multilineTextAlignment(.center)
                    .font(.title)
                    .padding()
                
                HStack {
                    Button("Отмена") {
                        isEditingBalance = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Сохранить") {
                        if let newBalance = Double(tempBalance),
                           newBalance <= 1_000_000 {
                            authManager.currentUser?.balance = newBalance
                            try? viewContext.save()
                        }
                        isEditingBalance = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("\(String(format: "%.2f", authManager.currentUser?.balance ?? 0)) ₽")
                    .font(.system(size: 40, weight: .bold))
                    .padding()
                
                Button("Изменить") {
                    tempBalance = String(format: "%.2f", authManager.currentUser?.balance ?? 0)
                    isEditingBalance = true
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(radius: 5)
        .padding(.horizontal)
    }
    
    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Последние операции")
                .font(.headline)
                .padding(.horizontal)
            
            let userPhone = authManager.currentUser?.phone ?? ""
            let user = authManager.currentUser
            let relevant = allTransactions.filter {
                $0.sender == user || $0.recipientPhone == userPhone
            }
            
            if relevant.isEmpty {
                Text("Нет операций")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(relevant.prefix(10), id: \.id) { transaction in
                    TransactionRow(transaction: transaction, currentUser: user)
                }
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    let currentUser: User?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    Text(transaction.recipientPhone ?? "-")
                        .font(.headline)
                    if let date = transaction.date {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("-")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(amountText)
                    .foregroundColor(amountColor)
            }
            if transaction.status == "pending" {
                Text("Ожидает подтверждения от доверенного лица")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if transaction.status == "rejected" {
                Text("Отклонено доверенным лицом")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(radius: 2)
        .padding(.horizontal)
    }
    
    private var amountText: String {
        if transaction.sender == currentUser {
            return "-\(String(format: "%.2f", transaction.amount)) ₽"
        } else {
            return "+\(String(format: "%.2f", transaction.amount)) ₽"
        }
    }
    
    private var amountColor: Color {
        if transaction.sender == currentUser {
            return .red
        } else {
            return .green
        }
    }
}

// Новый экран: история расходов
struct SpendingHistorySheet: View {
    let allTransactions: FetchedResults<Transaction>
    let currentUser: User?
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Расходы за месяц")) {
                    ForEach(monthlyOutgoing, id: \ .id) { transaction in
                        SpendingRow(transaction: transaction)
                    }
                }
            }
            .navigationTitle("История расходов")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var monthlyOutgoing: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        return allTransactions.filter {
            $0.sender == currentUser &&
            $0.date != nil &&
            $0.date! >= startOfMonth &&
            $0.status == "completed"
        }
    }
}

struct SpendingRow: View {
    let transaction: Transaction
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(transaction.recipientPhone ?? "-")
                    .font(.headline)
                if let date = transaction.date {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text("-\(String(format: "%.2f", transaction.amount)) ₽")
                .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
} 
