import SwiftUI
import SwiftData

struct TimelineEvent: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case encounter, memo, gift, status, period, milestone, todo

        var id: String { rawValue }

        var title: String {
            switch self {
            case .encounter: return "约会"
            case .memo: return "备忘"
            case .gift: return "礼物"
            case .status: return "关系"
            case .period: return "经期"
            case .milestone: return "里程碑"
            case .todo: return "待办"
            }
        }

        var symbol: String {
            switch self {
            case .encounter: return "heart.fill"
            case .memo: return "text.quote"
            case .gift: return "gift.fill"
            case .status: return "arrow.triangle.swap"
            case .period: return "drop.fill"
            case .milestone: return "flag.fill"
            case .todo: return "checkmark"
            }
        }

        var color: Color {
            switch self {
            case .encounter: return Palette.encounter
            case .memo: return Palette.memo
            case .gift: return Palette.gift
            case .status: return Palette.status
            case .period: return Palette.period
            case .milestone: return Palette.date
            case .todo: return Palette.todo
            }
        }
    }

    let id: String
    let date: Date
    let kind: Kind
    let title: String
    var subtitle: String = ""
    var encounter: Encounter?
    var memoID: UUID?
}

enum TimelineBuilder {
    static func events(for girl: Girl, todos: [TodoItem]) -> [TimelineEvent] {
        let d = girl.details
        var list: [TimelineEvent] = []

        list.append(TimelineEvent(id: "created", date: girl.createdAt, kind: .milestone, title: "建档"))
        if let met = d.metDate {
            list.append(TimelineEvent(id: "met", date: met, kind: .milestone, title: "认识",
                                      subtitle: [d.channel, d.howWeMet].filter { !$0.isEmpty }.joined(separator: " · ")))
        }
        if let first = d.firstDateDate {
            list.append(TimelineEvent(id: "firstDate", date: first, kind: .milestone, title: "第一次见面"))
        }
        if let firstEncounter = girl.firstEncounterDate {
            list.append(TimelineEvent(id: "firstNight", date: firstEncounter, kind: .milestone, title: "第一次"))
        }
        for (i, change) in d.statusHistory.enumerated() {
            let status = RelationStatus(rawValue: change.status) ?? .flirting
            list.append(TimelineEvent(id: "status-\(change.id)", date: change.date, kind: .status,
                                      title: i == 0 ? "关系：\(status.title)" : "关系变为「\(status.title)」"))
        }
        for e in girl.encounters {
            var parts: [String] = []
            if let place = e.place { parts.append(place.displayName) }
            parts.append("\(e.count) 回合")
            if e.girls.count > 1 { parts.append("多人") }
            if e.rating > 0 { parts.append(String(repeating: "★", count: e.rating)) }
            list.append(TimelineEvent(id: "e-\(e.id)", date: e.date, kind: .encounter, title: "约会",
                                      subtitle: parts.joined(separator: " · "), encounter: e))
        }
        for m in d.memos {
            list.append(TimelineEvent(id: "m-\(m.id)", date: m.date, kind: .memo, title: m.text, memoID: m.id))
        }
        for s in d.saidNotes {
            list.append(TimelineEvent(id: "s-\(s.id)", date: s.date, kind: .memo, title: "她说：\(s.text)"))
        }
        for g in d.gifts {
            list.append(TimelineEvent(id: "g-\(g.id)", date: g.date, kind: .gift,
                                      title: g.item.isEmpty ? (g.occasion.isEmpty ? "礼物" : g.occasion) : g.item,
                                      subtitle: [g.occasion, g.amount > 0 ? Fmt.money(g.amount) : ""].filter { !$0.isEmpty }.joined(separator: " · ")))
        }
        for p in d.periodEntries {
            let subtitle = p.end.map { "持续 \(Fmt.days(from: p.start, to: $0) + 1) 天" } ?? ""
            list.append(TimelineEvent(id: "p-\(p.id)", date: p.start, kind: .period, title: "经期开始", subtitle: subtitle))
        }
        for t in todos where t.girlID == girl.id && t.isDone {
            list.append(TimelineEvent(id: "t-\(t.id)", date: t.doneAt ?? t.createdAt, kind: .todo, title: t.title))
        }
        return list.sorted { $0.date > $1.date }
    }
}

/// 时间线的一行：左边图标 + 竖线，右边内容
struct TimelineRow: View {
    let event: TimelineEvent
    var isFirst = false
    var isLast = false
    var showsLine = true

    private let line = Color.secondary.opacity(0.2)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: event.kind.symbol, color: event.kind.color, size: 28)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.title)
                        .font(.subheadline.weight(event.kind == .memo ? .regular : .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(Fmt.shortDate(event.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if !event.subtitle.isEmpty {
                    Text(event.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
        }
        .background(alignment: .topLeading) {
            if showsLine {
                VStack(spacing: 0) {
                    Rectangle().fill(isFirst ? Color.clear : line).frame(width: 2, height: 6)
                    Color.clear.frame(width: 2, height: 28)
                    Rectangle().fill(isLast ? Color.clear : line).frame(width: 2)
                }
                .frame(width: 28)
            }
        }
    }
}

/// 完整时间线
struct GirlTimelineView: View {
    let girl: Girl

    @Query private var todos: [TodoItem]
    @State private var filter: TimelineEvent.Kind?
    @State private var addingMemo = false

    var body: some View {
        let all = TimelineBuilder.events(for: girl, todos: todos)
        let events = filter.map { f in all.filter { $0.kind == f } } ?? all
        let kinds = TimelineEvent.Kind.allCases.filter { k in all.contains { $0.kind == k } }
        let groups = Dictionary(grouping: events) { e in
            Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: e.date)) ?? e.date
        }
        let months = groups.keys.sorted(by: >)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("全部", count: all.count, selected: filter == nil) { filter = nil }
                        ForEach(kinds) { k in
                            chip(k.title, count: all.filter { $0.kind == k }.count, selected: filter == k, color: k.color) {
                                filter = (filter == k) ? nil : k
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)

                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(months, id: \.self) { month in
                        let items = groups[month] ?? []
                        Section {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, event in
                                row(event, isFirst: index == 0, isLast: index == items.count - 1)
                                    .padding(.horizontal)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        } header: {
                            Text(Fmt.month(month))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.bar)
                        }
                    }
                }
                .animation(.snappy, value: filter)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay {
            if events.isEmpty {
                ContentUnavailableView("没有内容", systemImage: "clock")
            }
        }
        .navigationTitle("时间线")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                addingMemo = true
            } label: {
                Image(systemName: "square.and.pencil")
            }
        }
        .sheet(isPresented: $addingMemo) {
            NoteSheet(title: "加一条备忘") { note in
                withAnimation(.snappy) {
                    girl.update { $0.memos.append(note); $0.memos.sort { $0.date > $1.date } }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ event: TimelineEvent, isFirst: Bool, isLast: Bool) -> some View {
        if let e = event.encounter {
            NavigationLink {
                EncounterDetailView(encounter: e)
            } label: {
                TimelineRow(event: event, isFirst: isFirst, isLast: isLast)
            }
            .buttonStyle(.plain)
        } else if let memoID = event.memoID {
            TimelineRow(event: event, isFirst: isFirst, isLast: isLast)
                .contextMenu {
                    Button(role: .destructive) {
                        withAnimation(.snappy) {
                            girl.update { d in d.memos.removeAll { $0.id == memoID } }
                        }
                    } label: {
                        Label("删除备忘", systemImage: "trash")
                    }
                }
        } else {
            TimelineRow(event: event, isFirst: isFirst, isLast: isLast)
        }
    }

    private func chip(_ title: String, count: Int, selected: Bool, color: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)").foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? color : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }
}
