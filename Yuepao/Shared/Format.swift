import Foundation
import CoreLocation

enum Fmt {
    static let locale = Locale(identifier: "zh_CN")

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "M月d日"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()

    private static let rowFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "M月d日 EEE HH:mm"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "yyyy年M月"
        return f
    }()

    static func date(_ d: Date) -> String { dateFormatter.string(from: d) }
    static func shortDate(_ d: Date) -> String { shortDateFormatter.string(from: d) }
    static func dateTime(_ d: Date) -> String { dateTimeFormatter.string(from: d) }
    static func row(_ d: Date) -> String { rowFormatter.string(from: d) }
    static func month(_ d: Date) -> String { monthFormatter.string(from: d) }

    static func days(from: Date, to: Date = Date()) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: from), to: cal.startOfDay(for: to)).day ?? 0
    }

    static func daysAgo(_ d: Date?) -> String {
        guard let d else { return "从未" }
        let n = days(from: d)
        switch n {
        case ..<0: return "\(-n) 天后"
        case 0: return "今天"
        case 1: return "昨天"
        default: return "\(n) 天前"
        }
    }

    static func money(_ v: Double) -> String {
        if v == 0 { return "¥0" }
        if v == v.rounded() { return "¥\(Int(v))" }
        return String(format: "¥%.2f", v)
    }

    /// 文件大小：3.1 MB
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// 视频时长：0:07、12:34、1:02:03
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = total % 3600 / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func age(_ birthday: Date?) -> Int? {
        guard let birthday else { return nil }
        return Calendar.current.dateComponents([.year], from: birthday, to: Date()).year
    }

    static func zodiac(_ birthday: Date?) -> String? {
        guard let birthday else { return nil }
        let c = Calendar.current.dateComponents([.month, .day], from: birthday)
        guard let m = c.month, let d = c.day else { return nil }
        // 每个月从 startDay 开始进入的星座
        let table: [(startDay: Int, sign: String)] = [
            (20, "水瓶座"), (19, "双鱼座"), (21, "白羊座"), (20, "金牛座"),
            (21, "双子座"), (22, "巨蟹座"), (23, "狮子座"), (23, "处女座"),
            (23, "天秤座"), (24, "天蝎座"), (23, "射手座"), (22, "摩羯座")
        ]
        let entry = table[m - 1]
        if d >= entry.startDay { return entry.sign }
        return table[(m + 10) % 12].sign
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}
