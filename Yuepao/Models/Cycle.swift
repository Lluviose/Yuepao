import Foundation
import SwiftUI

/// 某一天在周期里的状态
enum CycleDayKind: Equatable {
    case none
    case period(predicted: Bool)
    case fertile
    case ovulation

    var isPeriod: Bool {
        if case .period = self { return true }
        return false
    }
}

enum CyclePhase {
    case period, follicular, fertile, ovulation, luteal

    var title: String {
        switch self {
        case .period: return "经期"
        case .follicular: return "卵泡期"
        case .fertile: return "易孕期"
        case .ovulation: return "排卵日"
        case .luteal: return "黄体期"
        }
    }

    var color: Color {
        switch self {
        case .period: return Palette.period
        case .follicular: return .teal
        case .fertile, .ovulation: return Palette.fertile
        case .luteal: return .indigo
        }
    }
}

/// 根据经期记录推算周期、预测下次经期和易孕期。
/// 日历法只是参考，不能当避孕手段。
struct CycleInfo {
    let entries: [PeriodEntry]
    let averageCycle: Int
    let averagePeriodLength: Int

    private let cal = Calendar.current

    init(entries: [PeriodEntry], defaultLength: Int) {
        let sorted = entries.sorted { $0.start < $1.start }
        self.entries = sorted
        let cal = Calendar.current

        var gaps: [Int] = []
        if sorted.count >= 2 {
            for i in 1..<sorted.count {
                let d = cal.dateComponents([.day], from: cal.startOfDay(for: sorted[i - 1].start),
                                           to: cal.startOfDay(for: sorted[i].start)).day ?? 0
                if (18...50).contains(d) { gaps.append(d) }
            }
        }
        let recentGaps = gaps.suffix(6)
        averageCycle = recentGaps.isEmpty ? 28 : Int((Double(recentGaps.reduce(0, +)) / Double(recentGaps.count)).rounded())

        let lengths: [Int] = sorted.compactMap { e in
            guard let end = e.end else { return nil }
            let d = (cal.dateComponents([.day], from: cal.startOfDay(for: e.start), to: cal.startOfDay(for: end)).day ?? 0) + 1
            return (1...12).contains(d) ? d : nil
        }
        let recentLengths = lengths.suffix(6)
        averagePeriodLength = recentLengths.isEmpty
            ? max(2, min(defaultLength, 10))
            : Int((Double(recentLengths.reduce(0, +)) / Double(recentLengths.count)).rounded())
    }

    var hasData: Bool { !entries.isEmpty }

    var lastStart: Date? { entries.last.map { cal.startOfDay(for: $0.start) } }

    private func days(_ from: Date, _ to: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: from), to: cal.startOfDay(for: to)).day ?? 0
    }

    private func add(_ n: Int, to date: Date) -> Date {
        cal.date(byAdding: .day, value: n, to: date) ?? date
    }

    /// 这次经期是否还没结束（开始了、没记结束、且没超过平均天数太多）
    var isOngoing: Bool {
        guard let last = entries.last, last.end == nil else { return false }
        let n = days(last.start, Date())
        return n >= 0 && n < averagePeriodLength + 2
    }

    /// 包含 date 的那一个周期：开始日、周期长度、是否是预测出来的
    private func cycleContaining(_ date: Date) -> (start: Date, length: Int, periodLength: Int, predicted: Bool)? {
        guard let first = entries.first else { return nil }
        let day = cal.startOfDay(for: date)
        guard day >= cal.startOfDay(for: first.start) else { return nil }

        if let index = entries.lastIndex(where: { cal.startOfDay(for: $0.start) <= day }) {
            let entry = entries[index]
            let start = cal.startOfDay(for: entry.start)
            let periodLen: Int = entry.end.map { days(entry.start, $0) + 1 } ?? averagePeriodLength
            if index + 1 < entries.count {
                // 历史周期：用实际长度
                let length = days(start, entries[index + 1].start)
                return (start, max(length, 1), periodLen, false)
            }
            // 最后一次记录之后：按平均周期往后推
            let offset = days(start, day)
            let k = offset / averageCycle
            if k == 0 {
                return (start, averageCycle, periodLen, false)
            }
            return (add(k * averageCycle, to: start), averageCycle, averagePeriodLength, true)
        }
        return nil
    }

    /// 某天在周期中的第几天（从 1 开始）
    func dayOfCycle(on date: Date) -> Int? {
        guard let c = cycleContaining(date) else { return nil }
        return days(c.start, date) + 1
    }

    func kind(on date: Date) -> CycleDayKind {
        guard let c = cycleContaining(date) else { return .none }
        let n = days(c.start, date) + 1
        if n <= c.periodLength { return .period(predicted: c.predicted) }
        let ovulationDay = c.length - 13
        guard ovulationDay > c.periodLength else { return .none }
        if n == ovulationDay { return .ovulation }
        if n >= ovulationDay - 5 && n <= ovulationDay + 1 { return .fertile }
        return .none
    }

    func phase(on date: Date) -> CyclePhase? {
        guard let c = cycleContaining(date) else { return nil }
        let n = days(c.start, date) + 1
        let ovulationDay = c.length - 13
        if n <= c.periodLength { return .period }
        if n == ovulationDay { return .ovulation }
        if n >= ovulationDay - 5 && n <= ovulationDay + 1 { return .fertile }
        return n < ovulationDay ? .follicular : .luteal
    }

    /// 今天之后（含今天）最近一次预测的经期开始
    var nextStart: Date? {
        nextStart(on: Date())
    }

    /// 指定日期之后（含当天）最近一次预测的经期开始。
    func nextStart(on date: Date) -> Date? {
        guard let last = lastStart else { return nil }
        let today = cal.startOfDay(for: date)
        var next = add(averageCycle, to: last)
        var guardCount = 0
        while next < today && guardCount < 200 {
            next = add(averageCycle, to: next)
            guardCount += 1
        }
        return next
    }

    var daysUntilNext: Int? { nextStart.map { days(Date(), $0) } }

    /// 下一个排卵日（今天或以后）
    var nextOvulation: Date? {
        guard let next = nextStart else { return nil }
        let ovulation = add(-14, to: next)
        if ovulation >= cal.startOfDay(for: Date()) { return ovulation }
        return add(averageCycle - 14, to: next)
    }

    var nextFertileWindow: (start: Date, end: Date)? {
        guard let ov = nextOvulation else { return nil }
        return (add(-5, to: ov), add(1, to: ov))
    }

    /// 当前周期的完整信息，给周期环用
    var current: (day: Int, length: Int, periodLength: Int, ovulationDay: Int)? {
        guard let c = cycleContaining(Date()) else { return nil }
        let day = days(c.start, Date()) + 1
        return (day, c.length, c.periodLength, c.length - 13)
    }
}
