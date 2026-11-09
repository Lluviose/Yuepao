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
                .tint(Palette.gold)
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
    @State private var showCalendar = false
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

    private var currentGirls: [Girl] {
        let list = girls.filter { $0.status.isCurrent }
            .sorted { ($0.lastInteraction() ?? $0.createdAt) > ($1.lastInteraction() ?? $1.createdAt) }
        if let id = girlID, let g = girls.first(where: { $0.id == id }), !list.contains(where: { $0.id == id }) {
            return [g] + list
        }
        return list
    }

    var body: some View {
        ComposerShell(title: todo == nil ? "新待办" : "编辑待办", canSave: !title.trimmed.isEmpty,
                      saveIdentifier: "saveTodo",
                      onCancel: { dismiss() }, onSave: save) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("要做什么", text: $title, axis: .vertical)
                    .font(Typo.display(24, weight: .medium))
                    .focused($titleFocused)
                    .accessibilityIdentifier("todoTitle")
                if title.isEmpty {
                    ChipRow {
                        ForEach(suggestions, id: \.self) { s in
                            ChoiceChip(title: s, selected: false) { title = s }
                        }
                    }
                    .transition(.opacity)
                }
                TextField("备注", text: $notes, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1...4)
            }

            dateSection

            if !currentGirls.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ComposerLabel("关于谁")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(currentGirls) { g in
                                QuickPickAvatar(girl: g, selected: girlID == g.id) {
                                    withAnimation(.snappy(duration: 0.22)) {
                                        girlID = girlID == g.id ? nil : g.id
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, -20)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ComposerLabel("分类")
                ChipRow {
                    ForEach(config.options(.todoCategories), id: \.self) { c in
                        ChoiceChip(title: c, selected: category == c) {
                            category = category == c ? "" : c
                        }
                    }
                }
            }
        }
        .composerSheet(detents: [.large])
        .onAppear {
            if todo == nil { titleFocused = true }
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComposerLabel("时间")
            ChipRow {
                ChoiceChip(title: "不设", selected: !hasDate) {
                    hasDate = false
                    showCalendar = false
                }
                ForEach(QuickDay.allCases) { d in
                    ChoiceChip(title: d.title, selected: hasDate && d.matches(date) && !showCalendar) {
                        hasDate = true
                        showCalendar = false
                        date = merge(day: d.date, timeFrom: date)
                    }
                }
                ChoiceChip(title: "选日期", symbol: "calendar", selected: hasDate && showCalendar) {
                    hasDate = true
                    showCalendar = true
                }
            }
            if hasDate {
                VStack(spacing: 0) {
                    if showCalendar {
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .padding(.bottom, 4)
                    } else {
                        HStack {
                            Image(systemName: "calendar").foregroundStyle(.secondary)
                            Text(TodoFormat.due(date, hasTime: false) + " · " + Fmt.shortDate(date))
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }
                    Divider()
                    Toggle(isOn: $hasTime.animation(.snappy)) {
                        Label("具体时间", systemImage: "clock")
                    }
                    .padding(.vertical, 8)
                    if hasTime {
                        DatePicker("时间", selection: $date, displayedComponents: .hourAndMinute)
                            .padding(.bottom, 8)
                    }
                    Divider()
                    Toggle(isOn: $remind) {
                        Label(remind && !hasTime ? "提醒我（当天 9:00）" : "提醒我", systemImage: "bell")
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .tertiarySystemFill)))
                .transition(.opacity.combined(with: .move(edge: .top)))

                if remind && !Reminders.enabled {
                    Text("提醒需要先在「设置 → 提醒」里开启通知。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func merge(day: Date, timeFrom: Date) -> Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: timeFrom)
        return cal.date(bySettingHour: t.hour ?? 20, minute: t.minute ?? 0, second: 0, of: day) ?? day
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
