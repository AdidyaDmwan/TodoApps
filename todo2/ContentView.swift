import SwiftUI
import FirebaseFirestore

struct TodoItem: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var isDone: Bool

    init(title: String, isDone: Bool = false) {
        self.title = title
        self.isDone = isDone
    }
}

final class TodoViewModel: ObservableObject {
    @Published var todos = [TodoItem]()

    private let db = Firestore.firestore()
    private let collectionName = "todos"
    private var listener: ListenerRegistration?

    init() {
        startListening()
    }

    deinit {
        listener?.remove()
    }

    // MARK: - Real-time listener
    func startListening() {
        listener = db.collection(collectionName)
            .order(by: "createdAt")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else {
                    print("Error fetching todos: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                self.todos = snapshot.documents.compactMap {
                    try? $0.data(as: TodoItem.self)
                }
            }
    }

    // MARK: - CRUD
    func addTodo(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let data: [String: Any] = [
            "title": trimmed,
            "isDone": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        db.collection(collectionName).addDocument(data: data) { error in
            if let error { print("Error adding todo: \(error)") }
        }
    }

    func toggleTodoDone(_ todo: TodoItem) {
        guard let id = todo.id else { return }
        db.collection(collectionName).document(id).updateData([
            "isDone": !todo.isDone
        ]) { error in
            if let error { print("Error toggling todo: \(error)") }
        }
    }

    func deleteTodos(at offsets: IndexSet) {
        offsets.forEach { index in
            guard let id = todos[index].id else { return }
            db.collection(collectionName).document(id).delete { error in
                if let error { print("Error deleting todo: \(error)") }
            }
        }
    }
}

// MARK: - Views (sama seperti sebelumnya)

struct TodoInputView: View {
    @Binding var newTodoTitle: String
    let onAdd: () -> Void

    var body: some View {
        HStack {
            TextField("Add a new todo...", text: $newTodoTitle)
                .padding(12)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                .autocapitalization(.sentences)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.gray.opacity(0.3) : Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
            .disabled(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
    }
}

struct ContentView: View {
    @StateObject private var viewModel = TodoViewModel()
    @State private var newTodoTitle = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGray6).ignoresSafeArea()

                VStack(spacing: 12) {
                    Text("Todo List")
                        .font(.largeTitle).fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    TodoInputView(newTodoTitle: $newTodoTitle) {
                        viewModel.addTodo(title: newTodoTitle)
                        newTodoTitle = ""
                    }

                    if viewModel.todos.isEmpty {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "list.bullet.rectangle.portrait")
                                .font(.largeTitle).foregroundColor(.secondary)
                            Text("No todos yet").font(.title3).fontWeight(.semibold)
                            Text("Add a new item above to start your productivity flow")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(viewModel.todos) { todo in
                                HStack(spacing: 12) {
                                    Button(action: { viewModel.toggleTodoDone(todo) }) {
                                        Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(todo.isDone ? .green : .gray)
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)

                                    Text(todo.title)
                                        .strikethrough(todo.isDone, color: .gray)
                                        .foregroundColor(todo.isDone ? .secondary : .primary)

                                    Spacer()

                                    if todo.isDone {
                                        Text("Done")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.green)
                                            .cornerRadius(8)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.systemBackground))
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                            .onDelete(perform: viewModel.deleteTodos)
                        }
                        .listStyle(PlainListStyle())
                        .scrollContentBackground(.hidden)
                    }

                    Spacer(minLength: 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
            }
        }
    }
}
