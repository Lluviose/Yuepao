import SwiftUI
import SwiftData

/// 年度回顾里的一页
enum ReviewCard {
    case cover(year: Int)
    case total(count: Int, rounds: Int, overnights: Int)
    case people(count: Int, newCount: Int, girls: [Girl])
    case favorite(girl: Girl, count: Int, rounds: Int)
    case places(top: String, topCount: Int, cities: [String])
    case rhythm(month: Int, monthCount: Int, monthly: [Int], dayPart: String)
    case explore(positions: Int, topPosition: String?, avgRating: Double?)
    case achievements(count: Int, medals: [AchievementResult])
    case ending(year: Int, count: Int)
    case empty(year: Int)
}

struct YearReview {
    let cards: [ReviewCard]

    init(year: Int, encounters all: [Encounter], achievements: [AchievementResult], unlockDate: (AchievementResult) -> Date?) {
        let cal = Calendar.current
        let encounters = all.filter { cal.component(.year, from: $0.date) == year }.sorted { $0.date < $1.date }
        guard !encounters.isEmpty else {
            cards = [.cover(year: year), .empty(year: year)]
            return
        }
        var cards: [ReviewCard] = [.cover(year: year)]

        let rounds = encounters.reduce(0) { $0 + $1.count }
        cards.append(.total(count: encounters.count, rounds: rounds, overnights: encounters.filter(\.overnight).count))

        // 人
        var countByGirl: [UUID: Int] = [:]
        var roundsByGirl: [UUID: Int] = [:]
        var girlByID: [UUID: Girl] = [:]
        for e in encounters {
            for g in e.girls {
                countByGirl[g.id, default: 0] += 1
                roundsByGirl[g.id, default: 0] += e.count
                girlByID[g.id] = g
            }
        }
        var firstEver: [UUID: Date] = [:]
        for e in all.sorted(by: { $0.date < $1.date }) {
            for g in e.girls where firstEver[g.id] == nil { firstEver[g.id] = e.date }
        }
        let newCount = girlByID.keys.filter { id in
            firstEver[id].map { cal.component(.year, from: $0) == year } ?? false
        }.count
        let ranked = countByGirl.sorted { $0.value > $1.value }
        cards.append(.people(count: girlByID.count, newCount: newCount,
                             girls: ranked.prefix(6).compactMap { girlByID[$0.key] }))
        if let top = ranked.first, let girl = girlByID[top.key] {
            cards.append(.favorite(girl: girl, count: top.value, rounds: roundsByGirl[top.key] ?? 0))
        }

        // 地点
        var placeCount: [String: Int] = [:]
        var cities: [String] = []
        for e in encounters {
            if let p = e.place {
                placeCount[p.displayName, default: 0] += 1
                let city = p.city.trimmed
                if !city.isEmpty && !cities.contains(city) { cities.append(city) }
            }
        }
        if let topPlace = placeCount.max(by: { $0.value < $1.value }) {
            cards.append(.places(top: topPlace.key, topCount: topPlace.value, cities: cities))
        }

        // 节奏
        var monthly = Array(repeating: 0, count: 12)
        var parts = Array(repeating: 0, count: 6)
        for e in encounters {
            monthly[cal.component(.month, from: e.date) - 1] += 1
            let h = cal.component(.hour, from: e.date)
            let index: Int
            switch h {
            case 0..<6: index = 0
            case 6..<12: index = 1
            case 12..<17: index = 2
            case 17..<19: index = 3
            case 19..<23: index = 4
            default: index = 5
            }
            parts[index] += 1
        }
        let partNames = ["凌晨", "上午", "下午", "傍晚", "晚上", "深夜"]
        let bestMonth = monthly.indices.max { monthly[$0] < monthly[$1] } ?? 0
        let bestPart = parts.indices.max { parts[$0] < parts[$1] } ?? 4
        cards.append(.rhythm(month: bestMonth + 1, monthCount: monthly[bestMonth], monthly: monthly, dayPart: partNames[bestPart]))

        // 探索
        var positionCount: [String: Int] = [:]
        for e in encounters {
            for p in Set(e.details.positions) { positionCount[p, default: 0] += 1 }
        }
        let rated = encounters.filter { $0.rating > 0 }
        let avg = rated.isEmpty ? nil : Double(rated.reduce(0) { $0 + $1.rating }) / Double(rated.count)
        cards.append(.explore(positions: positionCount.count,
                              topPosition: positionCount.max(by: { $0.value < $1.value })?.key,
                              avgRating: avg))

        // 成就
        let unlockedThisYear = achievements.filter { r in
            guard let d = unlockDate(r) else { return false }
            return cal.component(.year, from: d) == year
        }
        if !unlockedThisYear.isEmpty {
            cards.append(.achievements(count: unlockedThisYear.count,
                                       medals: Array(unlockedThisYear.sorted { $0.def.tier.rawValue > $1.def.tier.rawValue }.prefix(6))))
        }

        cards.append(.ending(year: year, count: encounters.count))
        self.cards = cards
    }
}

// MARK: - 页面

struct YearReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Encounter.date) private var encounters: [Encounter]
    @ObservedObject private var center = AchievementCenter.shared

    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var page = 0

    private var years: [Int] {
        let cal = Calendar.current
        var set = Set(encounters.map { cal.component(.year, from: $0.date) })
        set.insert(cal.component(.year, from: Date()))
        return set.sorted(by: >)
    }

    var body: some View {
        let review = YearReview(year: year, encounters: encounters, achievements: center.results) { center.unlockDate($0) }
        ZStack(alignment: .top) {
            TabView(selection: $page) {
                ForEach(Array(review.cards.enumerated()), id: \.offset) { index, card in
                    ReviewCardView(card: card, index: index, active: page == index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .ignoresSafeArea()
            .id(year)

            HStack {
                Menu {
                    ForEach(years, id: \.self) { y in
                        Button("\(String(y)) 年") {
                            year = y
                            page = 0
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(String(year)) 年")
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityIdentifier("closeReview")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}

/// 数字从 0 滚到目标值
struct CountUpText: View {
    let value: Int
    let active: Bool
    var font: Font = Typo.display(96, weight: .medium)

    @State private var shown = 0

    var body: some View {
        Text("\(shown)")
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear { animate() }
            .onChange(of: active) { _, _ in animate() }
    }

    private func animate() {
        guard active else { return }
        shown = 0
        withAnimation(.smooth(duration: 1.3).delay(0.15)) { shown = value }
    }
}

struct ReviewCardView: View {
    let card: ReviewCard
    let index: Int
    let active: Bool

    private static let backgrounds: [[Color]] = [
        [Color(red: 0.40, green: 0.11, blue: 0.19), Color(red: 0.12, green: 0.03, blue: 0.06)],
        [Color(red: 0.25, green: 0.13, blue: 0.27), Color(red: 0.07, green: 0.04, blue: 0.09)],
        [Color(red: 0.20, green: 0.20, blue: 0.23), Color(red: 0.05, green: 0.05, blue: 0.06)],
        [Color(red: 0.12, green: 0.17, blue: 0.29), Color(red: 0.03, green: 0.05, blue: 0.10)],
        [Color(red: 0.30, green: 0.21, blue: 0.10), Color(red: 0.08, green: 0.05, blue: 0.02)]
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: Self.backgrounds[index % Self.backgrounds.count], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.12), .clear], center: UnitPoint(x: 0.3, y: 0.15),
                           startRadius: 0, endRadius: 420)
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Palette.gold.opacity(0.25), lineWidth: 0.8)
                .padding(18)
            content
                .padding(.horizontal, 40)
                .opacity(active ? 1 : 0.3)
                .offset(y: active ? 0 : 16)
                .animation(.smooth(duration: 0.6), value: active)
        }
        .foregroundStyle(.white)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch card {
        case .cover(let year):
            VStack(spacing: 14) {
                Text("年度回顾").eyebrow()
                Text(String(year))
                    .font(Typo.display(88, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [Palette.gold, Color.white], startPoint: .top, endPoint: .bottom))
                Text("这一年的故事，翻开看看")
                    .font(Typo.display(18, weight: .regular))
                    .opacity(0.8)
                Label("向左滑动", systemImage: "hand.draw")
                    .font(.footnote)
                    .opacity(0.5)
                    .padding(.top, 30)
            }
        case .total(let count, let rounds, let overnights):
            VStack(spacing: 10) {
                Text("这一年，你们见了").font(Typo.display(20, weight: .regular)).opacity(0.85)
                CountUpText(value: count, active: active)
                    .foregroundStyle(Palette.gold)
                Text("次").font(Typo.display(22))
                Text("共 \(rounds) 回合 · \(overnights) 次过夜")
                    .font(.subheadline)
                    .opacity(0.65)
                    .padding(.top, 8)
            }
        case .people(let count, let newCount, let girls):
            VStack(spacing: 14) {
                Text("这一年出现过").font(Typo.display(20, weight: .regular)).opacity(0.85)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountUpText(value: count, active: active, font: Typo.display(84, weight: .medium))
                        .foregroundStyle(Palette.gold)
                    Text("位佳人").font(Typo.display(22))
                }
                HStack(spacing: -14) {
                    ForEach(girls) { g in
                        AvatarView(photoID: g.avatarID, name: g.name, size: 54)
                            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 2))
                    }
                }
                .padding(.vertical, 6)
                Text(newCount > 0 ? "其中 \(newCount) 位是今年新认识的" : "都是老相识")
                    .font(.subheadline)
                    .opacity(0.65)
            }
        case .favorite(let girl, let count, let rounds):
            VStack(spacing: 16) {
                Text("见得最多的是").font(Typo.display(20, weight: .regular)).opacity(0.85)
                AvatarView(photoID: girl.avatarID, name: girl.name, size: 120)
                    .overlay(Circle().stroke(Palette.gold.opacity(0.8), lineWidth: 2))
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                Text(girl.name).font(Typo.display(40, weight: .semibold))
                Text("\(count) 次 · \(rounds) 回合")
                    .font(.subheadline)
                    .foregroundStyle(Palette.gold)
                Text(BondLevel(count: girl.encounters.count).title)
                    .font(.footnote)
                    .opacity(0.6)
            }
        case .places(let top, let topCount, let cities):
            VStack(spacing: 14) {
                Text("最常去的地方").font(Typo.display(20, weight: .regular)).opacity(0.85)
                Text(top)
                    .font(Typo.display(40, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text("去了 \(topCount) 次").font(.subheadline).foregroundStyle(Palette.gold)
                if !cities.isEmpty {
                    Divider().overlay(Color.white.opacity(0.2)).frame(width: 80).padding(.vertical, 8)
                    Text("足迹遍布 \(cities.count) 座城市").font(Typo.display(18, weight: .regular))
                    Text(cities.prefix(6).joined(separator: " · "))
                        .font(.footnote)
                        .opacity(0.6)
                        .multilineTextAlignment(.center)
                }
            }
        case .rhythm(let month, let monthCount, let monthly, let dayPart):
            VStack(spacing: 16) {
                Text("最热烈的月份").font(Typo.display(20, weight: .regular)).opacity(0.85)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(month)").font(Typo.display(84, weight: .medium)).foregroundStyle(Palette.gold)
                    Text("月").font(Typo.display(24))
                }
                Text("那个月见了 \(monthCount) 次").font(.subheadline).opacity(0.7)
                MonthBars(values: monthly, highlight: month - 1, active: active)
                    .frame(height: 90)
                    .padding(.top, 6)
                Text("你们最常在「\(dayPart)」相见")
                    .font(Typo.display(17, weight: .regular))
                    .opacity(0.8)
                    .padding(.top, 4)
            }
        case .explore(let positions, let topPosition, let avgRating):
            VStack(spacing: 14) {
                Text("这一年解锁了").font(Typo.display(20, weight: .regular)).opacity(0.85)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountUpText(value: positions, active: active, font: Typo.display(84, weight: .medium))
                        .foregroundStyle(Palette.gold)
                    Text("种体位").font(Typo.display(22))
                }
                if let topPosition {
                    Text("最爱「\(topPosition)」").font(.subheadline).opacity(0.7)
                }
                if let avgRating {
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: Double(i) <= avgRating + 0.25 ? "star.fill" : "star")
                                .foregroundStyle(Palette.gold)
                        }
                    }
                    .padding(.top, 10)
                    Text(String(format: "平均满意度 %.1f", avgRating))
                        .font(.footnote)
                        .opacity(0.6)
                }
            }
        case .achievements(let count, let medals):
            VStack(spacing: 18) {
                Text("这一年收获了").font(Typo.display(20, weight: .regular)).opacity(0.85)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountUpText(value: count, active: active, font: Typo.display(84, weight: .medium))
                        .foregroundStyle(Palette.gold)
                    Text("枚奖章").font(Typo.display(22))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                    ForEach(medals) { r in
                        VStack(spacing: 6) {
                            MedalView(symbol: r.def.symbol, tier: r.def.tier, unlocked: true, size: 58, shine: active)
                            Text(r.def.title).font(.caption2).opacity(0.75).lineLimit(1)
                        }
                    }
                }
                .padding(.top, 6)
            }
        case .ending(let year, let count):
            VStack(spacing: 16) {
                Image(systemName: "book.closed")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Palette.gold)
                Text("\(String(year)) 年，\(count) 次心动")
                    .font(Typo.display(26, weight: .medium))
                    .multilineTextAlignment(.center)
                Text("下一页，继续书写。")
                    .font(Typo.display(18, weight: .regular))
                    .opacity(0.7)
            }
        case .empty(let year):
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Palette.gold)
                Text("\(String(year)) 年还没有记录")
                    .font(Typo.display(24, weight: .medium))
                Text("去写下第一页吧")
                    .font(.subheadline)
                    .opacity(0.6)
            }
        }
    }
}

private struct MonthBars: View {
    let values: [Int]
    let highlight: Int
    let active: Bool

    var body: some View {
        let maxValue = max(values.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, v in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(index == highlight ? AnyShapeStyle(Palette.gold) : AnyShapeStyle(Color.white.opacity(0.25)))
                        .frame(width: 10, height: active ? max(4, CGFloat(v) / CGFloat(maxValue) * 70) : 4)
                        .animation(.spring(duration: 0.8, bounce: 0.25).delay(Double(index) * 0.03), value: active)
                    Text("\(index + 1)")
                        .font(.system(size: 8))
                        .opacity(0.45)
                }
            }
        }
    }
}
