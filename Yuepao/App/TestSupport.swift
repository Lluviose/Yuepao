import Foundation
import SwiftData

/// 只给自动化 UI 测试用：内存数据库、不上锁、可选填充演示数据。
enum TestSupport {
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uiTesting") }
    static var seedDemo: Bool { ProcessInfo.processInfo.arguments.contains("-seedDemo") }

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        #if DEBUG
        guard isUITesting, seedDemo else { return }
        let cal = Calendar.current
        func daysAgo(_ n: Int, hour: Int) -> Date {
            let d = cal.date(byAdding: .day, value: -n, to: Date()) ?? Date()
            return cal.date(bySettingHour: hour, minute: 30, second: 0, of: d) ?? d
        }

        func makeGirl(_ name: String, _ status: RelationStatus, _ rank: String, _ city: String,
                      _ lat: Double, _ lon: Double, configure: (inout GirlDetails) -> Void) -> Girl {
            let g = Girl(name: name)
            context.insert(g)
            g.status = status
            g.rank = rank
            g.city = city
            g.latitude = lat
            g.longitude = lon
            var d = GirlDetails()
            configure(&d)
            d.statusHistory = [StatusChange(date: daysAgo(150, hour: 12), status: status.rawValue)]
            g.details = d
            return g
        }

        let mei = makeGirl("小美", .steady, "女友", "上海", 31.2330, 121.4750) { d in
            d.birthday = cal.date(byAdding: .day, value: 12, to: cal.date(byAdding: .year, value: -24, to: Date()) ?? Date())
            d.height = 165; d.weight = 48; d.cup = "C"; d.bodyType = "匀称"
            d.occupation = "设计师"; d.channel = "探探"; d.metDate = daysAgo(200, hour: 20)
            d.personality = ["温柔", "黏人"]; d.ratingLooks = 8; d.ratingOverall = 9; d.intimacy = 85
            d.favoriteFood = "日料、火锅"; d.taboos = "不要提她前任"
            d.saidNotes = [NoteItem(date: daysAgo(10, hour: 21), text: "下个月要去成都出差一周")]
            d.periods = [
                PeriodEntry(start: cal.startOfDay(for: daysAgo(80, hour: 0)), end: cal.startOfDay(for: daysAgo(76, hour: 0))),
                PeriodEntry(start: cal.startOfDay(for: daysAgo(51, hour: 0)), end: cal.startOfDay(for: daysAgo(47, hour: 0))),
                PeriodEntry(start: cal.startOfDay(for: daysAgo(22, hour: 0)), end: cal.startOfDay(for: daysAgo(17, hour: 0)))
            ]
            d.memos = [NoteItem(date: daysAgo(3, hour: 22), text: "一起看了电影，她很喜欢那家日料"),
                       NoteItem(date: daysAgo(40, hour: 21), text: "第一次去她家，养了一只橘猫")]
            d.importantDates = [ImportantDate(title: "在一起纪念日", date: daysAgo(170, hour: 12), remind: true)]
            d.likedPositions = ["女上", "后入"]
            d.gifts = [GiftItem(date: daysAgo(30, hour: 12), item: "香水", amount: 980, occasion: "日常")]
            d.contactGoalDays = 5
        }
        let xue = makeGirl("阿雪", .active, "固定", "上海", 31.2200, 121.5440) { d in
            d.channel = "Soul"; d.metDate = daysAgo(90, hour: 20); d.ratingOverall = 7; d.intimacy = 60
            d.occupation = "护士"; d.contactGoalDays = 7
        }
        let lily = makeGirl("Lily", .flirting, "", "上海", 31.1955, 121.4370) { d in
            d.channel = "酒吧 / 夜店"; d.metDate = daysAgo(8, hour: 23); d.intimacy = 30
        }
        let yu = makeGirl("小雨", .active, "偶尔", "北京", 39.9087, 116.3975) { d in
            d.channel = "朋友介绍"; d.ratingOverall = 8; d.intimacy = 55
        }

        func makePlace(_ name: String, _ type: PlaceType, _ city: String, _ district: String, _ lat: Double, _ lon: Double) -> Place {
            let p = Place(name: name)
            context.insert(p)
            p.type = type
            p.city = city
            p.district = district
            p.latitude = lat
            p.longitude = lon
            return p
        }

        let hotel = makePlace("静安某酒店", .hotel, "上海", "静安区", 31.2286, 121.4480)
        let herHome = makePlace("小美家", .herHome, "上海", "黄浦区", 31.2335, 121.4762)
        let myHome = makePlace("我家", .myHome, "上海", "徐汇区", 31.2050, 121.4500)
        let bjHotel = makePlace("国贸某酒店", .hotel, "北京", "朝阳区", 39.9087, 116.4600)

        let plan: [(Girl, Place, Int, Int, Protection)] = [
            (mei, herHome, 2, 22, .condom), (mei, herHome, 6, 23, .pill), (mei, myHome, 11, 21, .condom),
            (mei, hotel, 18, 15, .both), (mei, herHome, 25, 22, .condom), (mei, myHome, 40, 23, .condom),
            (mei, hotel, 70, 20, .condom), (xue, hotel, 4, 14, .condom), (xue, myHome, 15, 22, .withdrawal),
            (xue, hotel, 33, 19, .condom), (xue, hotel, 60, 21, .condom), (yu, bjHotel, 20, 23, .condom),
            (yu, bjHotel, 95, 22, .condom), (mei, hotel, 120, 21, .condom)
        ]
        for (i, item) in plan.enumerated() {
            let e = Encounter(date: daysAgo(item.2, hour: item.3))
            context.insert(e)
            e.count = 1 + i % 3
            e.durationMinutes = [60, 90, 120][i % 3]
            e.protection = item.4
            e.rating = 3 + i % 3
            var d = EncounterDetails()
            d.positions = ["传教士", "后入"]
            d.expenses = [ExpenseItem(category: "酒店", amount: item.1.type == .hotel ? 680 : 0),
                          ExpenseItem(category: "餐饮", amount: 200)]
                .filter { $0.amount > 0 }
            e.details = d
            e.totalCost = d.totalCost
            e.place = item.1
            e.girls = [item.0]
        }
        _ = lily

        let todoPlan: [(String, Int?, Girl?, Bool)] = [
            ("给小美准备生日礼物", 10, mei, false),
            ("订周五晚上的餐厅", 0, xue, false),
            ("回 Lily 消息", -1, lily, false),
            ("去做一次检测", 5, nil, false),
            ("买她喜欢的香水", nil, mei, false),
            ("订酒店", -4, xue, true)
        ]
        for item in todoPlan {
            let t = TodoItem(title: item.0)
            context.insert(t)
            t.dueDate = item.1.map { cal.startOfDay(for: cal.date(byAdding: .day, value: $0, to: Date()) ?? Date()) }
            t.girlID = item.2?.id
            t.isDone = item.3
            t.doneAt = item.3 ? daysAgo(4, hour: 18) : nil
        }
        try? context.save()
        #endif
    }
}
