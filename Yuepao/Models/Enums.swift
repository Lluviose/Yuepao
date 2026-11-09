import SwiftUI
import UIKit

/// 关系状态
enum RelationStatus: String, CaseIterable, Identifiable, Codable {
    case flirting, active, steady, cooling, ended, blocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flirting: return "暧昧中"
        case .active: return "在约"
        case .steady: return "稳定"
        case .cooling: return "冷却"
        case .ended: return "断联"
        case .blocked: return "拉黑"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .flirting: return UIColor(red: 0.78, green: 0.60, blue: 0.38, alpha: 1)   // 香槟
        case .active: return UIColor(red: 0.69, green: 0.30, blue: 0.39, alpha: 1)     // 玫瑰木
        case .steady: return UIColor(red: 0.52, green: 0.17, blue: 0.27, alpha: 1)     // 酒红
        case .cooling: return UIColor(red: 0.43, green: 0.52, blue: 0.60, alpha: 1)    // 雾蓝
        case .ended: return UIColor(red: 0.60, green: 0.60, blue: 0.62, alpha: 1)
        case .blocked: return UIColor(red: 0.32, green: 0.32, blue: 0.34, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    /// 算作"后宫"的状态
    var inHarem: Bool { self == .active || self == .steady || self == .cooling }

    /// 仍在联系中的状态
    var isCurrent: Bool { self == .flirting || self == .active || self == .steady || self == .cooling }
}

/// 安全措施
enum Protection: String, CaseIterable, Identifiable, Codable {
    case unrecorded, condom, pill, both, withdrawal, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unrecorded: return "未记录"
        case .condom: return "安全套"
        case .pill: return "她吃短效药"
        case .both: return "安全套 + 药"
        case .withdrawal: return "体外"
        case .none: return "无措施"
        }
    }

    var symbol: String {
        switch self {
        case .unrecorded: return "questionmark.circle"
        case .condom, .both: return "checkmark.shield"
        case .pill: return "pills"
        case .withdrawal, .none: return "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .unrecorded: return .secondary
        case .condom, .both: return Palette.status
        case .pill: return Palette.todo
        case .withdrawal, .none: return Palette.fertile
        }
    }
}

/// 地点类型
enum PlaceType: String, CaseIterable, Identifiable, Codable {
    case hotel, homestay, herHome, myHome, car, outdoor, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hotel: return "酒店"
        case .homestay: return "民宿"
        case .herHome: return "她家"
        case .myHome: return "我家"
        case .car: return "车里"
        case .outdoor: return "户外"
        case .other: return "其他"
        }
    }

    var symbol: String {
        switch self {
        case .hotel: return "bed.double"
        case .homestay: return "building.2"
        case .herHome: return "house"
        case .myHome: return "house.fill"
        case .car: return "car"
        case .outdoor: return "tree"
        case .other: return "mappin"
        }
    }
}

/// 她是否知道你有别人
enum Awareness: String, CaseIterable, Identifiable, Codable {
    case unset, unaware, suspects, knows, accepts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unset: return "未设置"
        case .unaware: return "不知道"
        case .suspects: return "可能察觉"
        case .knows: return "知道"
        case .accepts: return "知道且接受"
        }
    }
}

enum GirlSort: String, CaseIterable, Identifiable {
    case recent, rank, count, rating, created

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "最近互动"
        case .rank: return "位分"
        case .count: return "次数"
        case .rating: return "综合评分"
        case .created: return "建档时间"
        }
    }
}

enum Choices {
    static let durations: [Int] = [0, 15, 30, 45, 60, 90, 120, 180, 240, 360, 480, 720]
    static let contactGoals: [Int] = [0, 3, 5, 7, 10, 14, 21, 30, 60]
    static let initiators: [String] = ["", "我", "她", "互相"]
    static let testResults: [String] = ["阴性", "阳性", "待出结果", "其他"]

    static func durationTitle(_ minutes: Int) -> String {
        if minutes == 0 { return "未记录" }
        if minutes < 60 { return "\(minutes) 分钟" }
        let h = Double(minutes) / 60
        return h == h.rounded() ? "\(Int(h)) 小时" : String(format: "%.1f 小时", h)
    }
}
