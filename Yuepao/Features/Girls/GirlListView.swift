import SwiftUI
import SwiftData

struct GirlListView: View {
    @Query(sort: \Girl.createdAt, order: .reverse) private var girls: [Girl]
    @Environment(\.modelContext) private var context
    @ObservedObject private var config = ConfigStore.shared

    @AppStorage("girlSort") private var sortRaw = GirlSort.recent.rawValue
    @AppStorage("girlHideEnded") private var hideEnded = false
    @State private var search = ""
    @State private var statusFilter: RelationStatus?
    @State private var rankFilter: String?
    @State private var creating = false
    @State private var pendingDelete: Girl?

    private var sort: GirlSort { GirlSort(rawValue: sortRaw) ?? .recent }

    private var filtered: [Girl] {
        var list = girls
        if hideEnded { list = list.filter { $0.status.isCurrent } }
        if let statusFilter { list = list.filter { $0.status == statusFilter } }
        if let rankFilter { list = list.filter { $0.rank == rankFilter } }
        let q = search.trimmed
        if !q.isEmpty {
            list = list.filter { g in
                g.name.contains(q) || g.city.contains(q) || g.rank.contains(q) || g.details.realName.contains(q)
                    || g.details.tags.contains { $0.contains(q) } || g.details.occupation.contains(q)
            }
        }
        switch sort {
        case .recent:
            return list.sorted { ($0.lastInteraction() ?? $0.createdAt) > ($1.lastInteraction() ?? $1.createdAt) }
        case .rank:
            return list.sorted {
                let a = config.rankIndex($0.rank), b = config.rankIndex($1.rank)
                return a != b ? a < b : $0.encounters.count > $1.encounters.count
            }
        case .count:
            return list.sorted { $0.encounters.count > $1.encounters.count }
        case .rating:
            return list.sorted { $0.details.ratingOverall > $1.details.ratingOverall }
        case .created:
            return list.sorted { $0.createdAt > $1.createdAt }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !girls.isEmpty {
                    summary
                }
                ForEach(filtered) { girl in
                    NavigationLink {
                        GirlDetailView(girl: girl)
                    } label: {
                        GirlRow(girl: girl)
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) { pendingDelete = girl }
                    }
                }
            }
            .overlay {
                if girls.isEmpty {
                    ContentUnavailableView {
                        Label("还没有档案", systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text("点右上角 + 新建第一个档案")
                    } actions: {
                        Button("新建档案") { creating = true }.buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .searchable(text: $search, prompt: "代号、城市、标签…")
            .navigationTitle("后宫")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    filterMenu
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建档案")
                    .accessibilityIdentifier("addGirl")
                }
            }
            .sheet(isPresented: $creating) {
                GirlEditView(girl: nil)
            }
            .confirmationDialog(
                "删除「\(pendingDelete?.name ?? "")」的档案？",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("删除档案，保留约会记录", role: .destructive) {
                    if let g = pendingDelete { GirlActions.delete(g, alsoEncounters: false, context: context) }
                    pendingDelete = nil
                }
                Button("删除档案和只和她有关的记录", role: .destructive) {
                    if let g = pendingDelete { GirlActions.delete(g, alsoEncounters: true, context: context) }
                    pendingDelete = nil
                }
            } message: {
                Text("删除后无法恢复（除非有备份）")
            }
        }
    }

    private var summary: some View {
        let harem = girls.filter { $0.status.inHarem }.count
        let flirting = girls.filter { $0.status == .flirting }.count
        return HStack(spacing: 0) {
            SummaryCell(value: "\(harem)", label: "后宫")
            Divider()
            SummaryCell(value: "\(flirting)", label: "暧昧中")
            Divider()
            SummaryCell(value: "\(girls.count)", label: "全部档案")
        }
        .padding(.vertical, 4)
    }

    private var filterMenu: some View {
        Menu {
            Picker("排序", selection: $sortRaw) {
                ForEach(GirlSort.allCases) { s in
                    Text(s.title).tag(s.rawValue)
                }
            }
            Divider()
            Picker("状态", selection: $statusFilter) {
                Text("全部状态").tag(RelationStatus?.none)
                ForEach(RelationStatus.allCases) { s in
                    Text(s.title).tag(RelationStatus?.some(s))
                }
            }
            Picker("位分", selection: $rankFilter) {
                Text("全部位分").tag(String?.none)
                ForEach(config.options(.ranks), id: \.self) { r in
                    Text(r).tag(String?.some(r))
                }
            }
            Toggle("隐藏已断联 / 拉黑", isOn: $hideEnded)
        } label: {
            Image(systemName: statusFilter == nil && rankFilter == nil && !hideEnded
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
    }
}

struct SummaryCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct GirlRow: View {
    let girl: Girl

    var body: some View {
        let d = girl.details
        HStack(spacing: 12) {
            AvatarView(photoID: girl.avatarID, name: girl.name, size: 50, ring: girl.status.color)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(girl.name).font(.headline)
                    if !girl.rank.isEmpty { Badge(text: girl.rank) }
                    Badge(text: girl.status.title, color: girl.status.color)
                }
                Text(subtitle(d))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(girl.encounters.count)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("次").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitle(_ d: GirlDetails) -> String {
        var parts: [String] = []
        if let age = Fmt.age(d.birthday) { parts.append("\(age)岁") }
        if !girl.city.isEmpty { parts.append(girl.city) }
        if let last = girl.lastInteraction(details: d) {
            parts.append("上次 \(Fmt.daysAgo(last))")
        } else {
            parts.append("还没见过")
        }
        return parts.joined(separator: " · ")
    }
}

@MainActor
enum GirlActions {
    static func delete(_ girl: Girl, alsoEncounters: Bool, context: ModelContext) {
        let d = girl.details
        var photos = d.photoIDs
        if let avatar = girl.avatarID { photos.append(avatar) }
        if alsoEncounters {
            for e in girl.encounters where e.girls.count <= 1 {
                photos.append(contentsOf: e.details.photoIDs)
                Reminders.cancelRisk(encounterID: e.id)
                context.delete(e)
            }
        }
        PhotoStore.shared.delete(photos)
        context.delete(girl)
        try? context.save()
    }
}
