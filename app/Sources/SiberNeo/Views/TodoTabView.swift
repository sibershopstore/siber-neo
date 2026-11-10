import SwiftUI

struct TodoTabView: View {
    @EnvironmentObject var todos: TodoStore
    @EnvironmentObject var state: NotchState

    @StateObject var draft = TodoDraft()
    @FocusState var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(tr("Tambah tugas", "Add a task"), text: $draft.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($fieldFocused)
                    .onSubmit(addTask)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.stroke))

                IconButton(
                    systemName: draft.useReminder ? "bell.fill" : "bell",
                    size: 12,
                    tint: draft.useReminder ? Theme.red : Theme.secondary
                ) {
                    draft.useReminder.toggle()
                }
                .help(tr("Pengingat", "Reminder"))

                if draft.useReminder {
                    DatePicker("", selection: $draft.reminderTime, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .frame(width: 72)
                }

                Button(tr("Tambah", "Add"), action: addTask)
                    .buttonStyle(PillButtonStyle(primary: true))
            }

            if todos.items.isEmpty {
                EmptyStateView(icon: "checklist", title: tr("Belum ada tugas", "No tasks yet"), subtitle: tr("Catat tugas dan atur pengingat waktunya.", "Jot down tasks and set reminder times."))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(todos.sorted) { item in
                            TodoRow(item: item)
                        }
                    }
                }
                HStack {
                    Text(tr("\(todos.openCount) tugas aktif", "\(todos.openCount) open tasks"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                    Spacer()
                    if todos.items.contains(where: { $0.done }) {
                        Button(tr("Bersihkan yang selesai", "Clear completed")) { todos.clearCompleted() }
                            .buttonStyle(ChipStyle())
                    }
                }
            }
        }
        .onChange(of: fieldFocused) { _, focused in
            state.keepOpen = focused
        }
    }

    private func addTask() {
        let due = draft.useReminder ? Self.nextOccurrence(of: draft.reminderTime) : nil
        todos.add(title: draft.text, due: due)
        draft.text = ""
        draft.useReminder = false
    }

    /// Returns the selected hour and minute for today, or tomorrow if that time has already passed.
    static func nextOccurrence(of time: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let today = calendar.date(
            bySettingHour: parts.hour ?? 0,
            minute: parts.minute ?? 0,
            second: 0,
            of: Date()
        ) ?? time
        return today > Date() ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}

struct TodoRow: View {
    @EnvironmentObject var todos: TodoStore
    let item: TodoItem

    @StateObject var flags = ViewFlags()

    var body: some View {
        HStack(spacing: 10) {
            Button {
                todos.toggle(item.id)
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.done ? Theme.red : Theme.secondary)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 13))
                .strikethrough(item.done, color: Theme.tertiary)
                .foregroundStyle(item.done ? Theme.tertiary : Color.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let due = item.due {
                HStack(spacing: 4) {
                    Image(systemName: "bell")
                    Text(Self.dueLabel(due))
                }
                .font(.system(size: 11))
                .foregroundStyle(due < Date() && !item.done ? Theme.red : Theme.tertiary)
            }

            Button {
                todos.remove(item.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(flags.hovering ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(flags.hovering ? Color.white.opacity(0.05) : Color.clear)
        )
        .onHover { flags.hovering = $0 }
    }

    static func dueLabel(_ date: Date) -> String {
        let clock = Fmt.clock(date)
        if Calendar.current.isDateInToday(date) { return clock }
        if Calendar.current.isDateInTomorrow(date) { return tr("Besok \(clock)", "Tomorrow \(clock)") }
        return clock
    }
}
