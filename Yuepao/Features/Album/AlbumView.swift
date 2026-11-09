import SwiftUI
import SwiftData

/// 相册：档案里的照片 + 每次记录里的照片、视频、实况，按月份排。
/// 传入 `girl` 时只看和她有关的
struct AlbumView: View {
    var girl: Girl?

    @Environment(\.modelContext) private var context
    @Query(sort: \Encounter.date, order: .reverse) private var encounters: [Encounter]
    @Query(sort: \Girl.createdAt) private var girls: [Girl]

    @State private var filter: Filter = .all
    @State private var infos: [String: MediaInfo] = [:]
    @State private var usage = MediaUsage()
    @State private var loaded = false
    @State private var viewing: MediaViewerTarget?

    enum Filter: String, CaseIterable, Identifiable {
        case all, photo, live, video

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .photo: return "照片"
            case .live: return "实况"
            case .video: return "视频"
            }
        }

        var kind: MediaKind? {
            switch self {
            case .all: return nil
            case .photo: return .photo
            case .live: return .live
            case .video: return .video
            }
        }
    }

    struct Entry: Identifiable {
        let id: String
        let date: Date
        let caption: String
    }

    struct MonthSection: Identifiable {
        let month: Date
        let entries: [Entry]
        var id: Date { month }
    }

    var body: some View {
        let all = entries
        let shown = all.filter { entry in
            guard let kind = filter.kind else { return true }
            return (infos[entry.id]?.kind ?? .photo) == kind
        }
        let captions = Dictionary(all.map { ($0.id, $0.caption) }, uniquingKeysWith: { first, _ in first })
        ScrollView {
            if all.isEmpty {
                EmptyState(symbol: "photo.on.rectangle.angled", title: "还没有照片或视频",
                           message: "在记录或档案里添加，原画质加密保存在这台手机上，不进系统相册。")
                    .padding(.top, 80)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Picker("类型", selection: $filter) {
                        ForEach(Filter.allCases) { f in
                            Text(f.title).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if shown.isEmpty {
                        Text("没有\(filter.title)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        grid(shown)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Palette.canvas)
        .navigationTitle(girl.map { "\($0.name)的相册" } ?? "相册")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: all.count) { await load(all.map(\.id)) }
        .fullScreenCover(item: $viewing) { target in
            MediaViewer(ids: shown.map(\.id), startID: target.id,
                        onDelete: { id in delete(id) },
                        onSetAvatar: avatarHandler,
                        caption: { id in captions[id] })
        }
        .sensoryFeedback(.selection, trigger: filter)
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(usage.count)")
                    .font(Typo.display(36, weight: .medium))
                    .statNumber()
                Text("项")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if usage.bytes > 0 {
                    Text(Fmt.bytes(usage.bytes))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text(usage.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label("原画质加密保存，只在这台手机上", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .opacity(loaded ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: loaded)
    }

    // MARK: 网格

    private func grid(_ shown: [Entry]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                  spacing: 2, pinnedViews: [.sectionHeaders]) {
            ForEach(sections(shown)) { section in
                Section {
                    ForEach(section.entries) { entry in
                        Button {
                            Presentation.instant { viewing = MediaViewerTarget(id: entry.id) }
                        } label: {
                            MediaTile(id: entry.id, pixels: 384, cornerRadius: 0)
                        }
                        .buttonStyle(.plain)
                        .aspectRatio(1, contentMode: .fit)
                        .accessibilityIdentifier("albumItem")
                    }
                } header: {
                    HStack {
                        Text(Fmt.month(section.month))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(section.entries.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
        }
    }

    // MARK: 数据

    private var entries: [Entry] {
        var list: [Entry] = []
        var seen = Set<String>()
        let people = girl.map { [$0] } ?? girls
        for g in people {
            for id in g.details.photoIDs {
                guard seen.insert(id).inserted else { continue }
                let info = infos[id]
                list.append(Entry(id: id, date: info?.capturedAt ?? info?.importedAt ?? g.createdAt,
                                  caption: "\(g.name)的相册"))
            }
        }
        for e in encounters {
            if let girl, !e.girls.contains(where: { $0.id == girl.id }) { continue }
            for id in e.details.photoIDs {
                guard seen.insert(id).inserted else { continue }
                list.append(Entry(id: id, date: e.date, caption: "\(e.girlNames) · \(Fmt.shortDate(e.date))"))
            }
        }
        return list.sorted { $0.date > $1.date }
    }

    private func sections(_ list: [Entry]) -> [MonthSection] {
        let cal = Calendar.current
        var order: [Date] = []
        var groups: [Date: [Entry]] = [:]
        for entry in list {
            let month = cal.date(from: cal.dateComponents([.year, .month], from: entry.date)) ?? entry.date
            if groups[month] == nil { order.append(month) }
            groups[month, default: []].append(entry)
        }
        return order.map { MonthSection(month: $0, entries: groups[$0] ?? []) }
    }

    private func load(_ ids: [String]) async {
        let result = await Task.detached(priority: .userInitiated) { () -> ([String: MediaInfo], MediaUsage) in
            var map: [String: MediaInfo] = [:]
            for id in ids {
                if let info = MediaStore.shared.info(id) { map[id] = info }
            }
            return (map, MediaStore.shared.usage(of: ids))
        }.value
        infos = result.0
        usage = result.1
        loaded = true
    }

    private func delete(_ id: String) {
        for g in girls where g.details.photoIDs.contains(id) {
            g.update { $0.photoIDs.removeAll { $0 == id } }
        }
        for e in encounters where e.details.photoIDs.contains(id) {
            e.update { $0.photoIDs.removeAll { $0 == id } }
        }
        MediaStore.shared.delete(id)
        try? context.save()
    }

    /// 只有她自己的相册里才能「设为头像」
    private var avatarHandler: ((String) -> Void)? {
        guard girl != nil else { return nil }
        return { id in setAvatar(id) }
    }

    private func setAvatar(_ id: String) {
        guard let girl else { return }
        Task {
            await girl.setAvatar(fromMedia: id)
            try? context.save()
        }
    }
}
