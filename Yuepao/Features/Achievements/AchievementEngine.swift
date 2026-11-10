import Foundation
import SwiftUI

// MARK: - 基本类型

enum AchievementTier: Int, CaseIterable {
    case bronze, silver, gold, platinum

    var points: Int {
        switch self {
        case .bronze: return 10
        case .silver: return 25
        case .gold: return 50
        case .platinum: return 100
        }
    }

    var title: String {
        switch self {
        case .bronze: return "铜章"
        case .silver: return "银章"
        case .gold: return "金章"
        case .platinum: return "黑金"
        }
    }
}

enum AchievementCategory: String, CaseIterable, Identifiable {
    case milestone, harem, footprint, rhythm, explore, care

    var id: String { rawValue }

    var title: String {
        switch self {
        case .milestone: return "里程碑"
        case .harem: return "后宫"
        case .footprint: return "足迹"
        case .rhythm: return "节奏"
        case .explore: return "探索"
        case .care: return "体贴"
        }
    }

    var symbol: String {
        switch self {
        case .milestone: return "flag"
        case .harem: return "person.2"
        case .footprint: return "map"
        case .rhythm: return "metronome"
        case .explore: return "sparkle.magnifyingglass"
        case .care: return "hand.raised"
        }
    }
}

struct Measure {
    var current: Int
    var unlockedAt: Date?
}

struct AchievementDef: Identifiable {
    let id: String
    let title: String
    let detail: String
    let category: AchievementCategory
    let tier: AchievementTier
    let symbol: String
    var secret: Bool = false
    var target: Int = 1
    var dynamicTarget: ((AchievementData) -> Int)?
    let measure: (AchievementData) -> Measure
}

struct AchievementResult: Identifiable {
    let def: AchievementDef
    let current: Int
    let target: Int
    let unlocked: Bool
    let unlockedAt: Date?

    var id: String { def.id }
    var progress: Double { min(Double(current) / Double(max(target, 1)), 1) }
    var remaining: Int { max(target - current, 0) }
}

// MARK: - 数据快照

/// 评估成就用的数据，每次刷新只解码一次
struct AchievementData {
    let encounters: [Encounter]
    let encounterDetails: [UUID: EncounterDetails]
    let girls: [Girl]
    let girlDetails: [UUID: GirlDetails]
    let tests: [HealthTest]
    let todos: [TodoItem]
    let wishes: [WishItem]
    let positionOptions: [String]
    let playOptions: [String]
    let weeklyGoal: Int

    /// 每个人第一次的日期
    let firstEncounterByGirl: [UUID: Date]
    /// 每个人所有约会的日期（升序）
    let datesByGirl: [UUID: [Date]]

    init(encounters: [Encounter], girls: [Girl], tests: [HealthTest], todos: [TodoItem], wishes: [WishItem],
         positionOptions: [String], playOptions: [String], weeklyGoal: Int) {
        let sorted = encounters.sorted { $0.date < $1.date }
        self.encounters = sorted
        var details: [UUID: EncounterDetails] = [:]
        var byGirl: [UUID: [Date]] = [:]
        for e in sorted {
            details[e.id] = e.details
            for g in e.girls {
                byGirl[g.id, default: []].append(e.date)
            }
        }
        encounterDetails = details
        datesByGirl = byGirl
        firstEncounterByGirl = byGirl.compactMapValues { $0.first }
        self.girls = girls
        var gd: [UUID: GirlDetails] = [:]
        for g in girls { gd[g.id] = g.details }
        girlDetails = gd
        self.tests = tests.sorted { $0.date < $1.date }
        self.todos = todos
        self.wishes = wishes
        self.positionOptions = positionOptions
        self.playOptions = playOptions
        self.weeklyGoal = max(weeklyGoal, 1)
    }

    func details(_ e: Encounter) -> EncounterDetails {
        encounterDetails[e.id] ?? EncounterDetails()
    }

    /// 满足条件的约会日期（升序）
    func dates(where match: (Encounter, EncounterDetails) -> Bool) -> [Date] {
        encounters.filter { match($0, details($0)) }.map(\.date)
    }

    /// 按时间顺序，每出现一个新的 key 记一次日期
    func newKeyDates(_ keys: (Encounter, EncounterDetails) -> [String]) -> [Date] {
        var seen = Set<String>()
        var result: [Date] = []
        for e in encounters {
            for k in keys(e, details(e)) where !k.isEmpty && !seen.contains(k) {
                seen.insert(k)
                result.append(e.date)
            }
        }
        return result
    }
}

// MARK: - 等级 / 每周目标

struct LevelInfo {
    let level: Int
    let title: String
    let points: Int
    let floor: Int
    let nextThreshold: Int?
    let nextTitle: String?

    var progress: Double {
        guard let next = nextThreshold, next > floor else { return 1 }
        return min(Double(points - floor) / Double(next - floor), 1)
    }
}

struct WeeklyProgress {
    var goal: Int
    var thisWeek: Int
    var streak: Int
    var best: Int

    static let empty = WeeklyProgress(goal: 2, thisWeek: 0, streak: 0, best: 0)

    var remaining: Int { max(goal - thisWeek, 0) }
    var met: Bool { thisWeek >= goal }
    var progress: Double { min(Double(thisWeek) / Double(max(goal, 1)), 1) }
}

/// 和她的羁绊等级
struct BondLevel {
    static let steps: [(count: Int, title: String)] = [
        (0, "初识"), (1, "初尝"), (3, "熟悉"), (8, "亲密"), (15, "默契"), (30, "灵魂伴侣"), (60, "命中注定")
    ]

    let level: Int
    let title: String
    let count: Int
    let nextCount: Int?
    let nextTitle: String?
    let floor: Int

    init(count: Int) {
        self.count = count
        var index = 0
        for (i, step) in Self.steps.enumerated() where count >= step.count {
            index = i
        }
        level = index + 1
        title = Self.steps[index].title
        floor = Self.steps[index].count
        if index + 1 < Self.steps.count {
            nextCount = Self.steps[index + 1].count
            nextTitle = Self.steps[index + 1].title
        } else {
            nextCount = nil
            nextTitle = nil
        }
    }

    var progress: Double {
        guard let next = nextCount, next > floor else { return 1 }
        return min(Double(count - floor) / Double(next - floor), 1)
    }
}

// MARK: - 引擎

enum AchievementEngine {
    static let levels: [(points: Int, title: String)] = [
        (0, "初出茅庐"), (50, "情场新人"), (150, "小有名气"), (300, "风流倜傥"),
        (500, "情场老手"), (800, "万人迷"), (1200, "情圣"), (1800, "传说")
    ]

    static func level(points: Int) -> LevelInfo {
        var index = 0
        for (i, l) in levels.enumerated() where points >= l.points {
            index = i
        }
        let next = index + 1 < levels.count ? levels[index + 1] : nil
        return LevelInfo(level: index + 1, title: levels[index].title, points: points,
                         floor: levels[index].points, nextThreshold: next?.points, nextTitle: next?.title)
    }

    static func evaluate(_ data: AchievementData) -> [AchievementResult] {
        definitions.map { def in
            let target = def.dynamicTarget?(data) ?? def.target
            let m = def.measure(data)
            let unlocked = target > 0 && m.current >= target
            return AchievementResult(def: def, current: m.current, target: target,
                                     unlocked: unlocked, unlockedAt: unlocked ? m.unlockedAt : nil)
        }
    }

    static func weekly(_ dates: [Date], goal rawGoal: Int) -> WeeklyProgress {
        let goal = max(rawGoal, 1)
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = .current
        func weekStart(_ d: Date) -> Date {
            cal.dateInterval(of: .weekOfYear, for: d)?.start ?? cal.startOfDay(for: d)
        }
        func previous(_ w: Date) -> Date {
            cal.date(byAdding: .weekOfYear, value: -1, to: w) ?? w.addingTimeInterval(-7 * 86400)
        }
        var counts: [Date: Int] = [:]
        for d in dates { counts[weekStart(d), default: 0] += 1 }
        let current = weekStart(Date())
        let thisWeek = counts[current] ?? 0

        var streak = 0
        var cursor = thisWeek >= goal ? current : previous(current)
        var guardCount = 0
        while (counts[cursor] ?? 0) >= goal && guardCount < 520 {
            streak += 1
            cursor = previous(cursor)
            guardCount += 1
        }

        var best = 0
        var run = 0
        let weeks = counts.keys.sorted()
        if let first = weeks.first {
            var w = first
            var steps = 0
            while w <= current && steps < 1040 {
                if (counts[w] ?? 0) >= goal {
                    run += 1
                    best = max(best, run)
                } else if w != current {
                    run = 0
                }
                w = cal.date(byAdding: .weekOfYear, value: 1, to: w) ?? w.addingTimeInterval(7 * 86400)
                steps += 1
            }
        }
        return WeeklyProgress(goal: goal, thisWeek: thisWeek, streak: streak, best: max(best, streak))
    }

    // MARK: 工具

    static func nth(_ dates: [Date], _ n: Int) -> Measure {
        let sorted = dates.sorted()
        return Measure(current: sorted.count, unlockedAt: sorted.count >= n && n > 0 ? sorted[n - 1] : nil)
    }

    static func first(_ dates: [Date]) -> Measure {
        Measure(current: dates.isEmpty ? 0 : 1, unlockedAt: dates.min())
    }

    /// 累计值第一次达到 target 的日期
    static func cumulative(_ data: AchievementData, target: Int, value: (Encounter, EncounterDetails) -> Int) -> Measure {
        var sum = 0
        var reached: Date?
        for e in data.encounters {
            sum += value(e, data.details(e))
            if reached == nil && sum >= target { reached = e.date }
        }
        return Measure(current: sum, unlockedAt: reached)
    }

    /// 同一组（月 / 天）里数量达到 n 的最早日期
    static func groupReach(_ dates: [Date], n: Int, by components: Set<Calendar.Component>) -> Measure {
        let cal = Calendar.current
        var groups: [DateComponents: [Date]] = [:]
        for d in dates.sorted() {
            groups[cal.dateComponents(components, from: d), default: []].append(d)
        }
        let best = groups.values.map(\.count).max() ?? 0
        let reached = groups.values.filter { $0.count >= n }.map { $0[n - 1] }.min()
        return Measure(current: best, unlockedAt: reached)
    }

    /// 和同一个人达到 n 次的最早日期
    static func loyal(_ data: AchievementData, n: Int) -> Measure {
        let best = data.datesByGirl.values.map(\.count).max() ?? 0
        let reached = data.datesByGirl.values.filter { $0.count >= n }.map { $0[n - 1] }.min()
        return Measure(current: best, unlockedAt: reached)
    }

    static func partnerDates(_ data: AchievementData) -> [Date] {
        data.firstEncounterByGirl.values.sorted()
    }

    static func zodiacDates(_ data: AchievementData) -> [Date] {
        var seen = Set<String>()
        var result: [Date] = []
        for (girlID, date) in data.firstEncounterByGirl.sorted(by: { $0.value < $1.value }) {
            guard let sign = Fmt.zodiac(data.girlDetails[girlID]?.birthday), !seen.contains(sign) else { continue }
            seen.insert(sign)
            result.append(date)
        }
        return result
    }

    static func cityDates(_ data: AchievementData) -> [Date] {
        data.newKeyDates { e, _ in [e.place?.city.trimmed ?? ""] }
    }

    static func monthDay(_ d: Date) -> (Int, Int) {
        let c = Calendar.current.dateComponents([.month, .day], from: d)
        return (c.month ?? 0, c.day ?? 0)
    }

    static func hour(_ d: Date) -> Int {
        Calendar.current.component(.hour, from: d)
    }

    // MARK: 定义

    static let definitions: [AchievementDef] = makeDefinitions()

    private static func makeDefinitions() -> [AchievementDef] {
        var list: [AchievementDef] = []

        // 里程碑
        let encounterSteps: [(Int, String, String, AchievementTier, String)] = [
            (1, "初试云雨", "记下第一次", .bronze, "heart"),
            (10, "渐入佳境", "累计 10 次", .silver, "flame"),
            (50, "驾轻就熟", "累计 50 次", .gold, "flame.fill"),
            (100, "百战之身", "累计 100 次", .platinum, "crown")
        ]
        for (n, title, detail, tier, symbol) in encounterSteps {
            list.append(AchievementDef(id: "encounters-\(n)", title: title, detail: detail, category: .milestone,
                                       tier: tier, symbol: symbol, target: n) { d in
                nth(d.encounters.map(\.date), n)
            })
        }
        list.append(AchievementDef(id: "rounds-100", title: "金枪不倒", detail: "累计 100 回合", category: .milestone,
                                   tier: .gold, symbol: "bolt", target: 100) { d in
            cumulative(d, target: 100) { e, _ in e.count }
        })
        list.append(AchievementDef(id: "rounds-3", title: "一夜三次", detail: "一次约会 3 回合以上", category: .milestone,
                                   tier: .silver, symbol: "moon.stars") { d in
            first(d.dates { e, _ in e.count >= 3 })
        })
        list.append(AchievementDef(id: "overnight-1", title: "共度良宵", detail: "第一次过夜", category: .milestone,
                                   tier: .bronze, symbol: "moon.zzz") { d in
            first(d.dates { e, _ in e.overnight })
        })
        list.append(AchievementDef(id: "overnight-10", title: "夜夜笙歌", detail: "过夜 10 次", category: .milestone,
                                   tier: .gold, symbol: "sparkles", target: 10) { d in
            nth(d.dates { e, _ in e.overnight }, 10)
        })

        // 后宫
        let partnerSteps: [(Int, String, String, AchievementTier, String)] = [
            (1, "第一位", "拿下第一位", .bronze, "person"),
            (3, "小有收获", "拿下 3 位", .silver, "person.2"),
            (6, "后宫初成", "拿下 6 位", .gold, "person.3"),
            (12, "十二金钗", "拿下 12 位", .platinum, "crown.fill")
        ]
        for (n, title, detail, tier, symbol) in partnerSteps {
            list.append(AchievementDef(id: "partners-\(n)", title: title, detail: detail, category: .harem,
                                       tier: tier, symbol: symbol, target: n) { d in
                nth(partnerDates(d), n)
            })
        }
        list.append(AchievementDef(id: "loyal-10", title: "情有独钟", detail: "和同一个人约满 10 次", category: .harem,
                                   tier: .silver, symbol: "heart.circle", target: 10) { d in loyal(d, n: 10) })
        list.append(AchievementDef(id: "loyal-30", title: "长相厮守", detail: "和同一个人约满 30 次", category: .harem,
                                   tier: .gold, symbol: "infinity", target: 30) { d in loyal(d, n: 30) })
        list.append(AchievementDef(id: "group", title: "左拥右抱", detail: "一次约会有两位以上", category: .harem,
                                   tier: .gold, symbol: "person.2.circle", secret: true) { d in
            first(d.dates { e, _ in e.girls.count >= 2 })
        })
        list.append(AchievementDef(id: "rekindle", title: "旧情复燃", detail: "隔了 90 天以上，再次和她相约", category: .harem,
                                   tier: .silver, symbol: "arrow.uturn.backward.circle", secret: true) { d in
            var hits: [Date] = []
            for dates in d.datesByGirl.values where dates.count >= 2 {
                for i in 1..<dates.count where Fmt.days(from: dates[i - 1], to: dates[i]) >= 90 {
                    hits.append(dates[i])
                }
            }
            return first(hits)
        })
        list.append(AchievementDef(id: "new-month", title: "新鲜感", detail: "一个月内拿下两位新人", category: .harem,
                                   tier: .silver, symbol: "sparkle", target: 2) { d in
            groupReach(partnerDates(d), n: 2, by: [.year, .month])
        })
        list.append(AchievementDef(id: "steady", title: "名花有主", detail: "有一位进入「稳定」关系", category: .harem,
                                   tier: .silver, symbol: "seal") { d in
            var dates: [Date] = []
            var any = false
            for g in d.girls {
                let history = d.girlDetails[g.id]?.statusHistory ?? []
                if let c = history.first(where: { $0.status == RelationStatus.steady.rawValue }) {
                    dates.append(c.date)
                    any = true
                } else if g.status == .steady {
                    any = true
                }
            }
            return Measure(current: any ? 1 : 0, unlockedAt: dates.min())
        })

        // 足迹
        list.append(AchievementDef(id: "hotel", title: "初次开房", detail: "第一次在酒店或民宿", category: .footprint,
                                   tier: .bronze, symbol: "bed.double") { d in
            first(d.dates { e, _ in e.place?.type == .hotel || e.place?.type == .homestay })
        })
        list.append(AchievementDef(id: "her-home", title: "登堂入室", detail: "第一次去她家", category: .footprint,
                                   tier: .bronze, symbol: "house") { d in
            first(d.dates { e, _ in e.place?.type == .herHome })
        })
        list.append(AchievementDef(id: "my-home", title: "主场作战", detail: "第一次带她回家", category: .footprint,
                                   tier: .bronze, symbol: "house.fill") { d in
            first(d.dates { e, _ in e.place?.type == .myHome })
        })
        for (n, title, tier, symbol) in [(5, "四处留情", AchievementTier.silver, "mappin.and.ellipse"),
                                         (15, "四海为家", AchievementTier.gold, "map")] {
            list.append(AchievementDef(id: "places-\(n)", title: title, detail: "在 \(n) 个不同地点留下记录",
                                       category: .footprint, tier: tier, symbol: symbol, target: n) { d in
                nth(d.newKeyDates { e, _ in [e.place?.id.uuidString ?? ""] }, n)
            })
        }
        for (n, title, tier, symbol) in [(2, "异地恋曲", AchievementTier.silver, "building.2"),
                                         (5, "城市猎人", AchievementTier.gold, "globe.asia.australia"),
                                         (10, "环游四方", AchievementTier.platinum, "airplane")] {
            list.append(AchievementDef(id: "cities-\(n)", title: title, detail: "在 \(n) 座城市留下足迹",
                                       category: .footprint, tier: tier, symbol: symbol, target: n) { d in
                nth(cityDates(d), n)
            })
        }

        // 节奏
        for (n, title, tier, symbol) in [(4, "持之以恒", AchievementTier.silver, "calendar.badge.checkmark"),
                                         (12, "雷打不动", AchievementTier.gold, "medal")] {
            list.append(AchievementDef(id: "streak-\(n)", title: title, detail: "连续 \(n) 周达成每周目标",
                                       category: .rhythm, tier: tier, symbol: symbol, target: n) { d in
                let w = weekly(d.encounters.map(\.date), goal: d.weeklyGoal)
                return Measure(current: w.best, unlockedAt: nil)
            })
        }
        list.append(AchievementDef(id: "month-8", title: "火力全开", detail: "一个月 8 次以上", category: .rhythm,
                                   tier: .gold, symbol: "flame.circle", target: 8) { d in
            groupReach(d.encounters.map(\.date), n: 8, by: [.year, .month])
        })
        list.append(AchievementDef(id: "same-day", title: "梅开二度", detail: "同一天两次约会", category: .rhythm,
                                   tier: .silver, symbol: "2.circle", secret: true, target: 2) { d in
            groupReach(d.encounters.map(\.date), n: 2, by: [.year, .month, .day])
        })
        list.append(AchievementDef(id: "morning", title: "晨光", detail: "早上 6 点到 10 点之间", category: .rhythm,
                                   tier: .bronze, symbol: "sunrise", secret: true) { d in
            first(d.dates { e, _ in (6..<10).contains(hour(e.date)) })
        })
        list.append(AchievementDef(id: "late-night", title: "夜猫子", detail: "凌晨 0 点到 4 点之间", category: .rhythm,
                                   tier: .bronze, symbol: "moon", secret: true) { d in
            first(d.dates { e, _ in (0..<4).contains(hour(e.date)) })
        })
        list.append(AchievementDef(id: "valentine", title: "情人节快乐", detail: "2 月 14 日有约", category: .rhythm,
                                   tier: .gold, symbol: "heart.text.square", secret: true) { d in
            first(d.dates { e, _ in monthDay(e.date) == (2, 14) })
        })
        list.append(AchievementDef(id: "new-year", title: "跨年之夜", detail: "12 月 31 日或 1 月 1 日有约", category: .rhythm,
                                   tier: .gold, symbol: "sparkles.rectangle.stack", secret: true) { d in
            first(d.dates { e, _ in
                let md = monthDay(e.date)
                return md == (12, 31) || md == (1, 1)
            })
        })
        list.append(AchievementDef(id: "her-birthday", title: "生日礼物", detail: "在她生日当天相约", category: .rhythm,
                                   tier: .gold, symbol: "gift", secret: true) { d in
            first(d.dates { e, _ in
                let md = monthDay(e.date)
                return e.girls.contains { g in
                    guard let bd = d.girlDetails[g.id]?.birthday else { return false }
                    return monthDay(bd) == md
                }
            })
        })

        // 探索
        list.append(AchievementDef(id: "positions-3", title: "初窥门径", detail: "解锁 3 种体位", category: .explore,
                                   tier: .bronze, symbol: "square.grid.2x2", target: 3) { d in
            nth(d.newKeyDates { _, x in x.positions }, 3)
        })
        list.append(AchievementDef(id: "positions-all", title: "无所不能", detail: "解锁图鉴里的全部体位", category: .explore,
                                   tier: .gold, symbol: "square.grid.3x3.fill",
                                   dynamicTarget: { d in d.positionOptions.count }) { d in
            let options = Set(d.positionOptions)
            let dates = d.newKeyDates { _, x in x.positions.filter { options.contains($0) } }
            return nth(dates, options.count)
        })
        list.append(AchievementDef(id: "play-3", title: "花样百出", detail: "解锁 3 种玩法", category: .explore,
                                   tier: .silver, symbol: "wand.and.stars", target: 3) { d in
            nth(d.newKeyDates { _, x in x.play }, 3)
        })
        list.append(AchievementDef(id: "toys-3", title: "百宝箱", detail: "用过 3 种道具", category: .explore,
                                   tier: .silver, symbol: "wand.and.rays", target: 3) { d in
            nth(d.newKeyDates { _, x in x.toys }, 3)
        })
        list.append(AchievementDef(id: "toys-8", title: "收藏家", detail: "用过 8 种道具", category: .explore,
                                   tier: .gold, symbol: "shippingbox", target: 8) { d in
            nth(d.newKeyDates { _, x in x.toys }, 8)
        })
        list.append(AchievementDef(id: "outfits-3", title: "百变", detail: "解锁 3 种穿着", category: .explore,
                                   tier: .bronze, symbol: "tshirt", target: 3) { d in
            nth(d.newKeyDates { _, x in x.outfits }, 3)
        })
        list.append(AchievementDef(id: "wish-1", title: "心想事成", detail: "实现第一个心愿", category: .explore,
                                   tier: .bronze, symbol: "star") { d in
            nth(d.wishes.filter(\.isDone).map { $0.doneAt ?? $0.createdAt }, 1)
        })
        list.append(AchievementDef(id: "wish-5", title: "梦想成真", detail: "实现 5 个心愿", category: .explore,
                                   tier: .gold, symbol: "star.circle", target: 5) { d in
            nth(d.wishes.filter(\.isDone).map { $0.doneAt ?? $0.createdAt }, 5)
        })
        list.append(AchievementDef(id: "zodiac-6", title: "星座收藏家", detail: "和 6 个不同星座的她有过记录", category: .explore,
                                   tier: .silver, symbol: "circle.hexagongrid", target: 6) { d in
            nth(zodiacDates(d), 6)
        })
        list.append(AchievementDef(id: "zodiac-12", title: "十二星宫", detail: "集齐 12 星座", category: .explore,
                                   tier: .platinum, symbol: "circle.hexagongrid.fill", target: 12) { d in
            nth(zodiacDates(d), 12)
        })

        // 体贴
        list.append(AchievementDef(id: "safe-10", title: "安全第一", detail: "10 次做好防护", category: .care,
                                   tier: .silver, symbol: "checkmark.shield", target: 10) { d in
            nth(d.dates { e, _ in (e.protection == .condom || e.protection == .both) && !e.condomBroke }, 10)
        })
        list.append(AchievementDef(id: "test-1", title: "对自己负责", detail: "做第一次性健康检测", category: .care,
                                   tier: .bronze, symbol: "cross.case") { d in
            nth(d.tests.map(\.date), 1)
        })
        list.append(AchievementDef(id: "test-4", title: "定期体检", detail: "累计 4 次检测", category: .care,
                                   tier: .gold, symbol: "stethoscope", target: 4) { d in
            nth(d.tests.map(\.date), 4)
        })
        list.append(AchievementDef(id: "her-pleasure", title: "以她为先", detail: "10 次让她到达高潮", category: .care,
                                   tier: .gold, symbol: "heart.circle.fill", target: 10) { d in
            nth(d.dates { _, x in x.herOrgasms >= 1 }, 10)
        })
        list.append(AchievementDef(id: "perfect", title: "完美之夜", detail: "满意度和化学反应都是 5 星", category: .care,
                                   tier: .silver, symbol: "star.fill") { d in
            first(d.dates { e, x in e.rating == 5 && x.chemistry == 5 })
        })
        list.append(AchievementDef(id: "aftercare-10", title: "温柔善后", detail: "10 次记下事后照顾", category: .care,
                                   tier: .silver, symbol: "hands.sparkles", target: 10) { d in
            nth(d.dates { _, x in !x.aftercare.isEmpty }, 10)
        })
        list.append(AchievementDef(id: "feedback-10", title: "用心倾听", detail: "10 次记下她的反馈", category: .care,
                                   tier: .silver, symbol: "ear", target: 10) { d in
            nth(d.dates { _, x in !x.feedback.isEmpty }, 10)
        })
        list.append(AchievementDef(id: "safeword", title: "约法三章", detail: "和她约定安全词", category: .care,
                                   tier: .bronze, symbol: "lock.shield") { d in
            let any = d.girlDetails.values.contains { !$0.safeWord.trimmed.isEmpty }
            return Measure(current: any ? 1 : 0, unlockedAt: nil)
        })
        list.append(AchievementDef(id: "gifts-5", title: "礼数周到", detail: "送出 5 份礼物", category: .care,
                                   tier: .silver, symbol: "gift.fill", target: 5) { d in
            nth(d.girlDetails.values.flatMap { $0.gifts.map(\.date) }, 5)
        })
        list.append(AchievementDef(id: "todos-10", title: "说到做到", detail: "完成 10 条待办", category: .care,
                                   tier: .silver, symbol: "checklist", target: 10) { d in
            nth(d.todos.filter(\.isDone).map { $0.doneAt ?? $0.createdAt }, 10)
        })
        list.append(AchievementDef(id: "remember-10", title: "有心人", detail: "记下 10 条「她说过的事」", category: .care,
                                   tier: .silver, symbol: "text.bubble", target: 10) { d in
            nth(d.girlDetails.values.flatMap { $0.saidNotes.map(\.date) }, 10)
        })

        return list
    }
}
