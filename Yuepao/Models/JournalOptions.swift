import SwiftUI

/// 配色和分组仅用于展示，草稿和备份继续使用原有字符串。
enum JournalOptions {
    struct Group: Identifiable {
        let title: String
        let symbol: String
        let tint: Color
        var words: [String]
        var id: String { title }
    }

    static func groups(for key: OptionKey) -> [Group] {
        switch key {
        case .personality:
            return [
                Group(title: "相处起来", symbol: "leaf", tint: Palette.status,
                      words: ["温柔", "慢热", "大方", "黏人", "细心", "有耐心", "很会倾听"]),
                Group(title: "聊起天来", symbol: "bubble.left.and.bubble.right", tint: Palette.todo,
                      words: ["活泼", "幽默", "知性", "健谈", "直爽", "爱接梗", "脑洞大"]),
                Group(title: "做事风格", symbol: "safari", tint: Palette.gold,
                      words: ["独立", "有主见", "随性", "行动派", "好奇心强", "仪式感"]),
                Group(title: "第一印象", symbol: "sparkles", tint: Palette.gift,
                      words: ["可爱", "高冷", "御姐", "作", "文静", "有反差"])
            ]
        case .activities:
            return [
                Group(title: "吃喝", symbol: "cup.and.saucer", tint: Palette.gold,
                      words: ["吃饭", "喝咖啡", "夜宵", "喝酒", "逛菜市场", "一起做饭", "探面包店"]),
                Group(title: "出门走走", symbol: "figure.walk", tint: Palette.status,
                      words: ["散步", "逛街", "兜风", "旅行", "逛市集", "看日落", "骑行", "野餐"]),
                Group(title: "文化现场", symbol: "ticket", tint: Palette.gift,
                      words: ["看电影", "看展", "听现场", "逛书店", "拍胶片", "看话剧"]),
                Group(title: "一起玩", symbol: "gamecontroller", tint: Palette.todo,
                      words: ["玩桌游", "KTV", "酒吧", "直接见面", "做手工", "拼拼图", "打保龄球"])
            ]
        case .moods:
            return [
                Group(title: "自在", symbol: "sun.max", tint: Palette.gold,
                      words: ["放松", "温存", "安心", "轻快", "舒心"]),
                Group(title: "心动", symbol: "heart", tint: Palette.gift,
                      words: ["浪漫", "激情", "新鲜", "小鹿乱撞", "意犹未尽"]),
                Group(title: "合拍", symbol: "music.note", tint: Palette.status,
                      words: ["默契", "尽兴", "刺激", "笑个不停", "聊得投缘"]),
                Group(title: "有点复杂", symbol: "cloud", tint: Palette.todo,
                      words: ["疲惫", "敷衍", "拘谨", "走神", "五味杂陈"])
            ]
        default: return []
        }
    }

    static func catalog(for key: OptionKey, configured: [String], selected: [String]) -> [Group] {
        var seen = Set<String>()
        let words = (configured + selected).filter { !$0.isEmpty && seen.insert($0).inserted }
        let templates = groups(for: key)
        let known = Set(templates.flatMap(\.words))
        var result = templates.map { template in
            var group = template
            group.words = words.filter(template.words.contains)
            return group
        }
        result.append(Group(title: "自定义", symbol: "tag", tint: Palette.memo,
                            words: words.filter { !known.contains($0) }))
        return result.filter { !$0.words.isEmpty }
    }

    /// 交错展示不同分类，同一轮里每个候选只出现一次。
    static func suggestions(from groups: [Group]) -> [String] {
        let depth = groups.map { $0.words.count }.max() ?? 0
        return (0..<depth).flatMap { index in
            groups.compactMap { $0.words.indices.contains(index) ? $0.words[index] : nil }
        }
    }
}
