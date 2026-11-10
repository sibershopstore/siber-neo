import Foundation

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var due: Date?
    var done = false
    var notified = false
}

/// To-do list with reminders. Data is stored locally in todos.json.
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []

    var onDue: ((TodoItem) -> Void)?

    private var timer: Timer?
    private let fileName = "todos.json"

    init() {
        items = Storage.load([TodoItem].self, from: fileName) ?? []
        fireDue()
    }

    var sorted: [TodoItem] {
        items.sorted { a, b in
            if a.done != b.done { return !a.done }
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return false
            }
        }
    }

    var openCount: Int { items.filter { !$0.done }.count }

    func add(title: String, due: Date?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(TodoItem(title: trimmed, due: due))
        persist()
    }

    func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].done.toggle()
        persist()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func clearCompleted() {
        items.removeAll { $0.done }
        persist()
    }

    private func persist() {
        Storage.save(items, to: fileName)
        scheduleNext()
    }

    private func scheduleNext() {
        timer?.invalidate()
        timer = nil
        let now = Date()
        let upcoming = items
            .filter { !$0.done && !$0.notified }
            .compactMap { $0.due }
            .filter { $0 > now }
            .min()
        guard let next = upcoming else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            self?.fireDue()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fireDue() {
        let now = Date()
        var due: [TodoItem] = []
        for index in items.indices where !items[index].done && !items[index].notified {
            guard let date = items[index].due, date <= now.addingTimeInterval(1) else { continue }
            items[index].notified = true
            if now.timeIntervalSince(date) < 600 {
                due.append(items[index])
            }
        }
        persist()
        due.forEach { onDue?($0) }
    }
}
