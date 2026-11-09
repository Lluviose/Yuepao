import SwiftUI
import SwiftData

struct CodexItem: Identifiable {
    let name: String
    var glyph: String?
    var count: Int
    var first: Date?
    var people: [Girl] = []

    var id: String { name }
    var unlocked: Bool { count > 0 }
}

/// 图鉴：体位、玩法、道具、穿着、星座，试过的点亮
struct CodexView: View {
    @Query(sort: \Encounter.date) private var encounters: [Encounter]
    @Query private var girls: [Girl]
    @ObservedObject private var config = ConfigStore.shared

    enum Tab: String, CaseIterable, Identifiable {
        case positions, play, toys, outfits, zodiac
        var id: String { rawValue }
        var title: String {
            switch self {
            case .positions: return "体位"
            case .play: return "玩法"
            case .toys: return "道具"
            case .outfits: return "穿着"
            case .zodiac: return "星座"
            }
        }
    }

    @State private var tab: Tab = .positions

    static let zodiacSigns: [(name: String, glyph: String)] = [
        ("白羊座", "\u{2648}\u{FE0E}"), ("金牛座", "\u{2649}\u{FE0E}"), ("双子座", "\u{264A}\u{FE0E}"),
        ("巨蟹座", "\u{264B}\u{FE0E}"), ("狮子座", "\u{264C}\u{FE0E}"), ("处女座", "\u{264D}\u{FE0E}"),
        ("天秤座", "\u{264E}\u{FE0E}"), ("天蝎座", "\u{264F}\u{FE0E}"), ("射手座", "\u{2650}\u{FE0E}"),
        ("摩羯座", "\u{2651}\u{FE0E}"), ("水瓶座", "\u{2652}\u{FE0E}"), ("双鱼座", "\u{2653}\u{FE0E}")
    ]

    private func optionItems(_ key: OptionKey, values: (EncounterDetails) -> [String]) -> [CodexItem] {
        var counts: [String: Int] = [:]
        var firsts: [String: Date] = [:]
        for e in encounters {
            for v in Set(values(e.details)) where !v.isEmpty {
                counts[v, default: 0] += 1
                if firsts[v] == nil { firsts[v] = e.date }
            }
        }
        let options = config.options(key)
        let extra = counts.keys.filter { !options.contains($0) }.sorted()
        return (options + extra).map { CodexItem(name: $0, count: counts[$0] ?? 0, first: firsts[$0]) }
    }

    private var zodiacItems: [CodexItem] {
        var firstByGirl: [UUID: Date] = [:]
        for e in encounters {
            for g in e.girls where firstByGirl[g.id] == nil {
                firstByGirl[g.id] = e.date
            }
        }
        return Self.zodiacSigns.map { sign in
            let people = girls.filter { g in
                firstByGirl[g.id] != nil && Fmt.zodiac(g.details.birthday) == sign.name
            }
            let first = people.compactMap { firstByGirl[$0.id] }.min()
            return CodexItem(name: sign.name, glyph: sign.glyph, count: people.count, first: first, people: people)
        }
    }

    private var items: [CodexItem] {
        switch tab {
        case .positions: return optionItems(.positions) { $0.positions }
        case .play: return optionItems(.play) { $0.play }
        case .toys: return optionItems(.toys) { $0.toys }
        case .outfits: return optionItems(.outfits) { $0.outfits }
        case .zodiac: return zodiacItems
        }
    }

    var body: some View {
        let list = items
        let unlocked = list.filter(\.unlocked).count
        ScrollView {
            VStack(spacing: 18) {
                Picker("类别", selection: $tab.animation(.snappy)) {
                    ForEach(Tab.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(unlocked)")
                            .font(Typo.display(40, weight: .medium))
                            .contentTransition(.numericText())
                        Text("/ \(list.count) 已解锁")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    ProgressView(value: Double(unlocked), total: Double(max(list.count, 1)))
                        .tint(Palette.gold)
                    Text(hint(unlocked: unlocked, total: list.count))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(list) { item in
                        CodexCard(item: item, countUnit: tab == .zodiac ? "位" : "次")
                    }
                }
            }
            .padding(16)
        }
        .background(Palette.canvas)
        .navigationTitle("图鉴")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hint(unlocked: Int, total: Int) -> String {
        let left = total - unlocked
        switch tab {
        case .zodiac:
            return left == 0 ? "十二星座已经集齐" : "还差 \(left) 个星座，给档案填上生日才会计入"
        case .positions, .play, .toys, .outfits:
            return left == 0 ? "全部解锁，可以在「设置 → 选项管理」里加新的" : "还有 \(left) 个没试过，下次约会试试？"
        }
    }
}

struct CodexCard: View {
    let item: CodexItem
    let countUnit: String

    var body: some View {
        VStack(spacing: 6) {
            if let glyph = item.glyph {
                Text(glyph)
                    .font(.system(size: 30, weight: .light, design: .serif))
                    .foregroundStyle(item.unlocked ? Palette.gold : Color.secondary.opacity(0.35))
                    .frame(height: 36)
            } else {
                Image(systemName: item.unlocked ? "seal.fill" : "lock")
                    .font(.system(size: item.unlocked ? 18 : 14))
                    .foregroundStyle(item.unlocked ? Palette.gold : Color.secondary.opacity(0.4))
                    .frame(height: 24)
            }
            Text(item.name)
                .font(Typo.display(15, weight: item.unlocked ? .semibold : .regular))
                .foregroundStyle(item.unlocked ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if item.unlocked {
                Text("\(item.count) \(countUnit)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.gold)
                if let first = item.first {
                    Text("始于 \(Fmt.shortDate(first))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("未解锁")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(item.unlocked
                      ? AnyShapeStyle(LinearGradient(colors: [Palette.gold.opacity(0.14), Palette.gold.opacity(0.04)],
                                                     startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(Palette.surface))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(item.unlocked ? Palette.gold.opacity(0.45) : Color.secondary.opacity(0.2),
                              style: StrokeStyle(lineWidth: item.unlocked ? 0.8 : 1, dash: item.unlocked ? [] : [3, 3]))
        }
    }
}
