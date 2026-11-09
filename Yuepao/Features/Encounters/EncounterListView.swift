import SwiftUI
import SwiftData

struct EncounterListView: View {
    @Query(sort: \Encounter.date, order: .reverse) private var encounters: [Encounter]
    @Environment(\.modelContext) private var context

    @State private var creating = false
    @State private var search = ""
    @State private var pendingDelete: Encounter?
    @State private var repeatFrom: Encounter?

    private var filtered: [Encounter] {
        let q = search.trimmed
        guard !q.isEmpty else { return encounters }
        return encounters.filter { e in
            e.girls.contains { $0.name.contains(q) }
                || (e.place?.name.contains(q) ?? false)
                || (e.place?.city.contains(q) ?? false)
                || e.details.notes.contains(q)
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
            .overlay {
                if encounters.isEmpty {
                    ContentUnavailableView {
                        Label("还没有记录", systemImage: "heart.text.square")
                    } description: {
                        Text("点右上角 + 记录一次")
                    } actions: {
                        Button("记一次") { creating = true }.buttonStyle(.borderedProminent)
                    }
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
        HStack(spacing: 14) {
            DateChip(date: encounter.date)
            VStack(alignment: .leading, spacing: 4) {
                if showGirls {
                    HStack(spacing: 6) {
                        stackedAvatars
                        Text(encounter.girlNames)
                            .font(.headline)
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
                        Image(systemName: "moon.fill").foregroundStyle(.indigo)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 4) {
                    if encounter.stiRisk || encounter.pregnancyRisk {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
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

    @ViewBuilder
    private var stackedAvatars: some View {
        let girls = Array(encounter.girls.prefix(3))
        if !girls.isEmpty {
            HStack(spacing: -6) {
                ForEach(girls) { g in
                    AvatarView(photoID: g.avatarID, name: g.name, size: 20)
                        .overlay(Circle().stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 1.5))
                }
            }
        }
    }
}

/// 记录行左边的日期块
struct DateChip: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
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
        PhotoStore.shared.delete(encounter.details.photoIDs)
        Reminders.cancelRisk(encounterID: encounter.id)
        context.delete(encounter)
        try? context.save()
    }
}
