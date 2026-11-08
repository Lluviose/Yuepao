import Foundation
import UserNotifications

/// 本地通知：生日 / 纪念日 / 风险后检测提醒
enum Reminders {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "notificationsEnabled") }
    static var discreet: Bool { UserDefaults.standard.object(forKey: "discreetNotifications") as? Bool ?? true }
    static var riskEnabled: Bool { UserDefaults.standard.object(forKey: "riskReminders") as? Bool ?? true }
    static var periodEnabled: Bool { UserDefaults.standard.object(forKey: "periodReminders") as? Bool ?? false }

    private static let datePrefix = "date-"
    private static let riskPrefix = "risk-"

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

    // MARK: 生日 / 纪念日（每年重复）

    struct DateEvent {
        let key: String
        let name: String
        let title: String
        let date: Date
    }

    @MainActor
    static func rescheduleDates(girls: [Girl]) {
        let requests = enabled ? dateRequests(girls: girls) : []
        let keep = Set(requests.map(\.identifier))
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix("date-") && !keep.contains($0) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: stale)
        }
        // 相同 identifier 会直接覆盖旧的
        requests.forEach { UNUserNotificationCenter.current().add($0) }
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
        guard enabled, todo.remind, !todo.isDone, let fire = todo.fireDate, fire > Date() else { return }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let body = girlName.map { "\(todo.title)（\($0)）" } ?? todo.title
        add(id: "todo-\(todo.id)",
            content: content(title: "待办", body: body),
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    static func cancelTodo(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["todo-\(id)"])
    }

    // MARK: 风险提醒

    static func scheduleRiskFollowUps(encounterID: UUID, date: Date) {
        cancelRisk(encounterID: encounterID)
        guard enabled, riskEnabled else { return }
        let plan: [(Int, String)] = [
            (14, "距离那次无保护已经两周，建议做一次性病检测"),
            (42, "距离那次无保护已经六周，建议做 HIV / 梅毒等窗口期检测")
        ]
        for (days, body) in plan {
            guard var fire = Calendar.current.date(byAdding: .day, value: days, to: date) else { continue }
            fire = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: fire) ?? fire
            guard fire > Date() else { continue }
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            add(id: "\(riskPrefix)\(encounterID)-\(days)",
                content: content(title: "健康提醒", body: body),
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        }
    }

    static func cancelRisk(encounterID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [14, 42].map { "\(riskPrefix)\(encounterID)-\($0)" }
        )
    }

    static func removeAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private static func add(id: String, content: UNNotificationContent, trigger: UNNotificationTrigger) {
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
