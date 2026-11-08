import SwiftUI
import SwiftData
import MapKit

enum MapLayer: String, CaseIterable, Identifiable {
    case all, harem, places
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部"
        case .harem: return "后宫分布"
        case .places: return "约会地点"
        }
    }
}

enum TimeRange: String, CaseIterable, Identifiable {
    case all, year, days90, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部时间"
        case .year: return "今年"
        case .days90: return "近 90 天"
        case .month: return "本月"
        }
    }

    func contains(_ date: Date) -> Bool {
        let cal = Calendar.current
        switch self {
        case .all: return true
        case .year: return cal.isDate(date, equalTo: Date(), toGranularity: .year)
        case .month: return cal.isDate(date, equalTo: Date(), toGranularity: .month)
        case .days90: return date >= (cal.date(byAdding: .day, value: -90, to: Date()) ?? Date())
        }
    }
}

struct HaremMapScreen: View {
    @Query private var girls: [Girl]
    @Query private var places: [Place]
    @ObservedObject private var config = ConfigStore.shared

    @AppStorage("mapColorByRank") private var colorByRank = false
    @AppStorage("mapHideEnded") private var hideEnded = true
    @State private var layer: MapLayer = .all
    @State private var range: TimeRange = .all
    @State private var girlFilter: UUID?
    @State private var selection: MapSelection?
    @State private var showCities = false

    private var filterGirl: Girl? {
        girlFilter.flatMap { id in girls.first { $0.id == id } }
    }

    private var girlItems: [MapGirlItem] {
        guard layer != .places else { return [] }
        return girls.compactMap { g in
            guard let c = g.coordinate else { return nil }
            if hideEnded && !g.status.isCurrent { return nil }
            if let girlFilter, g.id != girlFilter { return nil }
            return MapGirlItem(id: g.id, name: g.name, coordinate: c, color: color(for: g), avatarID: g.avatarID)
        }
    }

    private var placeItems: [MapPlaceItem] {
        guard layer != .harem else { return [] }
        return places.compactMap { p in
            guard let c = p.coordinate else { return nil }
            let count = p.encounters.filter { e in
                range.contains(e.date) && (girlFilter == nil || e.girls.contains { $0.id == girlFilter })
            }.count
            guard count > 0 else { return nil }
            return MapPlaceItem(id: p.id, name: p.displayName, coordinate: c, count: count)
        }
    }

    private func color(for girl: Girl) -> UIColor {
        guard colorByRank else { return girl.status.uiColor }
        let palette: [UIColor] = [.systemRed, .systemPink, .systemPurple, .systemIndigo, .systemBlue, .systemTeal, .systemGray]
        let index = config.rankIndex(girl.rank)
        return index == Int.max ? .systemGray : palette[min(index, palette.count - 1)]
    }

    var body: some View {
        let gItems = girlItems
        let pItems = placeItems
        NavigationStack {
            ClusterMapView(girls: gItems, places: pItems) { selection = $0 }
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .top) {
                    controls(girlCount: gItems.count, placeTotal: pItems.reduce(0) { $0 + $1.count })
                }
                .navigationTitle("地图")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showCities = true
                        } label: {
                            Image(systemName: "building.2")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            PlaceListView()
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                    }
                }
                .sheet(item: $selection) { sel in
                    selectionSheet(sel)
                        .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $showCities) {
                    NavigationStack {
                        CityStatsView(girls: girls, places: places, range: range)
                    }
                    .presentationDetents([.medium, .large])
                }
                .onAppear { LocationPermission.requestIfNeeded() }
        }
    }

    private func controls(girlCount: Int, placeTotal: Int) -> some View {
        VStack(spacing: 8) {
            Picker("图层", selection: $layer) {
                ForEach(MapLayer.allCases) { l in
                    Text(l.title).tag(l)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Menu {
                    Picker("时间", selection: $range) {
                        ForEach(TimeRange.allCases) { r in
                            Text(r.title).tag(r)
                        }
                    }
                } label: {
                    chip(range.title, systemImage: "calendar")
                }
                Menu {
                    Picker("人", selection: $girlFilter) {
                        Text("所有人").tag(UUID?.none)
                        ForEach(girls.sorted { $0.encounters.count > $1.encounters.count }) { g in
                            Text(g.name).tag(UUID?.some(g.id))
                        }
                    }
                } label: {
                    chip(filterGirl?.name ?? "所有人", systemImage: "person")
                }
                Menu {
                    Toggle("隐藏已断联 / 拉黑", isOn: $hideEnded)
                    Picker("头像边框颜色", selection: $colorByRank) {
                        Text("按关系状态").tag(false)
                        Text("按位分").tag(true)
                    }
                } label: {
                    chip("显示", systemImage: "slider.horizontal.3")
                }
                Spacer(minLength: 0)
            }

            Text(summaryText(girlCount: girlCount, placeTotal: placeTotal))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func summaryText(girlCount: Int, placeTotal: Int) -> String {
        switch layer {
        case .harem: return "地图上 \(girlCount) 人（只显示设置了常驻位置的档案）"
        case .places: return "\(range.title)在地图上的地点共 \(placeTotal) 次"
        case .all: return "\(girlCount) 人 · 地点共 \(placeTotal) 次"
        }
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func selectionSheet(_ sel: MapSelection) -> some View {
        switch sel {
        case .girl(let id):
            if let g = girls.first(where: { $0.id == id }) {
                NavigationStack { GirlDetailView(girl: g) }
            }
        case .place(let id):
            if let p = places.first(where: { $0.id == id }) {
                NavigationStack { PlaceDetailView(place: p) }
            }
        case .group(let girlIDs, let placeIDs):
            NavigationStack {
                List {
                    let gs = girls.filter { girlIDs.contains($0.id) }
                    let ps = places.filter { placeIDs.contains($0.id) }
                    if !gs.isEmpty {
                        Section("后宫") {
                            ForEach(gs) { g in
                                NavigationLink {
                                    GirlDetailView(girl: g)
                                } label: {
                                    GirlRow(girl: g)
                                }
                            }
                        }
                    }
                    if !ps.isEmpty {
                        Section("地点") {
                            ForEach(ps) { p in
                                NavigationLink {
                                    PlaceDetailView(place: p)
                                } label: {
                                    PlaceRow(place: p)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("这里有")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// MARK: - 城市统计

struct CityStatsView: View {
    let girls: [Girl]
    let places: [Place]
    let range: TimeRange

    struct CityRow: Identifiable {
        let city: String
        var girls: Int = 0
        var encounters: Int = 0
        var id: String { city }
    }

    private var rows: [CityRow] {
        var map: [String: CityRow] = [:]
        for g in girls where g.status.isCurrent {
            let city = g.city.trimmed
            guard !city.isEmpty else { continue }
            map[city, default: CityRow(city: city)].girls += 1
        }
        for p in places {
            let city = p.city.trimmed
            guard !city.isEmpty else { continue }
            let n = p.encounters.filter { range.contains($0.date) }.count
            guard n > 0 else { continue }
            map[city, default: CityRow(city: city)].encounters += n
        }
        return map.values.sorted { ($0.encounters, $0.girls) > ($1.encounters, $1.girls) }
    }

    var body: some View {
        let data = rows
        List {
            Section {
                HStack(spacing: 0) {
                    SummaryCell(value: "\(data.count)", label: "已点亮城市")
                    Divider()
                    SummaryCell(value: "\(data.reduce(0) { $0 + $1.girls })", label: "后宫人数")
                    Divider()
                    SummaryCell(value: "\(data.reduce(0) { $0 + $1.encounters })", label: "次数")
                }
                .padding(.vertical, 4)
            } footer: {
                Text("人数按档案里填的城市统计（不含断联/拉黑），次数按地点的城市统计（\(range.title)）。")
            }

            Section("城市") {
                ForEach(data) { row in
                    HStack {
                        Text(row.city)
                        Spacer()
                        if row.girls > 0 { Badge(text: "\(row.girls) 人", color: .purple) }
                        if row.encounters > 0 { Badge(text: "\(row.encounters) 次", color: .orange) }
                    }
                }
            }
        }
        .overlay {
            if data.isEmpty {
                ContentUnavailableView("还没有城市数据", systemImage: "building.2", description: Text("给档案和地点填上城市就会出现在这里"))
            }
        }
        .navigationTitle("城市")
        .navigationBarTitleDisplayMode(.inline)
    }
}
