import SwiftUI
import MapKit

/// 足迹总览：城市排行（点一下地图飞过去）、常去的地点、城市印章
struct MapOverviewView: View {
    let girls: [Girl]
    let places: [Place]
    let range: TimeRange
    let girlFilter: UUID?
    let hideEnded: Bool
    var onFly: ([CLLocationCoordinate2D]) -> Void
    var onFocusPlace: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    struct CityRow: Identifiable {
        let city: String
        var people = Set<UUID>()
        var places = Set<UUID>()
        var encounters = 0
        var first: Date?
        var coordinates: [CLLocationCoordinate2D] = []
        var id: String { city }
    }

    struct PlaceRank: Identifiable {
        let place: Place
        let count: Int
        var id: UUID { place.id }
    }

    private func matches(_ e: Encounter) -> Bool {
        range.contains(e.date) && (girlFilter == nil || e.girls.contains { $0.id == girlFilter })
    }

    private var visibleGirls: [Girl] {
        girls.filter { g in
            (!hideEnded || g.status.isCurrent) && (girlFilter == nil || g.id == girlFilter)
        }
    }

    private var cityRows: [CityRow] {
        var map: [String: CityRow] = [:]
        for g in visibleGirls {
            let city = g.city.trimmed
            guard !city.isEmpty else { continue }
            map[city, default: CityRow(city: city)].people.insert(g.id)
            if let c = g.coordinate { map[city]?.coordinates.append(c) }
        }
        for p in places {
            let city = p.city.trimmed
            guard !city.isEmpty else { continue }
            let list = p.encounters.filter(matches)
            guard !list.isEmpty else { continue }
            var row = map[city] ?? CityRow(city: city)
            row.places.insert(p.id)
            row.encounters += list.count
            if let earliest = list.map(\.date).min() {
                row.first = min(row.first ?? earliest, earliest)
            }
            if let c = p.coordinate { row.coordinates.append(c) }
            map[city] = row
        }
        return map.values.sorted { ($0.encounters, $0.people.count) > ($1.encounters, $1.people.count) }
    }

    private var topPlaces: [PlaceRank] {
        places.map { PlaceRank(place: $0, count: $0.encounters.filter(matches).count) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        let rows = cityRows
        let ranks = topPlaces
        let unplaced = visibleGirls.filter { $0.coordinate == nil }.count
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header(rows)
                    if rows.isEmpty {
                        ContentUnavailableView("还没有城市数据", systemImage: "building.2",
                                               description: Text("给档案和地点填上城市，就会出现在这里"))
                    } else {
                        citySection(rows)
                    }
                    if !ranks.isEmpty { placeSection(ranks) }
                    links
                    if unplaced > 0 {
                        Text("还有 \(unplaced) 人没有设置常驻位置，所以不在地图上。在档案里编辑「常驻位置」就能显示。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .navigationTitle("足迹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("closeOverview")
                }
            }
        }
    }

    // MARK: 总数

    private func header(_ rows: [CityRow]) -> some View {
        let people = Set(rows.flatMap(\.people)).count
        let spots = Set(rows.flatMap(\.places)).count
        let total = rows.reduce(0) { $0 + $1.encounters }
        return VStack(alignment: .leading, spacing: 14) {
            Text(range == .all ? "全部足迹" : range.title).eyebrow()
            HStack(spacing: 0) {
                headerCell(rows.count, "座城市")
                headerCell(spots, "个地点")
                headerCell(total, "次")
                headerCell(people, "人")
            }
        }
    }

    private func headerCell(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(Typo.display(30, weight: .medium))
                .statNumber()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 城市

    private func citySection(_ rows: [CityRow]) -> some View {
        let most = max(rows.map(\.encounters).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("城市").eyebrow()
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.leading, 16) }
                    Button {
                        guard !row.coordinates.isEmpty else { return }
                        Haptics.light()
                        dismiss()
                        onFly(row.coordinates)
                    } label: {
                        cityRow(row, fraction: Double(row.encounters) / Double(most))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("city-\(row.city)")
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func cityRow(_ row: CityRow, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.city)
                    .font(Typo.display(19))
                Spacer()
                Text("\(row.encounters)")
                    .font(Typo.display(19, weight: .semibold))
                    .statNumber()
                Text("次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 6)
            }
            ProgressView(value: fraction)
                .tint(Color.accentColor)
            Text(cityCaption(row))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .contentShape(Rectangle())
    }

    private func cityCaption(_ row: CityRow) -> String {
        var parts: [String] = []
        if !row.people.isEmpty { parts.append("\(row.people.count) 人") }
        if !row.places.isEmpty { parts.append("\(row.places.count) 个地点") }
        if let first = row.first { parts.append("始于 " + Fmt.month(first)) }
        return parts.joined(separator: " · ")
    }

    // MARK: 常去的地点

    private func placeSection(_ ranks: [PlaceRank]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最常去").eyebrow()
            VStack(spacing: 0) {
                ForEach(Array(ranks.enumerated()), id: \.element.id) { index, rank in
                    if index > 0 { Divider().padding(.leading, 62) }
                    Button {
                        Haptics.light()
                        dismiss()
                        onFocusPlace(rank.place.id)
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(Typo.display(15, weight: .semibold))
                                .foregroundStyle(index == 0 ? Palette.gold : Color.secondary)
                                .frame(width: 18)
                            IconBadge(symbol: rank.place.type.symbol, color: .accentColor, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rank.place.displayName)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text([rank.place.type.title, rank.place.district].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(rank.count) 次")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(rank.place.coordinate == nil)
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.7),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: 更多

    private var links: some View {
        VStack(spacing: 0) {
            NavigationLink {
                CityStampsView()
            } label: {
                linkRow("城市印章", symbol: "seal")
            }
            Divider().padding(.leading, 56)
            NavigationLink {
                PlaceListView()
            } label: {
                linkRow("全部地点", symbol: "mappin.and.ellipse")
            }
        }
        .buttonStyle(.plain)
        .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func linkRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: Palette.gold, size: 30)
            Text(title).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
