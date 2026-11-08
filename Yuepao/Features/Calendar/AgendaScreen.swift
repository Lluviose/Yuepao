import SwiftUI
import SwiftData

// MARK: - 数据

struct AgendaEvent: Identifiable {
    enum Kind {
        case cycle(Girl, String, CycleDayKind)
        case date(Girl, String)
        case encounter(Encounter)
        case todo(TodoItem)
    }

    let id: String
    let kind: Kind
}

/// 把档案、记录、待办整理成按天查询的结构
struct AgendaModel {
    let girls: [Girl]
    private let encountersByDay: [Date: [Encounter]]
    private let todosByDay: [Date: [TodoItem]]
    private let cycles: [(girl: Girl, info: CycleInfo)]
    private let yearly: [(girl: Girl, title: String, month: Int, day: Int, year: Int?)]
    let focusGirl: Girl?

    private static let cal = Calendar.current

    init(girls allGirls: [Girl], encounters: [Encounter], todos: [TodoItem], girlFilter: UUID?) {
        let cal = Self.cal
        let girls = girlFilter.map { id in allGirls.filter { $0.id == id } } ?? allGirls.filter { $0.status != .blocked }
        self.girls = girls
        focusGirl = girlFilter.flatMap { id in allGirls.first { $0.id == id } }

        let visibleEncounters = girlFilter.map { id in encounters.filter { e in e.girls.contains { $0.id == id } } } ?? encounters
        encountersByDay = Dictionary(grouping: visibleEncounters) { cal.startOfDay(for: $0.date) }

        let visibleTodos = todos.filter { $0.dueDate != nil && (girlFilter == nil || $0.girlID == girlFilter) }
        todosByDay = Dictionary(grouping: visibleTodos) { cal.startOfDay(for: $0.dueDate ?? Date()) }

        var cycles: [(girl: Girl, info: CycleInfo)] = []
        var yearly: [(girl: Girl, title: String, month: Int, day: Int, year: Int?)] = []
        for g in girls {
            let d = g.details
            let info = d.cycle
            if info.hasData && (g.status.isCurrent || girlFilter != nil) {
                cycles.append((g, info))
            }
            if let bd = d.birthday {
                let c = cal.dateComponents([.year, .month, .day], from: bd)
                yearly.append((g, "生日", c.month ?? 1, c.day ?? 1, c.year))
            }
            for item in d.importantDates {
                let c = cal.dateComponents([.month, .day], from: item.date)
                yearly.append((g, item.title, c.month ?? 1, c.day ?? 1, nil))
            }
        }
        self.cycles = cycles
        self.yearly = yearly
    }

    private func yearlyEvents(on day: Date) -> [(girl: Girl, title: String, year: Int?)] {
        let c = Self.cal.dateComponents([.month, .day], from: day)
        return yearly.filter { $0.month == c.month && $0.day == c.day }.map { ($0.girl, $0.title, $0.year) }
    }

    func decoration(_ day: Date) -> DayDecoration {
        let key = Self.cal.startOfDay(for: day)
        var dec = DayDecoration()
        if encountersByDay[key] != nil { dec.dots.append(Palette.encounter) }
        if let todos = todosByDay[key], todos.contains(where: { !$0.isDone }) { dec.dots.append(Palette.todo) }
        if !yearlyEvents(on: key).isEmpty { dec.dots.append(Palette.date) }

        if focusGirl != nil, let info = cycles.first?.info {
            switch info.kind(on: key) {
            case .period(let predicted): dec.band = predicted ? .predictedPeriod : .period
            case .fertile: dec.band = .fertile
            case .ovulation:
                dec.band = .fertile
                dec.ovulation = true
            case .none: break
            }
        } else if cycles.contains(where: { $0.info.kind(on: key).isPeriod }) {
            dec.dots.append(Palette.period)
        }
        return dec
    }

    func events(_ day: Date) -> [AgendaEvent] {
        let key = Self.cal.startOfDay(for: day)
        var result: [AgendaEvent] = []

        for c in cycles {
            let kind = c.info.kind(on: key)
            let n = c.info.dayOfCycle(on: key) ?? 0
            let text: String
            switch kind {
            case .period(let predicted):
                text = predicted ? (n == 1 ? "预计来例假" : "预计经期第 \(n) 天") : "经期第 \(n) 天"
            case .ovulation:
                text = "排卵日（预测）"
            case .fertile:
                text = "易孕期"
            case .none:
                continue
            }
            result.append(AgendaEvent(id: "c-\(c.girl.id)", kind: .cycle(c.girl, text, kind)))
        }

        for y in yearlyEvents(on: key) {
            var title = y.title
            if y.title == "生日", let year = y.year {
                let age = Self.cal.component(.year, from: key) - year
                if age > 0 { title = "\(age) 岁生日" }
            }
            result.append(AgendaEvent(id: "y-\(y.girl.id)-\(y.title)", kind: .date(y.girl, title)))
        }

        for e in (encountersByDay[key] ?? []).sorted(by: { $0.date < $1.date }) {
            result.append(AgendaEvent(id: "e-\(e.id)", kind: .encounter(e)))
        }

        let todos = (todosByDay[key] ?? []).sorted {
            if $0.isDone != $1.isDone { return !$0.isDone }
            return ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture)
        }
        for t in todos {
            result.append(AgendaEvent(id: "t-\(t.id)", kind: .todo(t)))
        }
        return result
    }
}

// MARK: - 日程页

struct AgendaScreen: View {
    @Query(sort: \Girl.createdAt) private var girls: [Girl]
    @Query(sort: \Encounter.date, order: .reverse) private var encounters: [Encounter]
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var todos: [TodoItem]
    @Environment(\.modelContext) private var context

    enum Mode: String, CaseIterable, Identifiable {
        case calendar, todos
        var id: String { rawValue }
        var title: String { self == .calendar ? "日历" : "待办" }
    }

    @State private var mode: Mode = .calendar
    @State private var month = MonthCalendarView.calendar.date(
        from: MonthCalendarView.calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var selection = Calendar.current.startOfDay(for: Date())
    @State private var girlFilter: UUID?
    @State private var creatingEncounter = false
    @State private var creatingTodo = false
    @State private var editingTodo: TodoItem?

    private var openTodoCount: Int { todos.filter { !$0.isDone }.count }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .calendar: calendarList
                case .todos: todoList
                }
            }
            .animation(.snappy, value: mode)
            .navigationTitle("日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("模式", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m == .todos && openTodoCount > 0 ? "待办 \(openTodoCount)" : m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if mode == .calendar { filterMenu }
                }
                ToolbarItem(placement: .primaryAction) {
                    addMenu
                }
            }
            .sheet(isPresented: $creatingEncounter) {
                EncounterEditView(encounter: nil, presetGirls: focusGirls, presetDate: selection)
            }
            .sheet(isPresented: $creatingTodo) {
                TodoEditView(todo: nil, presetGirl: girls.first { $0.id == girlFilter },
                             presetDate: mode == .calendar ? selection : nil)
            }
            .sheet(item: $editingTodo) { todo in
                TodoEditView(todo: todo)
            }
        }
    }

    private var focusGirls: [Girl] {
        girls.filter { $0.id == girlFilter }
    }

    private var addMenu: some View {
        Menu {
            Button {
                creatingTodo = true
            } label: {
                Label("加待办", systemImage: "checklist")
            }
            Button {
                creatingEncounter = true
            } label: {
                Label(mode == .calendar ? "在 \(Fmt.shortDate(selection)) 记一次" : "记一次", systemImage: "heart.text.square")
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityIdentifier("agendaAdd")
    }

    private var filterMenu: some View {
        Menu {
            Picker("看谁的", selection: $girlFilter.animation(.snappy)) {
                Text("所有人").tag(UUID?.none)
                ForEach(girls.filter { $0.status.isCurrent }) { g in
                    Text(g.name).tag(UUID?.some(g.id))
                }
            }
        } label: {
            Image(systemName: girlFilter == nil ? "person.2" : "person.fill")
        }
    }

    // MARK: 日历模式

    private var calendarList: some View {
        let model = AgendaModel(girls: girls, encounters: encounters, todos: todos, girlFilter: girlFilter)
        let events = model.events(selection)
        return List {
            Section {
                MonthCalendarView(month: $month, selection: $selection) { model.decoration($0) }
                    .padding(.vertical, 6)
                legend(model)
            }

            Section {
                if events.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                            Text("这天没有安排")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 14)
                        Spacer()
                    }
                } else {
                    ForEach(events) { event in
                        eventRow(event)
                    }
                }
                HStack(spacing: 10) {
                    addButton("记一次", "heart.fill") { creatingEncounter = true }
                    addButton("加待办", "checklist") { creatingTodo = true }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            } header: {
                HStack {
                    Text(dayTitle(selection))
                        .contentTransition(.numericText())
                    Spacer()
                    if let focus = model.focusGirl, let phase = focus.details.cycle.phase(on: selection) {
                        Text("\(focus.name) · \(phase.title)")
                            .foregroundStyle(phase.color)
                    }
                }
                .animation(.snappy, value: selection)
            }
        }
        .listSectionSpacing(.compact)
    }

    @ViewBuilder
    private func legend(_ model: AgendaModel) -> some View {
        HStack(spacing: 14) {
            legendItem(Palette.encounter, "约会")
            legendItem(Palette.todo, "待办")
            legendItem(Palette.date, "纪念日")
            if model.focusGirl == nil {
                legendItem(Palette.period, "经期")
            } else {
                legendBand(Palette.period.opacity(0.25), "经期")
                legendBand(Palette.fertile.opacity(0.3), "易孕期")
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
    }

    private func legendBand(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 8)
            Text(text)
        }
    }

    private func addButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.borderless)
    }

    private func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        var text = Fmt.shortDate(date) + " " + date.formatted(Date.FormatStyle().weekday(.wide).locale(Fmt.locale))
        if cal.isDateInToday(date) { text += " · 今天" } else if cal.isDateInTomorrow(date) { text += " · 明天" }
        return text
    }

    @ViewBuilder
    private func eventRow(_ event: AgendaEvent) -> some View {
        switch event.kind {
        case .cycle(let girl, let text, let kind):
            NavigationLink {
                GirlCycleView(girl: girl)
            } label: {
                HStack(spacing: 12) {
                    IconBadge(symbol: kind.isPeriod ? "drop.fill" : "sparkle", color: kind.isPeriod ? Palette.period : Palette.fertile)
                    Text(girl.name).fontWeight(.medium)
                    Text(text).foregroundStyle(.secondary)
                }
            }
        case .date(let girl, let title):
            NavigationLink {
                GirlDetailView(girl: girl)
            } label: {
                HStack(spacing: 12) {
                    IconBadge(symbol: title.contains("生日") ? "gift.fill" : "star.fill", color: Palette.date)
                    Text(girl.name).fontWeight(.medium)
                    Text(title).foregroundStyle(.secondary)
                }
            }
        case .encounter(let e):
            NavigationLink {
                EncounterDetailView(encounter: e)
            } label: {
                HStack(spacing: 12) {
                    IconBadge(symbol: "heart.fill", color: Palette.encounter)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.girlNames).fontWeight(.medium)
                        Text([e.date.formatted(.dateTime.hour().minute()), e.place?.displayName].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("×\(e.count)").font(.subheadline.weight(.semibold)).statNumber()
                }
            }
        case .todo(let todo):
            TodoRow(todo: todo, girlName: girls.first { $0.id == todo.girlID }?.name, showDate: false) {
                TodoActions.toggle(todo, girls: girls, context: context)
            }
            .contentShape(Rectangle())
            .onTapGesture { editingTodo = todo }
        }
    }

    // MARK: 待办模式

    private var todoList: some View {
        List {
            TodoListSections(todos: todos, girls: girls) { editingTodo = $0 }
        }
        .overlay {
            if todos.isEmpty {
                ContentUnavailableView {
                    Label("没有待办", systemImage: "checklist")
                } description: {
                    Text("约会安排、礼物、回消息…记下来到点提醒你")
                } actions: {
                    Button("加一条") { creatingTodo = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
