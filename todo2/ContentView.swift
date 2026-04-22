import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct TodoItem: Identifiable {
    let id: String
    let title: String
    let isDone: Bool
    let createdAt: Date?
}

enum AuthMode: String, CaseIterable, Identifiable {
    case login = "Sign In"
    case register = "Create Account"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .login:
            return "Welcome back"
        case .register:
            return "Create your account"
        }
    }

    var subtitle: String {
        switch self {
        case .login:
            return "Sign in to continue managing your tasks."
        case .register:
            return "Save your personal tasks securely with Firebase."
        }
    }

    var actionTitle: String {
        switch self {
        case .login:
            return "Sign In"
        case .register:
            return "Create Account"
        }
    }

    var footnote: String {
        switch self {
        case .login:
            return "Need an account? Switch to Create Account."
        case .register:
            return "Already have an account? Switch to Sign In."
        }
    }
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage = ""

    private var authListener: AuthStateDidChangeListenerHandle?

    init() {
        user = Auth.auth().currentUser
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
        }
    }

    deinit {
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
    }

    func login(email: String, password: String) async -> Bool {
        await authenticate(email: email, password: password, mode: .login)
    }

    func register(email: String, password: String) async -> Bool {
        await authenticate(email: email, password: password, mode: .register)
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func authenticate(email: String, password: String, mode: AuthMode) async -> Bool {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedEmail.isEmpty, !cleanedPassword.isEmpty else {
            errorMessage = "Please enter both email and password."
            return false
        }

        guard cleanedPassword.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return false
        }

        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        do {
            switch mode {
            case .login:
                try await Auth.auth().signIn(withEmail: cleanedEmail, password: cleanedPassword)
            case .register:
                try await Auth.auth().createUser(withEmail: cleanedEmail, password: cleanedPassword)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

final class TodoViewModel: ObservableObject {
    @Published var todos: [TodoItem] = []
    @Published var errorMessage = ""

    private let db = Firestore.firestore()
    private let userId: String
    private var listener: ListenerRegistration?

    init(userId: String) {
        self.userId = userId
        startListening()
    }

    deinit {
        listener?.remove()
    }

    func startListening() {
        listener?.remove()
        listener = todosCollection()
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let snapshot else {
                    self.todos = []
                    return
                }

                self.errorMessage = ""
                self.todos = snapshot.documents.map { document in
                    let data = document.data()
                    let title = data["title"] as? String ?? ""
                    let isDone = data["isDone"] as? Bool ?? false
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                    return TodoItem(
                        id: document.documentID,
                        title: title,
                        isDone: isDone,
                        createdAt: createdAt
                    )
                }
            }
    }

    func addTodo(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let data: [String: Any] = [
            "title": trimmed,
            "isDone": false,
            "createdAt": FieldValue.serverTimestamp()
        ]

        todosCollection().addDocument(data: data) { [weak self] error in
            if let error {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func toggleTodoDone(_ todo: TodoItem) {
        todosCollection().document(todo.id).updateData([
            "isDone": !todo.isDone
        ]) { [weak self] error in
            if let error {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func deleteTodos(at offsets: IndexSet) {
        offsets.forEach { index in
            let todo = todos[index]
            todosCollection().document(todo.id).delete { [weak self] error in
                if let error {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func todosCollection() -> CollectionReference {
        db.collection("users").document(userId).collection("todos")
    }
}

struct CardFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
    }
}

struct SectionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundColor(Color(red: 0.62, green: 0.12, blue: 0.14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(red: 1.0, green: 0.95, blue: 0.95))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AuthenticationView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    @State private var mode: AuthMode = .login
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.96, blue: 0.98),
                        Color(red: 0.91, green: 0.93, blue: 0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer(minLength: 24)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("TaskFlow")
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)

                        Text(mode.title)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(mode.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    SectionCard {
                        VStack(spacing: 18) {
                            Picker("Authentication Mode", selection: $mode) {
                                ForEach(AuthMode.allCases) { currentMode in
                                    Text(currentMode.rawValue).tag(currentMode)
                                }
                            }
                            .pickerStyle(.segmented)

                            VStack(spacing: 12) {
                                TextField("Email address", text: $email)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                                    .modifier(CardFieldStyle())

                                SecureField("Password", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .modifier(CardFieldStyle())
                            }

                            if !authViewModel.errorMessage.isEmpty {
                                ErrorBanner(message: authViewModel.errorMessage)
                            }

                            Button {
                                Task {
                                    let success: Bool
                                    switch mode {
                                    case .login:
                                        success = await authViewModel.login(email: email, password: password)
                                    case .register:
                                        success = await authViewModel.register(email: email, password: password)
                                    }

                                    if success {
                                        password = ""
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    if authViewModel.isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    }

                                    Text(mode.actionTitle)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.black)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .disabled(authViewModel.isLoading)

                            Text(mode.footnote)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
    }
}

struct TodoInputView: View {
    @Binding var newTodoTitle: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Add a new task", text: $newTodoTitle)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(
                        newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color(.systemGray4)
                        : Color.black
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

struct TodoRowView: View {
    let todo: TodoItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .stroke(todo.isDone ? Color.black : Color(.systemGray3), lineWidth: 1.5)
                        .frame(width: 24, height: 24)

                    if todo.isDone {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 24, height: 24)

                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .font(.body)
                    .foregroundColor(todo.isDone ? .secondary : .primary)
                    .strikethrough(todo.isDone, color: .secondary)

                if let createdAt = todo.createdAt {
                    Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct EmptyStateView: View {
    var body: some View {
        SectionCard {
            VStack(spacing: 14) {
                Image(systemName: "checklist")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.secondary)

                Text("No tasks yet")
                    .font(.headline)

                Text("Create your first task to start organizing your day.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }
}

struct TodoListView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var viewModel: TodoViewModel
    @State private var newTodoTitle = ""

    init(userId: String) {
        _viewModel = StateObject(wrappedValue: TodoViewModel(userId: userId))
    }

    private var completedCount: Int {
        viewModel.todos.filter { $0.isDone }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("My Tasks")
                                .font(.system(size: 34, weight: .semibold, design: .rounded))

                            Text(authViewModel.user?.email ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        SectionCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Overview")
                                        .font(.headline)
                                    Text("\(viewModel.todos.count) tasks • \(completedCount) completed")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "tray.full")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.black.opacity(0.75))
                            }
                        }

                        if !viewModel.errorMessage.isEmpty {
                            ErrorBanner(message: viewModel.errorMessage)
                        }

                        TodoInputView(newTodoTitle: $newTodoTitle) {
                            viewModel.addTodo(title: newTodoTitle)
                            newTodoTitle = ""
                        }

                        if viewModel.todos.isEmpty {
                            EmptyStateView()
                        } else {
                            VStack(spacing: 12) {
                                ForEach(viewModel.todos) { todo in
                                    TodoRowView(todo: todo, onToggle: {
                                        viewModel.toggleTodoDone(todo)
                                    }, onDelete: {
                                        if let index = viewModel.todos.firstIndex(where: { $0.id == todo.id }) {
                                            viewModel.deleteTodos(at: IndexSet(integer: index))
                                        }
                                    })
                                    .contextMenu {
                                        Button(todo.isDone ? "Mark as Incomplete" : "Mark as Complete") {
                                            viewModel.toggleTodoDone(todo)
                                        }

                                        Button("Delete", role: .destructive) {
                                            if let index = viewModel.todos.firstIndex(where: { $0.id == todo.id }) {
                                                viewModel.deleteTodos(at: IndexSet(integer: index))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out") {
                        authViewModel.signOut()
                    }
                }
            })
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        Group {
            if let user = authViewModel.user {
                TodoListView(userId: user.uid)
            } else {
                AuthenticationView()
            }
        }
    }
}

struct ContentView: View {
    var body: some View {
        RootView()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AuthViewModel())
    }
}
