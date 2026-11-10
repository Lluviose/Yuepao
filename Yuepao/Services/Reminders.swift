import Foundation
import UserNotifications

protocol ReminderScheduler {
    func replacePending(with requests: [UNNotificationRequest], removeDelivered: Bool)
}

struct SystemReminderScheduler: ReminderScheduler {
    func replacePending(with requests: [UNNotificationRequest], removeDelivered: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        requests.forEach { center.add($0) }
        if removeDelivered { center.removeAllDeliveredNotifications() }
    }
}

/// 本地通知：生日 / 纪念日 / 风险后检测提醒
enum Reminders {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "notificationsEnabled") }
    static var discreet: Bool { UserDefaults.standard.object(forKey: "discreetNotifications") as? Bool ?? true }
    static var riskEnabled: Bool { UserDefaults.standard.object(forKey: "riskReminders") as? Bool ?? true }
    static var periodEnabled: Bool { UserDefaults.standard.object(forKey: "periodReminders") as? Bool ?? false }
    static var weeklyNudgeEnabled: Bool { UserDefaults.standard.bool(forKey: "weeklyNudge") }

    private static let datePrefix = "date-"
    private static let riskPrefix = "risk-"
    @MainActor private static var dateScheduleGeneration = 0

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    private static func content(title: String, body: String) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        if discreet {
            c.title = "提醒"
            c.body = "你有一条待办事项"
        } else {
            c.title = title
            c.body = body
        }
        c.sound = .default
        return c
    }

    /// 设置隐私开关、重新开启提醒和恢复备份后，重建全部通知，避免旧请求保留明文或已删除的数据。
    @MainActor
    static func rescheduleAll(girls: [Girl], encounters: [Encounter], todos: [TodoItem], weeklyRemaining: Int,
                              scheduler: any ReminderScheduler = SystemReminderScheduler()) {
        dateScheduleGeneration += 1
        let requests = allRequests(girls: girls, encounters: encounters, todos: todos, weeklyRemaining: weeklyRemaining)
        // 已送达的明文通知也不应在开启隐藏内容后留在通知中心。
        scheduler.replacePending(with: requests, removeDelivered: discreet || !enabled)
    }

    @MainActor
    static func allRequests(girls: [Girl], encounters: [Encounter], todos: [TodoItem], weeklyRemaining: Int) -> [UNNotificationRequest] {
        guard enabled else { return [] }
        var requests = dateRequests(girls: girls)
        for todo in todos {
            if let request = todoRequest(todo, girlName: girls.first { $0.id == todo.girlID }?.name) {
                requests.append(request)
            }
        }
        for encounter in encounters where encounter.stiRisk || encounter.pregnancyRisk {
            requests.append(contentsOf: riskRequests(encounterID: encounter.id, date: encounter.date))
        }
        if let request = weeklyRequest(remaining: weeklyRemaining) { requests.append(request) }
        // iOS 最多保留 64 项，优先安排最近到期的提醒。
        return Array(requests.sorted {
            let a = ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
            let b = ($1.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
            return a < b
        }.prefix(64))
    }

    // MARK: 生日 / 纪念日（每年重复）

    struct DateEvent {
        let key: String
        let name: String
        let title: String
        let date: Date
    }

    @MainActor
    static func rescheduleDates(girls: [Girl]) {
        dateScheduleGeneration += 1
        let generation = dateScheduleGeneration
        let requests = enabled ? dateRequests(girls: girls) : []
        let keep = Set(requests.map(\.identifier))
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            Task { @MainActor in
                guard generation == dateScheduleGeneration, enabled else { return }
                let center = UNUserNotificationCenter.current()
                let stale = pending.map(\.identifier).filter { $0.hasPrefix("date-") && !keep.contains($0) }
                center.removePendingNotificationRequests(withIdentifiers: stale)
                requests.forEach { center.add($0) }
            }
        }
    }

    @MainActor
    private static func dateRequests(girls: [Girl]) -> [UNNotificationRequest] {
        var result: [UNNotificationRequest] = []
        var events: [DateEvent] = []
        for girl in girls where girl.status != .blocked {
            let d = girl.details
            if let birthday = d.birthday {
                events.append(DateEvent(key: "\(girl.id)-bd", name: girl.name, title: "生日", date: birthday))
            }
            for item in d.importantDates where item.remind {
                events.append(DateEvent(key: "\(girl.id)-\(item.id)", name: girl.name, title: item.title, date: item.date))
            }
        }

        // 经期提醒：预计开始的前一天晚上
        if periodEnabled {
            let candidates = girls.filter { $0.status.isCurrent }
                .compactMap { g -> (Girl, Date)? in
                    guard let next = g.details.cycle.nextStart else { return nil }
                    return (g, next)
                }
                .sorted { $0.1 < $1.1 }
                .prefix(8)
            for (girl, next) in candidates {
                guard let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: next),
                      let fire = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: dayBefore),
                      fire > Date() else { continue }
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                result.append(UNNotificationRequest(
                    identifier: "\(datePrefix)period-\(girl.id)",
                    content: content(title: "经期提醒", body: "「\(girl.name)」明天可能来例假"),
                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
        }

        // iOS 最多保留 64 条待发通知，按最近的排，给待办留出空间
        let sorted = events.sorted { daysUntilNext($0.date) < daysUntilNext($1.date) }.prefix(18)
        let cal = Calendar.current
        for event in sorted {
            let md = cal.dateComponents([.month, .day], from: event.date)

            var onDay = DateComponents()
            onDay.month = md.month
            onDay.day = md.day
            onDay.hour = 9
            onDay.minute = 0
            result.append(UNNotificationRequest(
                identifier: "\(datePrefix)\(event.key)-0",
                content: content(title: "\(event.title)提醒", body: "今天是「\(event.name)」的\(event.title)"),
                trigger: UNCalendarNotificationTrigger(dateMatching: onDay, repeats: true)))

            if let dayBefore = cal.date(byAdding: .day, value: -1, to: event.date) {
                let mdBefore = cal.dateComponents([.month, .day], from: dayBefore)
                var before = DateComponents()
                before.month = mdBefore.month
                before.day = mdBefore.day
                before.hour = 20
                before.minute = 0
                result.append(UNNotificationRequest(
                    identifier: "\(datePrefix)\(event.key)-1",
                    content: content(title: "\(event.title)提醒", body: "明天是「\(event.name)」的\(event.title)，礼物准备了吗？"),
                    trigger: UNCalendarNotificationTrigger(dateMatching: before, repeats: true)))
            }
        }
        return result
    }

    /// 距离下一次（今年或明年）这个月日还有几天
    static func daysUntilNext(_ date: Date, from now: Date = Date()) -> Int {
        let cal = Calendar.current
        let md = cal.dateComponents([.month, .day], from: date)
        let today = cal.startOfDay(for: now)
        guard let next = cal.nextDate(after: today.addingTimeInterval(-1), matching: md, matchingPolicy: .nextTimePreservingSmallerComponents) else {
            return 999
        }
        return cal.dateComponents([.day], from: today, to: next).day ?? 999
    }

    // MARK: 待办

    static func scheduleTodo(_ todo: TodoItem, girlName: String?) {
        cancelTodo(id: todo.id)
        if let request = todoRequest(todo, girlName: girlName) {
            UNUserNotificationCenter.current().add(request)
        }
    }

    private static func todoRequest(_ todo: TodoItem, girlName: String?) -> UNNotificationRequest? {
        guard enabled, todo.remind, !todo.isDone, let fire = todo.fireDate, fire > Date() else { return nil }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let body = girlName.map { "\(todo.title)（\($0)）" } ?? todo.title
        return UNNotificationRequest(identifier: "todo-\(todo.id)",
            content: content(title: "待办", body: body),
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    static func cancelTodo(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["todo-\(id)"])
    }

    // MARK: 每周目标

    private static let weeklyNudgeID = "weekly-nudge"

    /// 本周还没达成目标时，周四晚上 8 点提醒一次
    static func updateWeeklyNudge(remaining: Int) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [weeklyNudgeID])
        if let request = weeklyRequest(remaining: remaining) {
            UNUserNotificationCenter.current().add(request)
        }
    }

    private static func weeklyRequest(remaining: Int) -> UNNotificationRequest? {
        guard enabled, weeklyNudgeEnabled, remaining > 0 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = .current
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
              let thursday = cal.date(byAdding: .day, value: 3, to: weekStart),
              let fire = cal.date(bySettingHour: 20, minute: 0, second: 0, of: thursday),
              fire > Date() else { return nil }
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        return UNNotificationRequest(identifier: weeklyNudgeID,
            content: content(title: "本周目标", body: "本周还差 \(remaining) 次达成目标，周末安排一下？"),
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    // MARK: 风险提醒

    static func scheduleRiskFollowUps(encounterID: UUID, date: Date) {
        cancelRisk(encounterID: encounterID)
        riskRequests(encounterID: encounterID, date: date).forEach { UNUserNotificationCenter.current().add($0) }
    }

    private static func riskRequests(encounterID: UUID, date: Date) -> [UNNotificationRequest] {
        guard enabled, riskEnabled else { return [] }
        var requests: [UNNotificationRequest] = []
        let plan: [(Int, String)] = [
            (14, "距离那次无保护已经两周，建议做一次性病检测"),
            (42, "距离那次无保护已经六周，建议做 HIV / 梅毒等窗口期检测")
        ]
        for (days, body) in plan {
            guard var fire = Calendar.current.date(byAdding: .day, value: days, to: date) else { continue }
            fire = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: fire) ?? fire
            guard fire > Date() else { continue }
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            requests.append(UNNotificationRequest(identifier: "\(riskPrefix)\(encounterID)-\(days)",
                content: content(title: "健康提醒", body: body),
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
        return requests
    }

    static func cancelRisk(encounterID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [14, 42].map { "\(riskPrefix)\(encounterID)-\($0)" }
        )
    }

    static func removeAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
