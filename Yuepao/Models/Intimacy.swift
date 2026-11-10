import SwiftUI

/// 这一次的强度。0 表示没记录
enum Intensity: Int, CaseIterable, Identifiable {
    case gentle = 1, moderate, intense, wild

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .gentle: return "温柔"
        case .moderate: return "适中"
        case .intense: return "激烈"
        case .wild: return "狂野"
        }
    }

    static func title(_ value: Int) -> String? {
        Intensity(rawValue: value)?.title
    }
}

/// 道具、特质、玩法这类长列表分组显示。
/// 分组只认默认选项的名字；自己加的、改过名的都归到「自定义」
enum OptionGroups {
    struct Group: Identifiable {
        let title: String
        let items: [String]
        var id: String { title }
    }

    static let play: [(title: String, items: [String])] = [
        ("亲密", ["接吻", "前戏", "口", "舔", "手", "按摩"]),
        ("情趣", ["共浴", "镜前", "角色扮演", "一起看片", "冰火"]),
        ("进阶", ["束缚", "拍打", "支配", "语言刺激", "边缘控制"])
    ]

    static let toys: [(title: String, items: [String])] = [
        ("震动", ["跳蛋", "震动棒", "AV 棒", "吮吸器", "震动环"]),
        ("束缚", ["眼罩", "手铐", "绳子", "项圈", "口球"]),
        ("刺激", ["乳夹", "皮拍", "鞭子", "低温蜡烛"]),
        ("感官", ["羽毛", "冰块", "按摩油"]),
        ("其他", ["润滑液", "肛塞"])
    ]

    static let traits: [(title: String, items: [String])] = [
        ("倾向", ["恋痛", "M 倾向", "S 倾向", "喜欢被支配", "喜欢主导", "S/M 皆可"]),
        ("体质", ["敏感体质", "易高潮", "多次高潮", "潮吹", "慢热", "怕痒"]),
        ("风格", ["主动", "害羞", "叫声大", "爱接吻", "喜欢温柔", "喜欢粗暴", "喜欢被夸", "喜欢脏话", "事后黏人"])
    ]

    static func table(for key: OptionKey) -> [(title: String, items: [String])]? {
        switch key {
        case .play: return play
        case .toys: return toys
        case .traits: return traits
        default: return nil
        }
    }

    /// 按分组整理 `options`（保留用户设置的顺序）；这个选项没有分组时返回 nil
    static func groups(for key: OptionKey, options: [String]) -> [Group]? {
        guard let table = table(for: key) else { return nil }
        var used = Set<String>()
        var result: [Group] = []
        for entry in table {
            let items = options.filter { entry.items.contains($0) }
            used.formUnion(items)
            if !items.isEmpty { result.append(Group(title: entry.title, items: items)) }
        }
        let rest = options.filter { !used.contains($0) }
        if !rest.isEmpty { result.append(Group(title: "自定义", items: rest)) }
        return result
    }
}

/// 记一次时的快捷开始时间：很多时候是事后补记
enum TimePreset: String, CaseIterable, Identifiable {
    case now, hourAgo, lastNight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: return "刚刚"
        case .hourAgo: return "1 小时前"
        case .lastNight: return "昨晚 10 点"
        }
    }

    var symbol: String {
        switch self {
        case .now: return "clock"
        case .hourAgo: return "clock.arrow.circlepath"
        case .lastNight: return "moon"
        }
    }

    var date: Date {
        let now = Date()
        switch self {
        case .now:
            return now
        case .hourAgo:
            return now.addingTimeInterval(-3600)
        case .lastNight:
            let cal = Calendar.current
            let yesterday = cal.date(byAdding: .day, value: -1, to: now) ?? now
            return cal.date(bySettingHour: 22, minute: 0, second: 0, of: yesterday) ?? yesterday
        }
    }

    /// 选中的时间和这个快捷项相差不到 2 分钟就算选中
    func matches(_ value: Date) -> Bool {
        abs(value.timeIntervalSince(date)) < 120
    }
}
