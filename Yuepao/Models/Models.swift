import Foundation
import SwiftData
import CoreLocation

// MARK: - 档案

@Model
final class Girl {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    /// 代号 / 昵称（列表里默认只显示它）
    var name: String = ""
    var statusRaw: String = RelationStatus.flirting.rawValue
    /// 位分（来自可自定义的选项列表）
    var rank: String = ""
    var city: String = ""
    var latitude: Double?
    var longitude: Double?
    var avatarID: String?
    /// 其余全部字段，JSON 编码的 `GirlDetails`
    var detailsData: Data = Data()

    var encounters: [Encounter] = []

    init(name: String = "") {
        self.name = name
    }
}

// MARK: - 约会 / 约炮记录

@Model
final class Encounter {
    var id: UUID = UUID()
    var date: Date = Date()
    var durationMinutes: Int = 0
    var overnight: Bool = false
    /// 回合数
    var count: Int = 1
    var protectionRaw: String = Protection.unrecorded.rawValue
    var condomBroke: Bool = false
    /// 满意度 0-5（0 = 未评）
    var rating: Int = 0
    /// 花费合计（由明细汇总，冗余存一份方便统计）
    var totalCost: Double = 0
    /// 其余字段，JSON 编码的 `EncounterDetails`
    var detailsData: Data = Data()

    var place: Place?
    @Relationship(inverse: \Girl.encounters) var girls: [Girl] = []

    init(date: Date = Date()) {
        self.date = date
    }
}

// MARK: - 地点

@Model
final class Place {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var name: String = ""
    var typeRaw: String = PlaceType.hotel.rawValue
    var latitude: Double?
    var longitude: Double?
    var city: String = ""
    var district: String = ""
    var address: String = ""
    var note: String = ""
    var rating: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Encounter.place) var encounters: [Encounter] = []

    init(name: String = "") {
        self.name = name
    }
}

// MARK: - 性健康检测

@Model
final class HealthTest {
    var id: UUID = UUID()
    var date: Date = Date()
    var items: String = ""
    var result: String = ""
    var note: String = ""
    var nextDate: Date?

    init(date: Date = Date()) {
        self.date = date
    }
}

// MARK: - Convenience

extension Girl {
    var details: GirlDetails {
        get { JSONCoding.decode(GirlDetails.self, from: detailsData, fallback: GirlDetails()) }
        set { detailsData = JSONCoding.encode(newValue) }
    }

    var status: RelationStatus {
        get { RelationStatus(rawValue: statusRaw) ?? .flirting }
        set { statusRaw = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var sortedEncounters: [Encounter] {
        encounters.sorted { $0.date > $1.date }
    }

    var lastEncounterDate: Date? { encounters.map(\.date).max() }
    var firstEncounterDate: Date? { encounters.map(\.date).min() }
    var totalRounds: Int { encounters.reduce(0) { $0 + $1.count } }

    /// 最近一次互动：见面或手动标记的联系
    func lastInteraction(details given: GirlDetails? = nil) -> Date? {
        let d = given ?? details
        return [lastEncounterDate, d.lastContactDate].compactMap { $0 }.max()
    }

    /// 摊到她身上的约会花费（多人约会平摊）
    var encounterSpending: Double {
        encounters.reduce(0) { $0 + $1.totalCost / Double(max($1.girls.count, 1)) }
    }

    func update(_ change: (inout GirlDetails) -> Void) {
        var d = details
        change(&d)
        details = d
    }
}

extension Encounter {
    var details: EncounterDetails {
        get { JSONCoding.decode(EncounterDetails.self, from: detailsData, fallback: EncounterDetails()) }
        set { detailsData = JSONCoding.encode(newValue) }
    }

    var protection: Protection {
        get { Protection(rawValue: protectionRaw) ?? .unrecorded }
        set { protectionRaw = newValue.rawValue }
    }

    /// 有怀孕风险（没有可靠避孕或破套）
    var pregnancyRisk: Bool {
        switch protection {
        case .none, .withdrawal: return true
        case .condom: return condomBroke
        default: return false
        }
    }

    /// 有性病风险（没戴套或破套）
    var stiRisk: Bool {
        switch protection {
        case .none, .withdrawal, .pill: return true
        case .condom, .both: return condomBroke
        case .unrecorded: return false
        }
    }

    var girlNames: String {
        girls.isEmpty ? "未选择对象" : girls.map(\.name).joined(separator: "、")
    }

    func update(_ change: (inout EncounterDetails) -> Void) {
        var d = details
        change(&d)
        details = d
    }
}

extension Place {
    var type: PlaceType {
        get { PlaceType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var lastUsed: Date? { encounters.map(\.date).max() }

    var displayName: String { name.isEmpty ? type.title : name }
}
