import SwiftUI
import MapKit

// MARK: - 模式和筛选

enum MapMode: String, CaseIterable, Identifiable {
    case all, harem, places, heat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .harem: return "后宫"
        case .places: return "地点"
        case .heat: return "热力"
        }
    }

    var showsPeople: Bool { self == .all || self == .harem }
    var showsSpots: Bool { self == .all || self == .places }
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

/// 底图样式：默认是低饱和的素雅底图，标记更突出
enum MapStyle: String, CaseIterable, Identifiable {
    case muted, standard, satellite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .muted: return "素雅"
        case .standard: return "标准"
        case .satellite: return "卫星"
        }
    }

    var symbol: String {
        switch self {
        case .muted: return "circle.lefthalf.filled"
        case .standard: return "map"
        case .satellite: return "globe.asia.australia"
        }
    }

    func makeConfiguration() -> MKMapConfiguration {
        switch self {
        case .muted:
            let c = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            c.pointOfInterestFilter = .excludingAll
            return c
        case .standard:
            let c = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
            c.pointOfInterestFilter = .excludingAll
            return c
        case .satellite:
            let c = MKHybridMapConfiguration(elevationStyle: .realistic)
            c.pointOfInterestFilter = .excludingAll
            return c
        }
    }
}

// MARK: - 地图上的元素

enum MapFocus: Hashable, Identifiable {
    case girl(UUID)
    case place(UUID)

    var id: String {
        switch self {
        case .girl(let id): return "g-\(id.uuidString)"
        case .place(let id): return "p-\(id.uuidString)"
        }
    }
}

struct MapPerson: Identifiable, Equatable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let tone: UIColor
    let avatarID: String?
    /// 回放时还没到她出现的时间：标记留在地图上但隐藏，聚合才能保持正确
    var active = true

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MapSpot: Identifiable, Equatable {
    let id: UUID
    let name: String
    let type: PlaceType
    let latitude: Double
    let longitude: Double
    let count: Int
    /// 回放时还没去过：隐藏
    var active = true

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// 她和某个地点之间有过记录
struct MapLink: Hashable {
    let girl: UUID
    let place: UUID
}

struct HeatPoint: Equatable {
    let latitude: Double
    let longitude: Double
    /// 0...1
    let weight: Double
}

/// 某一时刻地图上要显示的全部内容
struct MapContent {
    var people: [MapPerson] = []
    var spots: [MapSpot] = []
    var links: [MapLink] = []
    var heat: [HeatPoint] = []
    var stats = MapStats()

    var isEmpty: Bool {
        !people.contains { $0.active } && !spots.contains { $0.active } && heat.isEmpty
    }

    var focuses: [MapFocus] {
        people.filter(\.active).map { MapFocus.girl($0.id) } + spots.filter(\.active).map { MapFocus.place($0.id) }
    }

    func coordinate(of focus: MapFocus) -> CLLocationCoordinate2D? {
        switch focus {
        case .girl(let id): return people.first { $0.id == id }?.coordinate
        case .place(let id): return spots.first { $0.id == id }?.coordinate
        }
    }
}

struct MapStats: Equatable {
    var people = 0
    var spots = 0
    var encounters = 0
    var cities = 0
}

// MARK: - 数据快照

/// 按筛选条件从数据库整理一次；回放时用同一份快照按时间截取
struct MapSnapshot {
    struct Person {
        let person: MapPerson
        /// 回放时从这一天起出现：第一次见面，没见过就用建档时间
        let since: Date
        let city: String
    }

    struct Visit {
        let date: Date
        let girlIDs: [UUID]
    }

    struct Spot {
        let id: UUID
        let name: String
        let type: PlaceType
        let latitude: Double
        let longitude: Double
        let city: String
        /// 按时间排序，已按时间范围和人筛选
        let visits: [Visit]
    }

    var people: [Person] = []
    var spots: [Spot] = []

    /// 最早的一条：回放从这里开始
    var firstDate: Date? {
        let dates = people.map(\.since) + spots.compactMap { $0.visits.first?.date }
        return dates.min()
    }

    init() {}

    init(girls: [Girl], places: [Place], range: TimeRange, girlFilter: UUID?, hideEnded: Bool, tone: (Girl) -> UIColor) {
        for g in girls {
            guard let lat = g.latitude, let lon = g.longitude else { continue }
            if hideEnded && !g.status.isCurrent { continue }
            if let girlFilter, g.id != girlFilter { continue }
            let person = MapPerson(id: g.id, name: g.name, latitude: lat, longitude: lon,
                                   tone: tone(g), avatarID: g.avatarID)
            people.append(Person(person: person, since: g.firstEncounterDate ?? g.createdAt, city: g.city.trimmed))
        }
        for p in places {
            guard let lat = p.latitude, let lon = p.longitude else { continue }
            let visits = p.encounters
                .filter { e in range.contains(e.date) && (girlFilter == nil || e.girls.contains { $0.id == girlFilter }) }
                .sorted { $0.date < $1.date }
                .map { Visit(date: $0.date, girlIDs: $0.girls.map(\.id)) }
            guard !visits.isEmpty else { continue }
            spots.append(Spot(id: p.id, name: p.displayName, type: p.type, latitude: lat, longitude: lon,
                              city: p.city.trimmed, visits: visits))
        }
    }

    /// 截至 `cutoff`（nil 表示全部）时地图上的内容。
    /// 回放时所有标记都保留，只是把还没到时间的标成 inactive（隐藏），
    /// 这样回放过程中不增删标记，MapKit 的聚合一直是对的。
    func content(mode: MapMode, until cutoff: Date? = nil) -> MapContent {
        var result = MapContent()
        var peopleItems: [MapPerson] = []
        var spotItems: [MapSpot] = []
        var activeSpots: [MapSpot] = []
        var links = Set<MapLink>()
        var cities = Set<String>()
        var activePeople = 0
        var total = 0

        for p in people {
            var item = p.person
            item.active = cutoff.map { p.since <= $0 } ?? true
            if item.active {
                activePeople += 1
                if !p.city.isEmpty { cities.insert(p.city) }
            }
            peopleItems.append(item)
        }
        for s in spots {
            let visits = cutoff.map { c in s.visits.filter { $0.date <= c } } ?? s.visits
            let spot = MapSpot(id: s.id, name: s.name, type: s.type, latitude: s.latitude,
                               longitude: s.longitude, count: visits.count, active: !visits.isEmpty)
            spotItems.append(spot)
            guard spot.active else { continue }
            activeSpots.append(spot)
            for v in visits {
                for g in v.girlIDs { links.insert(MapLink(girl: g, place: s.id)) }
            }
            total += visits.count
            if !s.city.isEmpty { cities.insert(s.city) }
        }

        if mode.showsPeople { result.people = peopleItems }
        if mode.showsSpots { result.spots = spotItems }
        if mode == .heat {
            let maxCount = Double(activeSpots.map(\.count).max() ?? 1)
            result.heat = activeSpots.map {
                HeatPoint(latitude: $0.latitude, longitude: $0.longitude,
                          weight: (Double($0.count) / max(maxCount, 1)).squareRoot())
            }
        }
        result.links = Array(links)
        result.stats = MapStats(people: activePeople, spots: activeSpots.count, encounters: total, cities: cities.count)
        return result
    }
}

// MARK: - 回放

struct MapPlayback: Equatable {
    var start: Date
    var end: Date
    var progress: Double = 0
    var playing = true

    var cutoff: Date {
        start.addingTimeInterval(end.timeIntervalSince(start) * progress)
    }

    /// 时间跨度超过一年按月显示，否则按天
    var dateTitle: String {
        end.timeIntervalSince(start) > 400 * 86_400 ? Fmt.month(cutoff) : Fmt.shortDate(cutoff)
    }

    var isFinished: Bool { progress >= 1 }
}

// MARK: - 长按放下的新地点

struct DraftPin: Equatable {
    let latitude: Double
    let longitude: Double
    var name = ""
    var address = ""
    var city = ""
    var district = ""
    var resolved = false

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var picked: PickedLocation {
        PickedLocation(coordinate: coordinate, name: name, address: address, city: city, district: district)
    }
}

enum MapFormat {
    static func distance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 { return "\(max(Int(meters / 10) * 10, 10)) 米" }
        if meters < 100_000 { return String(format: "%.1f 公里", meters / 1000) }
        return "\(Int(meters / 1000)) 公里"
    }
}
