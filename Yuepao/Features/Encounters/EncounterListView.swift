import SwiftUI
import SwiftData

struct EncounterListView: View {
    @Query(sort: \Encounter.date, order: .reverse, animation: .snappy) private var encounters: [Encounter]
    @Environment(\.modelContext) private var context

    @State private var creating = false
    @State private var search = ""
    @State private var pendingDelete: Encounter?
    @State private var repeatFrom: Encounter?
    @State private var editingRecord: Encounter?
    /// 只看某个人的记录
    @State private var girlFilter: UUID?

    /// 有记录的人，按次数从多到少
    private var people: [(girl: Girl, count: Int)] {
        var counts: [UUID: (girl: Girl, count: Int)] = [:]
        for e in encounters {
            for g in e.girls {
                counts[g.id, default: (girl: g, count: 0)].count += 1
            }
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.girl.name < $1.girl.name }
    }

    private var filtered: [Encounter] {
        var list = encounters
        // 筛选的人已经没有记录了（比如刚删掉），就当没筛选，免得卡在空列表
        if let girlFilter, encounters.contains(where: { e in e.girls.contains { $0.id == girlFilter } }) {
            list = list.filter { e in e.girls.contains { $0.id == girlFilter } }
        }
        let q = search.trimmed
        guard !q.isEmpty else { return list }
        return list.filter { e in
            e.girls.contains { $0.name.contains(q) }
                || (e.place?.name.contains(q) ?? false)
                || (e.place?.city.contains(q) ?? false)
                || e.details.notes.contains(q)
                || e.details.highlights.contains { $0.contains(q) }
        }
    }

    private var groups: [(month: Date, items: [Encounter])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filtered) { e in
            cal.date(from: cal.dateComponents([.year, .month], from: e.date)) ?? e.date
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                let list = people
                if list.count >= 2 {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                PersonFilterChip(girl: nil, count: encounters.count, selected: girlFilter == nil,
                                                 dimmed: false) {
                                    withAnimation(.snappy) { girlFilter = nil }
                                }
                                ForEach(list, id: \.girl.id) { item in
                                    let on = girlFilter == item.girl.id
                                    PersonFilterChip(girl: item.girl, count: item.count, selected: on,
                                                     dimmed: girlFilter != nil && !on) {
                                        withAnimation(.snappy) { girlFilter = on ? nil : item.girl.id }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .sensoryFeedback(.selection, trigger: girlFilter)
                    }
                }
                ForEach(groups, id: \.month) { group in
                    Section {
                        ForEach(group.items) { e in
                            NavigationLink {
                                EncounterDetailView(encounter: e)
                            } label: {
                                EncounterRow(encounter: e)
                            }
                            .swipeActions {
                                Button("删除", role: .destructive) { pendingDelete = e }
                            }
                            .contextMenu {
                                Button {
                                    repeatFrom = e
                                } label: {
                                    Label("再记一次", systemImage: "arrow.clockwise.heart")
                                }
                                Button {
                                    editingRecord = e
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    pendingDelete = e
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    repeatFrom = e
                                } label: {
                                    Label("再记一次", systemImage: "arrow.clockwise.heart")
                                }
                                .tint(.accentColor)
                            }
                        }
                    } header: {
                        HStack {
                            Text(Fmt.month(group.month))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(group.items.count) 次 · \(group.items.reduce(0) { $0 + $1.count }) 回合")
                                .statNumber()
                        }
                    }
                }
            }
            .paperBackground()
            .overlay {
                if encounters.isEmpty {
                    EmptyState(symbol: "heart.text.square", title: "还没有记录",
                               message: "每次约会记一笔，时间、地点和感受都留得住",
                               actionTitle: "记一次", action: { creating = true })
                } else if filtered.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .searchable(text: $search, prompt: "人、地点、备注…")
            .navigationTitle("记录")
            .toolbar {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("记一次")
                .accessibilityIdentifier("addEncounter")
            }
            .sheet(isPresented: $creating) {
                EncounterEditView(encounter: nil, presetGirls: [])
            }
            .sheet(item: $repeatFrom) { e in
                EncounterEditView(encounter: nil, presetGirls: e.girls, presetPlace: e.place)
            }
            .sheet(item: $editingRecord) { e in
                EncounterEditView(encounter: e, presetGirls: [])
            }
            .confirmationDialog("删除这条记录？", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let e = pendingDelete { EncounterActions.delete(e, context: context) }
                    pendingDelete = nil
                }
            }
        }
    }
}

struct EncounterRow: View {
    let encounter: Encounter
    var showGirls: Bool = true
    var showPlace: Bool = true

    var body: some View {
        let d = encounter.details
        HStack(spacing: 14) {
            DateChip(date: encounter.date)
            VStack(alignment: .leading, spacing: 4) {
                if showGirls {
                    HStack(spacing: 6) {
                        stackedAvatars
                        Text(encounter.girlNames)
                            .font(Typo.display(17))
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    Text(encounter.date.formatted(.dateTime.hour().minute()))
                        .monospacedDigit()
                    if showPlace, let place = encounter.place {
                        Text("·")
                        Image(systemName: place.type.symbol)
                        Text(place.displayName).lineLimit(1)
                    }
                    if encounter.overnight {
                        Image(systemName: "moon").foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                let tags = d.highlights
                if !tags.isEmpty {
                    Text(Self.tagLine(tags))
                        .font(.caption2)
                        .foregroundStyle(Color.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 5) {
                    if encounter.stiRisk || encounter.pregnancyRisk {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.fertile)
                    }
                    if d.intensity > 0 {
                        IntensityGlyph(value: d.intensity, height: 11)
                    }
                    Text("×\(encounter.count)")
                        .font(.subheadline.weight(.semibold))
                        .statNumber()
                }
                if encounter.rating > 0 {
                    StarDisplay(value: encounter.rating)
                }
            }
        }
        .padding(.vertical, 3)
    }

    /// 这次的关键词：最多三个，多的折成「+N」
    static func tagLine(_ tags: [String]) -> String {
        var seen = Set<String>()
        let unique = tags.filter { seen.insert($0).inserted }
        let shown = unique.prefix(3).joined(separator: " · ")
        return unique.count > 3 ? shown + "  +\(unique.count - 3)" : shown
    }

    @ViewBuilder
    private var stackedAvatars: some View {
        let girls = Array(encounter.girls.prefix(3))
        if !girls.isEmpty {
            HStack(spacing: -6) {
                ForEach(girls) { g in
                    AvatarView(photoID: g.avatarID, name: g.name, size: 20)
                        .overlay(Circle().stroke(Palette.surface, lineWidth: 1.5))
                }
            }
        }
    }
}

/// 记录页顶部按人筛选：头像 + 次数，选中一个人时其余变淡
struct PersonFilterChip: View {
    /// nil 表示「全部」
    let girl: Girl?
    let count: Int
    let selected: Bool
    let dimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Group {
                    if let girl {
                        AvatarView(photoID: girl.avatarID, name: girl.name, size: 44)
                    } else {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Palette.surface))
                    }
                }
                .overlay {
                    Circle()
                        .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                        .padding(-3)
                }
                .overlay(alignment: .topTrailing) {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(selected ? Color.accentColor : Color.secondary.opacity(0.6)))
                        .overlay(Capsule().stroke(Palette.canvas, lineWidth: 2))
                        .offset(x: 6, y: -4)
                }
                Text(girl?.name ?? "全部")
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .frame(width: 54)
            }
            .opacity(dimmed ? 0.45 : 1)
            .scaleEffect(dimmed ? 0.94 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.chip)
        .accessibilityLabel(girl.map { "只看\($0.name)" } ?? "全部记录")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(girl.map { "filter-\($0.name)" } ?? "filter-all")
    }
}

/// 记录行左边的日期块
struct DateChip: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 20, weight: .medium, design: .serif))
                .foregroundStyle(Calendar.current.isDateInToday(date) ? Color.white : Color.primary)
            Text(date.formatted(Date.FormatStyle().weekday(.abbreviated).locale(Fmt.locale)))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Calendar.current.isDateInToday(date) ? Color.white.opacity(0.85) : Color.secondary)
        }
        .frame(width: 44, height: 48)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Calendar.current.isDateInToday(date) ? Color.accentColor : Color.accentColor.opacity(0.1))
        )
    }
}

@MainActor
enum EncounterActions {
    static func delete(_ encounter: Encounter, context: ModelContext) {
        MediaStore.shared.delete(encounter.details.photoIDs)
        Reminders.cancelRisk(encounterID: encounter.id)
        context.delete(encounter)
        try? context.save()
    }
}
