import Foundation
import SwiftUI

/// 可自定义的选项列表
enum OptionKey: String, CaseIterable, Codable, Identifiable {
    case ranks, channels, bodyTypes, cups, personality, traits, maritalStatus, education, contactTypes
    case positions, play, toys, outfits, activities, moods, feedback, aftercare
    case expenseCategories, giftOccasions, tags, todoCategories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ranks: return "位分"
        case .channels: return "认识渠道"
        case .bodyTypes: return "体型"
        case .cups: return "罩杯"
        case .personality: return "性格标签"
        case .traits: return "特质 / 性癖"
        case .maritalStatus: return "感情状况"
        case .education: return "学历"
        case .contactTypes: return "联系方式类型"
        case .positions: return "体位"
        case .play: return "玩法"
        case .toys: return "道具"
        case .outfits: return "穿着"
        case .activities: return "约会内容"
        case .moods: return "心情 / 氛围"
        case .feedback: return "她的反馈"
        case .aftercare: return "事后照顾"
        case .expenseCategories: return "花费类别"
        case .giftOccasions: return "送礼场合"
        case .tags: return "档案标签"
        case .todoCategories: return "待办分类"
        }
    }

    var defaults: [String] {
        switch self {
        case .ranks: return ["女友", "固定", "常约", "偶尔", "一次性"]
        case .channels: return ["探探", "Soul", "Tinder", "陌陌", "小红书", "微信", "酒吧 / 夜店", "朋友介绍", "同事 / 工作", "同学", "其他"]
        case .bodyTypes: return ["骨感", "苗条", "匀称", "微胖", "丰满", "健身"]
        case .cups: return ["A", "B", "C", "D", "E", "F", "G+"]
        case .personality: return ["温柔", "黏人", "活泼", "高冷", "御姐", "可爱", "知性", "独立", "作", "大方"]
        case .traits: return OptionGroups.traits.flatMap(\.items)
        case .maritalStatus: return ["单身", "有男友", "已婚", "离异", "不清楚"]
        case .education: return ["高中", "大专", "本科", "硕士", "博士"]
        case .contactTypes: return ["微信", "电话", "QQ", "Instagram", "小红书", "Telegram", "其他"]
        case .positions: return ["传教士", "女上", "后入", "侧入", "站立", "坐莲", "69", "趴姿", "抱起", "反向女上"]
        case .play: return OptionGroups.play.flatMap(\.items)
        case .toys: return OptionGroups.toys.flatMap(\.items)
        case .outfits: return ["情趣内衣", "丝袜", "吊带袜", "渔网袜", "制服", "旗袍", "白衬衫", "睡裙", "浴袍", "高跟鞋", "猫耳"]
        case .activities: return ["吃饭", "喝酒", "夜宵", "看电影", "逛街", "散步", "看展", "KTV", "酒吧", "兜风", "旅行", "直接见面"]
        case .moods: return ["激情", "温存", "浪漫", "刺激", "默契", "放松", "新鲜", "尽兴", "敷衍", "疲惫"]
        case .feedback: return ["很满足", "还想要", "刚刚好", "有点累", "有点疼", "叫停过"]
        case .aftercare: return ["拥抱", "清洁", "喝水", "吃点东西", "按摩", "聊天", "冷敷 / 涂药", "一起睡"]
        case .expenseCategories: return ["酒店", "餐饮", "礼物", "交通", "娱乐", "红包", "其他"]
        case .giftOccasions: return ["生日", "情人节", "520", "七夕", "圣诞", "纪念日", "日常", "红包", "转账"]
        case .tags: return []
        case .todoCategories: return ["约会", "礼物", "联系", "健康", "其他"]
        }
    }
}

enum CustomFieldKind: String, Codable, CaseIterable, Identifiable {
    case text, number, rating, choice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "文本"
        case .number: return "数字"
        case .rating: return "评分 1-10"
        case .choice: return "单选"
        }
    }
}

struct CustomFieldDef: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var kind: CustomFieldKind = .text
    var options: [String] = []
}

struct AppConfig: Codable {
    var options: [String: [String]] = [:]
    var customFields: [CustomFieldDef] = []
}

@MainActor
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    private static let storageKey = "appConfig"

    @Published var config: AppConfig {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            config = JSONCoding.decode(AppConfig.self, from: data, fallback: AppConfig())
        } else {
            config = AppConfig()
        }
    }

    private func save() {
        UserDefaults.standard.set(JSONCoding.encode(config), forKey: Self.storageKey)
    }

    func options(_ key: OptionKey) -> [String] {
        config.options[key.rawValue] ?? key.defaults
    }

    func setOptions(_ values: [String], for key: OptionKey) {
        config.options[key.rawValue] = values
    }

    func addOption(_ value: String, to key: OptionKey) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        var list = options(key)
        guard !list.contains(v) else { return }
        list.append(v)
        setOptions(list, for: key)
    }

    func rankIndex(_ rank: String) -> Int {
        options(.ranks).firstIndex(of: rank) ?? Int.max
    }
}
