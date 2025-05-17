import SwiftUI

struct AuthView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedTab = 0
    
    // Login fields
    @State private var loginPhone = ""
    @State private var loginPassword = ""
    @State private var rememberMe = false
    
    // Register fields
    @State private var registerName = ""
    @State private var registerPhone = ""
    @State private var registerPassword = ""
    @State private var registerDateOfBirth = Date()
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack {
            Picker("", selection: $selectedTab) {
                Text("Вход").tag(0)
                Text("Регистрация").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            if selectedTab == 0 {
                loginView
            } else {
                registerView
            }
        }
        .alert("Ошибка", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var loginView: some View {
        VStack(spacing: 20) {
            TextField("Телефон", text: $loginPhone)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.phonePad)
            
            SecureField("Пароль", text: $loginPassword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Toggle("Запомнить меня", isOn: $rememberMe)
            
            Button("Войти") {
                if authManager.login(phone: loginPhone, password: loginPassword, context: viewContext) {
                    // Success
                } else {
                    errorMessage = "Неверный телефон или пароль"
                    showError = true
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var registerView: some View {
        VStack(spacing: 20) {
            TextField("Имя", text: $registerName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("Телефон", text: $registerPhone)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.phonePad)
            
            DatePicker("Дата рождения", selection: $registerDateOfBirth, displayedComponents: .date)
            
            SecureField("Пароль", text: $registerPassword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button("Зарегистрироваться") {
                if authManager.register(
                    name: registerName,
                    phone: registerPhone,
                    password: registerPassword,
                    dateOfBirth: registerDateOfBirth,
                    context: viewContext
                ) {
                    // Success
                } else {
                    errorMessage = "Пользователь с таким номером телефона уже существует"
                    showError = true
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
} 