import Foundation

/// 档案的详细字段。整体以 JSON 存在 `Girl.detailsData` 里，
/// 新增字段只需要在这里加一个带默认值的属性，旧数据会自动补默认值。
struct GirlDetails: Codable {
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
    var likedPositions: [String] = []
    var likedPlay: [String] = []
    var sensitiveSpots: String = ""
    var boundaries: String = ""
    var contraception: String = ""

    // G. 周期
    var periodStarts: [Date] = []
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

    /// 平均周期（天），数据不足时用 28
    var averageCycle: Int {
        let sorted = periodStarts.sorted()
        guard sorted.count >= 2 else { return 28 }
        var diffs: [Int] = []
        for i in 1..<sorted.count {
            let days = Calendar.current.dateComponents([.day], from: sorted[i - 1], to: sorted[i]).day ?? 0
            if (18...50).contains(days) { diffs.append(days) }
        }
        let recent = diffs.suffix(6)
        guard !recent.isEmpty else { return 28 }
        return Int((Double(recent.reduce(0, +)) / Double(recent.count)).rounded())
    }

    /// 预测下次经期开始日
    var nextPeriod: Date? {
        guard let last = periodStarts.max() else { return nil }
        let cycle = averageCycle
        var next = Calendar.current.date(byAdding: .day, value: cycle, to: last) ?? last
        let today = Calendar.current.startOfDay(for: Date())
        while next < today {
            next = Calendar.current.date(byAdding: .day, value: cycle, to: next) ?? today
        }
        return next
    }

    /// 是否可能处于经期中
    var possiblyOnPeriod: Bool {
        guard let last = periodStarts.max() else { return false }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last), to: Calendar.current.startOfDay(for: Date())).day ?? 99
        return days >= 0 && days < periodLength
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
        !likedPositions.isEmpty || !likedPlay.isEmpty || !sensitiveSpots.isEmpty || !boundaries.isEmpty || !contraception.isEmpty
    }
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
struct EncounterDetails: Codable {
    var activities: [String] = []
    var initiator: String = ""
    var positions: [String] = []
    var play: [String] = []
    /// 她高潮次数，-1 = 未记录
    var herOrgasms: Int = -1
    var chemistry: Int = 0
    var moods: [String] = []
    var expenses: [ExpenseItem] = []
    var pillTaken: Bool = false
    var notes: String = ""
    var photoIDs: [String] = []

    var totalCost: Double { expenses.reduce(0) { $0 + $1.amount } }
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
