import Foundation

/// 档案的详细字段。整体以 JSON 存在 `Girl.detailsData` 里，
/// 新增字段只需要在这里加一个带默认值的属性，旧数据会自动补默认值。
struct GirlDetails: Codable, Equatable {
    // A. 基本信息
    var realName: String = ""
    var birthday: Date?
    var height: Int?
    var weight: Int?
    var cup: String = ""
    var bust: Int?
    var waist: Int?
    var hips: Int?
    var bodyType: String = ""
    var appearance: String = ""
    var mbti: String = ""
    var personality: [String] = []
    var photoIDs: [String] = []

    // B. 社会信息
    var occupation: String = ""
    var education: String = ""
    var school: String = ""
    var hometown: String = ""
    var maritalStatus: String = ""
    var district: String = ""
    var contacts: [ContactItem] = []

    // C. 认识经过
    var channel: String = ""
    var metDate: Date?
    var firstDateDate: Date?
    var introducer: String = ""
    var howWeMet: String = ""

    // D. 后宫属性
    var intimacy: Int = 50
    var ratingLooks: Int = 0
    var ratingBody: Int = 0
    var ratingPersonality: Int = 0
    var ratingSex: Int = 0
    var ratingOverall: Int = 0
    var awareness: String = Awareness.unset.rawValue
    var connections: [Connection] = []
    var contactGoalDays: Int = 0
    var lastContactDate: Date?
    var statusHistory: [StatusChange] = []

    // E. 偏好与雷区
    var favoriteFood: String = ""
    var dislikedFood: String = ""
    var drinks: String = ""
    var hobbies: String = ""
    var giftPrefs: String = ""
    var taboos: String = ""
    var saidNotes: [NoteItem] = []

    // F. 亲密偏好
    /// 特质 / 性癖，比如「恋痛」「敏感体质」
    var traits: [String] = []
    var likedPositions: [String] = []
    var likedPlay: [String] = []
    var likedToys: [String] = []
    var sensitiveSpots: String = ""
    /// 底线 / 明确不接受的
    var boundaries: String = ""
    /// 约定好的安全词：听到就立刻停
    var safeWord: String = ""
    /// 事后她需要的照顾
    var aftercareNeeds: [String] = []
    var contraception: String = ""

    // G. 周期
    /// 旧版本只记开始日期，读取时会自动转成 `periods`
    var periodStarts: [Date] = []
    var periods: [PeriodEntry] = []
    var periodLength: Int = 5

    // H. 重要日期 / 礼物 / 时间线
    var importantDates: [ImportantDate] = []
    var gifts: [GiftItem] = []
    var memos: [NoteItem] = []

    // 其他
    var tags: [String] = []
    var customValues: [String: String] = [:]
    var notes: String = ""

    var awarenessLevel: Awareness {
        get { Awareness(rawValue: awareness) ?? .unset }
        set { awareness = newValue.rawValue }
    }

    var giftSpending: Double { gifts.reduce(0) { $0 + $1.amount } }

    /// 所有经期记录（兼容旧数据），按开始日期升序
    var periodEntries: [PeriodEntry] {
        let list = periods.isEmpty ? periodStarts.map { PeriodEntry(start: $0) } : periods
        return list.sorted { $0.start < $1.start }
    }

    var cycle: CycleInfo { CycleInfo(entries: periodEntries, defaultLength: periodLength) }

    /// 记录一次经期开始（同一天重复点不会重复记）
    mutating func startPeriod(on date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        var list = periodEntries
        if list.contains(where: { Calendar.current.isDate($0.start, inSameDayAs: day) }) { return }
        list.append(PeriodEntry(start: day))
        periods = list.sorted { $0.start < $1.start }
        periodStarts = []
    }

    /// 结束最近一次进行中的经期
    mutating func endPeriod(on date: Date) {
        var list = periodEntries
        guard let i = list.lastIndex(where: { $0.start <= date }) else { return }
        list[i].end = max(Calendar.current.startOfDay(for: date), list[i].start)
        periods = list
        periodStarts = []
    }

    mutating func setPeriods(_ list: [PeriodEntry]) {
        periods = list.sorted { $0.start < $1.start }
        periodStarts = []
    }

    var hasBodyInfo: Bool {
        height != nil || weight != nil || !cup.isEmpty || bust != nil || waist != nil || hips != nil || !bodyType.isEmpty || !appearance.isEmpty
    }

    var hasSocialInfo: Bool {
        !occupation.isEmpty || !education.isEmpty || !school.isEmpty || !hometown.isEmpty || !maritalStatus.isEmpty || !district.isEmpty || !contacts.isEmpty
    }

    var hasMetInfo: Bool {
        !channel.isEmpty || metDate != nil || firstDateDate != nil || !introducer.isEmpty || !howWeMet.isEmpty
    }

    var hasPreferences: Bool {
        !favoriteFood.isEmpty || !dislikedFood.isEmpty || !drinks.isEmpty || !hobbies.isEmpty || !giftPrefs.isEmpty || !taboos.isEmpty
    }

    var hasIntimacy: Bool {
        !traits.isEmpty || !likedPositions.isEmpty || !likedPlay.isEmpty || !likedToys.isEmpty
            || !sensitiveSpots.isEmpty || !boundaries.isEmpty || !safeWord.isEmpty
            || !aftercareNeeds.isEmpty || !contraception.isEmpty
    }
}

struct PeriodEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    /// 最后一天（含），nil 表示没记录结束
    var end: Date?
}

struct ContactItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var type: String = "微信"
    var value: String = ""
}

struct Connection: Codable, Identifiable, Hashable {
    var id = UUID()
    var girlID: UUID?
    var relation: String = ""
}

struct StatusChange: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date = Date()
    var status: String = RelationStatus.flirting.rawValue
}

struct NoteItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date = Date()
    var text: String = ""
}

struct ImportantDate: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String = ""
    var date: Date = Date()
    var remind: Bool = true
}

struct GiftItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date = Date()
    var item: String = ""
    var amount: Double = 0
    var occasion: String = ""
}

/// 约会记录的详细字段
struct EncounterDetails: Codable, Equatable {
    var activities: [String] = []
    var initiator: String = ""
    var positions: [String] = []
    var play: [String] = []
    /// 用到的道具
    var toys: [String] = []
    /// 她穿了什么
    var outfits: [String] = []
    /// 强度 0 = 未记录，1...4 见 `Intensity`
    var intensity: Int = 0
    /// 谁主导：我 / 她 / 轮流
    var lead: String = ""
    /// 她高潮次数，-1 = 未记录
    var herOrgasms: Int = -1
    var chemistry: Int = 0
    var moods: [String] = []
    /// 她事后的反馈
    var feedback: [String] = []
    /// 事后照顾
    var aftercare: [String] = []
    var expenses: [ExpenseItem] = []
    var pillTaken: Bool = false
    var notes: String = ""
    var photoIDs: [String] = []

    var totalCost: Double { expenses.reduce(0) { $0 + $1.amount } }

    /// 体位、玩法、道具、穿着合在一起，列表里当作这次的关键词
    var highlights: [String] { positions + play + toys + outfits }
}

struct ExpenseItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var category: String = "酒店"
    var amount: Double = 0
    var note: String = ""
}

// MARK: - JSON helpers

enum JSONCoding {
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    /// 先严格解码；失败时把已存数据合并到默认值上再解码，
    /// 这样以后给结构体加字段时旧数据不会丢。
    static func decode<T: Codable>(_ type: T.Type, from data: Data, fallback: T) -> T {
        guard !data.isEmpty else { return fallback }
        if let value = try? JSONDecoder().decode(T.self, from: data) { return value }
        guard
            let stored = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let baseData = try? JSONEncoder().encode(fallback),
            var base = (try? JSONSerialization.jsonObject(with: baseData)) as? [String: Any]
        else { return fallback }
        base.merge(stored) { _, new in new }
        guard let merged = try? JSONSerialization.data(withJSONObject: base) else { return fallback }
        return (try? JSONDecoder().decode(T.self, from: merged)) ?? fallback
    }
}
