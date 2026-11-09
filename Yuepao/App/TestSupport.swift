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
            d.traits = ["敏感体质", "爱接吻", "喜欢被夸", "事后黏人"]
            d.likedToys = ["跳蛋", "按摩油"]
            d.aftercareNeeds = ["拥抱", "聊天"]
            d.boundaries = "不接受拍照"
            d.gifts = [GiftItem(date: daysAgo(30, hour: 12), item: "香水", amount: 980, occasion: "日常")]
            d.contactGoalDays = 5
        }
        let xue = makeGirl("阿雪", .active, "固定", "上海", 31.2200, 121.5440) { d in
            d.birthday = cal.date(from: DateComponents(year: 1999, month: 3, day: 28))
            d.channel = "Soul"; d.metDate = daysAgo(90, hour: 20); d.ratingOverall = 7; d.intimacy = 60
            d.occupation = "护士"; d.contactGoalDays = 7
            d.height = 168; d.weight = 50; d.cup = "B"; d.bodyType = "苗条"
            d.ratingLooks = 8; d.ratingBody = 9; d.ratingSex = 9; d.ratingPersonality = 7
            d.mbti = "INFP"; d.personality = ["温柔", "独立"]
            d.favoriteFood = "泰餐、甜品"; d.hobbies = "瑜伽、看展"; d.drinks = "冰美式"
            d.awarenessLevel = .suspects
            d.traits = ["恋痛", "M 倾向", "喜欢被支配", "叫声大"]
            d.safeWord = "红灯"
            d.likedPlay = ["束缚", "拍打"]
            d.likedToys = ["眼罩", "绳子", "皮拍"]
            d.aftercareNeeds = ["拥抱", "冷敷 / 涂药", "喝水"]
            d.boundaries = "不留明显痕迹"
        }
        let lily = makeGirl("Lily", .flirting, "", "上海", 31.1955, 121.4370) { d in
            d.channel = "酒吧 / 夜店"; d.metDate = daysAgo(8, hour: 23); d.intimacy = 30
        }
        let yu = makeGirl("小雨", .active, "偶尔", "北京", 39.9087, 116.3975) { d in
            d.birthday = cal.date(from: DateComponents(year: 2000, month: 8, day: 2))
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
        let positionSets: [[String]] = [["传教士", "后入"], ["女上", "传教士"], ["后入", "侧入"], ["女上"]]
        let playSets: [[String]] = [["前戏", "口"], ["接吻"], [], ["共浴", "镜前"]]
        let toySets: [[String]] = [["跳蛋"], [], ["按摩油"], [], ["眼罩"]]
        let outfitSets: [[String]] = [["丝袜"], [], ["情趣内衣"], []]
        let leads = ["我", "她", "", "轮流"]
        for (i, item) in plan.enumerated() {
            let e = Encounter(date: daysAgo(item.2, hour: item.3))
            context.insert(e)
            e.count = 1 + i % 3
            e.durationMinutes = [60, 90, 120][i % 3]
            e.protection = item.4
            e.rating = 3 + i % 3
            e.overnight = i % 4 == 0
            var d = EncounterDetails()
            d.positions = positionSets[i % positionSets.count]
            d.play = playSets[i % playSets.count]
            d.herOrgasms = i % 2 == 0 ? 1 : -1
            d.chemistry = i == 4 ? 5 : 3
            d.toys = toySets[i % toySets.count]
            d.outfits = outfitSets[i % outfitSets.count]
            d.intensity = [2, 3, 1, 2, 3][i % 5]
            d.lead = leads[i % leads.count]
            d.moods = i % 3 == 0 ? ["激情", "尽兴"] : (i % 3 == 1 ? ["温存"] : [])
            d.feedback = i % 3 == 0 ? ["很满足"] : (i % 3 == 1 ? ["还想要"] : [])
            d.aftercare = i % 2 == 0 ? ["拥抱", "清洁"] : []
            d.activities = i % 4 == 0 ? ["吃饭", "喝酒"] : []
            d.initiator = i % 4 == 0 ? "我" : ""
            if i == 7 {
                // 阿雪最近的一次：玩得重一点，事后照顾也记全
                d.positions = ["后入", "趴姿"]
                d.play = ["束缚", "拍打", "语言刺激"]
                d.toys = ["眼罩", "绳子", "皮拍"]
                d.outfits = ["情趣内衣", "吊带袜"]
                d.intensity = 4
                d.lead = "我"
                d.herOrgasms = 2
                d.moods = ["刺激", "尽兴"]
                d.feedback = ["很满足", "有点疼"]
                d.aftercare = ["拥抱", "冷敷 / 涂药", "喝水"]
                d.notes = "她说下次想试试低温蜡烛，力度保持这次就好。"
            }
            d.expenses = [ExpenseItem(category: "酒店", amount: item.1.type == .hotel ? 680 : 0),
                          ExpenseItem(category: "餐饮", amount: 200)]
                .filter { $0.amount > 0 }
            e.details = d
            e.totalCost = d.totalCost
            e.place = item.1
            e.girls = [item.0]
        }
        _ = lily

        // 一次两个人的约会
        let group = Encounter(date: daysAgo(9, hour: 23))
        context.insert(group)
        group.count = 2
        group.protection = .condom
        group.rating = 5
        group.place = hotel
        group.girls = [mei, xue]

        let test = HealthTest(date: daysAgo(12, hour: 10))
        context.insert(test)
        test.items = "HIV、梅毒、淋病、衣原体"
        test.result = "阴性"

        let wishPlan: [(String, String, Girl?, Bool)] = [
            ("海边酒店", "地点", mei, true), ("温泉之夜", "体验", mei, false),
            ("制服", "玩法", xue, false), ("一起旅行", "体验", nil, false), ("跨年夜", "体验", nil, false)
        ]
        for w in wishPlan {
            let item = WishItem(title: w.0)
            context.insert(item)
            item.kind = w.1
            item.girlID = w.2?.id
            item.isDone = w.3
            item.doneAt = w.3 ? daysAgo(18, hour: 22) : nil
        }

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
