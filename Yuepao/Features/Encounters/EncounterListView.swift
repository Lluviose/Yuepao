import SwiftUI
import SwiftData

struct EncounterListView: View {
    @Query(sort: \Encounter.date, order: .reverse) private var encounters: [Encounter]
    @Environment(\.modelContext) private var context

    @State private var creating = false
    @State private var search = ""
    @State private var pendingDelete: Encounter?

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
                        }
                    } header: {
                        HStack {
                            Text(Fmt.month(group.month))
                            Spacer()
                            Text("\(group.items.count) 次 · \(group.items.reduce(0) { $0 + $1.count }) 回合")
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
            }
            .sheet(isPresented: $creating) {
                EncounterEditView(encounter: nil, presetGirls: [])
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
        HStack(spacing: 12) {
            avatars
            VStack(alignment: .leading, spacing: 3) {
                if showGirls {
                    Text(encounter.girlNames).font(.headline).lineLimit(1)
                }
                Text(Fmt.row(encounter.date))
                    .font(showGirls ? .caption : .subheadline)
                    .foregroundStyle(showGirls ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                if showPlace, let place = encounter.place {
                    Label(place.displayName, systemImage: place.type.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    if encounter.stiRisk || encounter.pregnancyRisk {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Text("×\(encounter.count)").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                if encounter.rating > 0 {
                    StarDisplay(value: encounter.rating)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var avatars: some View {
        if showGirls {
            let girls = Array(encounter.girls.prefix(2))
            ZStack(alignment: .bottomTrailing) {
                if let first = girls.first {
                    AvatarView(photoID: first.avatarID, name: first.name, size: 42)
                } else {
                    AvatarView(photoID: nil, name: "?", size: 42)
                }
                if girls.count > 1 {
                    AvatarView(photoID: girls[1].avatarID, name: girls[1].name, size: 22)
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
            }
        }
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
