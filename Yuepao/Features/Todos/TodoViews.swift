import SwiftUI
import SwiftData

// MARK: - 行

struct TodoRow: View {
    let todo: TodoItem
    var girlName: String?
    var showDate = true
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isDone ? Color.accentColor : (todo.isOverdue ? Palette.period : Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.success, trigger: todo.isDone) { _, done in done }

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .strikethrough(todo.isDone, color: .secondary)
                    .foregroundStyle(todo.isDone ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                    .animation(.default, value: todo.isDone)
                if !meta.isEmpty || girlName != nil {
                    HStack(spacing: 6) {
                        if let girlName {
                            Label(girlName, systemImage: "person.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        if !meta.isEmpty {
                            Text(meta)
                                .foregroundStyle(todo.isOverdue ? Palette.period : Color.secondary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if !todo.notes.isEmpty {
                    Text(todo.notes)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if todo.remind && todo.dueDate != nil && !todo.isDone {
                Image(systemName: "bell.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var meta: String {
        var parts: [String] = []
        if showDate, let due = todo.dueDate, todo.isDone {
            parts.append(Fmt.shortDate(due))
        } else if showDate, let due = todo.dueDate {
            parts.append(TodoFormat.due(due, hasTime: todo.hasTime))
        } else if let due = todo.dueDate, todo.hasTime {
            parts.append(due.formatted(.dateTime.hour().minute()))
        }
        if !todo.category.isEmpty { parts.append(todo.category) }
        return parts.joined(separator: " · ")
    }
}

enum TodoFormat {
    static func due(_ date: Date, hasTime: Bool) -> String {
        let cal = Calendar.current
        let time = hasTime ? " " + date.formatted(.dateTime.hour().minute()) : ""
        if cal.isDateInToday(date) { return "今天" + time }
        if cal.isDateInTomorrow(date) { return "明天" + time }
        if cal.isDateInYesterday(date) { return "昨天" + time }
        let n = Fmt.days(from: Date(), to: date)
        if n > 0 && n < 7 { return "\(n) 天后" + time }
        if n < 0 { return "逾期 \(-n) 天" }
        return Fmt.shortDate(date) + time
    }
}

@MainActor
enum TodoActions {
    static func toggle(_ todo: TodoItem, girls: [Girl], context: ModelContext) {
        withAnimation(.snappy) {
            todo.isDone.toggle()
            todo.doneAt = todo.isDone ? Date() : nil
        }
        try? context.save()
        if todo.isDone {
            Reminders.cancelTodo(id: todo.id)
        } else {
            Reminders.scheduleTodo(todo, girlName: girls.first { $0.id == todo.girlID }?.name)
        }
    }

    static func postpone(_ todo: TodoItem, days: Int, girls: [Girl], context: ModelContext) {
        let base = max(todo.dueDate ?? Date(), Calendar.current.startOfDay(for: Date()))
        withAnimation(.snappy) {
            todo.dueDate = Calendar.current.date(byAdding: .day, value: days, to: base)
        }
        try? context.save()
        Reminders.scheduleTodo(todo, girlName: girls.first { $0.id == todo.girlID }?.name)
    }

    static func delete(_ todo: TodoItem, context: ModelContext) {
        Reminders.cancelTodo(id: todo.id)
        withAnimation(.snappy) {
            context.delete(todo)
        }
        try? context.save()
    }
}

// MARK: - 待办清单

struct TodoListSections: View {
    let todos: [TodoItem]
    let girls: [Girl]
    var showCompleted = true
    let onEdit: (TodoItem) -> Void

    @Environment(\.modelContext) private var context
    @State private var showAllDone = false

    private var open: [TodoItem] { todos.filter { !$0.isDone } }

    private var overdue: [TodoItem] { sortByDue(open.filter { $0.isOverdue }) }
    private var today: [TodoItem] { sortByDue(open.filter { !$0.isOverdue && $0.isDueToday }) }
    private var upcoming: [TodoItem] { sortByDue(open.filter { !$0.isOverdue && !$0.isDueToday && $0.dueDate != nil }) }
    private var someday: [TodoItem] { open.filter { $0.dueDate == nil }.sorted { $0.createdAt > $1.createdAt } }
    private var done: [TodoItem] {
        todos.filter(\.isDone).sorted { ($0.doneAt ?? $0.createdAt) > ($1.doneAt ?? $1.createdAt) }
    }

    private func sortByDue(_ list: [TodoItem]) -> [TodoItem] {
        list.sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
    }

    var body: some View {
        group("逾期", overdue, tint: Palette.period)
        group("今天", today)
        group("之后", upcoming)
        group("随时", someday)
        if showCompleted && !done.isEmpty {
            Section {
                ForEach(showAllDone ? done : Array(done.prefix(5))) { todo in
                    row(todo)
                }
                if done.count > 5 {
                    Button(showAllDone ? "收起" : "显示全部 \(done.count) 条") {
                        withAnimation(.snappy) { showAllDone.toggle() }
                    }
                    .font(.footnote)
                }
            } header: {
                Text("已完成")
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [TodoItem], tint: Color? = nil) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { todo in
                    row(todo)
                }
            } header: {
                HStack {
                    Text(title).foregroundStyle(tint ?? Color.secondary)
                    Spacer()
                    Text("\(items.count)").statNumber()
                }
            }
        }
    }

    private func row(_ todo: TodoItem) -> some View {
        TodoRow(todo: todo, girlName: girls.first { $0.id == todo.girlID }?.name) {
            TodoActions.toggle(todo, girls: girls, context: context)
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit(todo) }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                TodoActions.delete(todo, context: context)
            } label: {
                Label("删除", systemImage: "trash")
            }
            if !todo.isDone {
                Button {
                    TodoActions.postpone(todo, days: 1, girls: girls, context: context)
                } label: {
                    Label("推迟", systemImage: "arrow.uturn.forward")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                TodoActions.toggle(todo, girls: girls, context: context)
            } label: {
                Label(todo.isDone ? "未完成" : "完成", systemImage: todo.isDone ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(.accentColor)
        }
    }
}

// MARK: - 编辑

struct TodoEditView: View {
    let todo: TodoItem?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Girl.createdAt, order: .reverse) private var girls: [Girl]
    @ObservedObject private var config = ConfigStore.shared

    @State private var title: String
    @State private var notes: String
    @State private var girlID: UUID?
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var hasTime: Bool
    @State private var remind: Bool
    @State private var category: String
    @FocusState private var titleFocused: Bool

    private let suggestions = ["约她吃饭", "订酒店", "买礼物", "准备生日惊喜", "回她消息", "去做检测", "买安全套"]

    init(todo: TodoItem?, presetGirl: Girl? = nil, presetDate: Date? = nil) {
        self.todo = todo
        _title = State(initialValue: todo?.title ?? "")
        _notes = State(initialValue: todo?.notes ?? "")
        _girlID = State(initialValue: todo?.girlID ?? presetGirl?.id)
        let due = todo?.dueDate ?? presetDate
        _hasDate = State(initialValue: due != nil)
        let defaultDate = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
        _date = State(initialValue: due ?? defaultDate)
        _hasTime = State(initialValue: todo?.hasTime ?? false)
        _remind = State(initialValue: todo?.remind ?? true)
        _category = State(initialValue: todo?.category ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("要做什么", text: $title, axis: .vertical)
                        .font(.body.weight(.medium))
                        .focused($titleFocused)
                        .accessibilityIdentifier("todoTitle")
                    if title.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.self) { s in
                                    Button(s) { title = s }
                                        .font(.footnote)
                                        .buttonStyle(.bordered)
                                        .buttonBorderShape(.capsule)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    TextField("备注", text: $notes, axis: .vertical)
                        .lineLimit(1...5)
                }

                Section {
                    Picker("关联档案", selection: $girlID) {
                        Text("无").tag(UUID?.none)
                        ForEach(girls) { g in
                            Text(g.name).tag(UUID?.some(g.id))
                        }
                    }
                    OptionSinglePicker(title: "分类", key: .todoCategories, selection: $category)
                }

                Section {
                    Toggle(isOn: $hasDate.animation(.snappy)) {
                        Label("日期", systemImage: "calendar")
                    }
                    if hasDate {
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                        Toggle(isOn: $hasTime.animation(.snappy)) {
                            Label("具体时间", systemImage: "clock")
                        }
                        if hasTime {
                            DatePicker("时间", selection: $date, displayedComponents: .hourAndMinute)
                        }
                        Toggle(isOn: $remind) {
                            Label("提醒我", systemImage: "bell")
                        }
                    }
                } footer: {
                    if hasDate && remind && !Reminders.enabled {
                        Text("提醒需要先在「设置 → 提醒」里开启通知。")
                    } else if hasDate && remind && !hasTime {
                        Text("没有具体时间时，当天早上 9 点提醒。")
                    }
                }
            }
            .navigationTitle(todo == nil ? "新待办" : "编辑待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(title.trimmed.isEmpty)
                        .accessibilityIdentifier("saveTodo")
                }
            }
            .onAppear {
                if todo == nil { titleFocused = true }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let target: TodoItem
        if let todo {
            target = todo
        } else {
            target = TodoItem()
            context.insert(target)
        }
        target.title = title.trimmed
        target.notes = notes.trimmed
        target.girlID = girlID
        target.category = category
        target.dueDate = hasDate ? (hasTime ? date : Calendar.current.startOfDay(for: date)) : nil
        target.hasTime = hasDate && hasTime
        target.remind = hasDate && remind
        try? context.save()
        Reminders.scheduleTodo(target, girlName: girls.first { $0.id == girlID }?.name)
        dismiss()
    }
}
