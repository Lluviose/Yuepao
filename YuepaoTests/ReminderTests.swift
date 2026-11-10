import Foundation
import UserNotifications
import XCTest
@testable import Yuepao

@MainActor
final class ReminderTests: XCTestCase {
    private let keys = ["notificationsEnabled", "discreetNotifications", "riskReminders", "periodReminders", "weeklyNudge"]

    func testEnablingPrivacyReplacesExistingPlaintextTodoAndRiskRequests() throws {
        try withPreferences {
            let girl = Girl(name: "私密代号")
            girl.update { $0.birthday = Date() }
            let todo = TodoItem(title: "私密待办")
            todo.girlID = girl.id
            todo.dueDate = Date().addingTimeInterval(3 * 86400)
            todo.hasTime = true
            let encounter = Encounter(date: Date())
            encounter.protection = .none
            let scheduler = MemoryScheduler()
            @MainActor func rebuild() {
                Reminders.rescheduleAll(girls: [girl], encounters: [encounter], todos: [todo],
                                       weeklyRemaining: 2, scheduler: scheduler)
            }

            UserDefaults.standard.set(false, forKey: "discreetNotifications")
            rebuild()
            let visibleTodo = try XCTUnwrap(scheduler.pending.first { $0.identifier == "todo-\(todo.id)" })
            XCTAssertTrue(visibleTodo.content.body.contains(girl.name))
            XCTAssertTrue(visibleTodo.content.body.contains(todo.title))
            XCTAssertEqual(scheduler.pending.filter { $0.identifier.hasPrefix("risk-") }.count, 2)
            let identifiers = Set(scheduler.pending.map(\.identifier))

            UserDefaults.standard.set(true, forKey: "discreetNotifications")
            rebuild()
            XCTAssertEqual(Set(scheduler.pending.map(\.identifier)), identifiers)
            XCTAssertTrue(scheduler.removedDelivered)
            XCTAssertTrue(scheduler.pending.allSatisfy {
                $0.content.title == "提醒" && $0.content.body == "你有一条待办事项"
            })
            // 关闭隐藏后应从数据重建原内容，而不是永久丢失原始标题。
            UserDefaults.standard.set(false, forKey: "discreetNotifications")
            rebuild()
            XCTAssertTrue(try XCTUnwrap(scheduler.pending.first { $0.identifier == visibleTodo.identifier }).content.body.contains(todo.title))
        }
    }

    func testRebuildingCancelsOldDataAndDisabledRiskReminders() throws {
        withPreferences {
            let todo = TodoItem(title: "旧待办")
            todo.hasTime = true
            todo.dueDate = Date().addingTimeInterval(86400)
            let encounter = Encounter()
            encounter.protection = .none
            let scheduler = MemoryScheduler()
            Reminders.rescheduleAll(girls: [], encounters: [encounter], todos: [todo], weeklyRemaining: 0, scheduler: scheduler)
            XCTAssertEqual(scheduler.pending.count, 3)

            UserDefaults.standard.set(false, forKey: "riskReminders")
            Reminders.rescheduleAll(girls: [], encounters: [encounter], todos: [todo], weeklyRemaining: 0, scheduler: scheduler)
            XCTAssertEqual(scheduler.pending.map(\.identifier), ["todo-\(todo.id)"])

            Reminders.rescheduleAll(girls: [], encounters: [], todos: [], weeklyRemaining: 0, scheduler: scheduler)
            XCTAssertTrue(scheduler.pending.isEmpty)
        }
    }

    func testDisablingNotificationsRemovesAllPendingAndDeliveredContent() throws {
        withPreferences {
            let todo = TodoItem(title: "待办")
            todo.hasTime = true
            todo.dueDate = Date().addingTimeInterval(86400)
            let scheduler = MemoryScheduler()
            Reminders.rescheduleAll(girls: [], encounters: [], todos: [todo], weeklyRemaining: 0, scheduler: scheduler)
            XCTAssertFalse(scheduler.pending.isEmpty)

            UserDefaults.standard.set(false, forKey: "notificationsEnabled")
            Reminders.rescheduleAll(girls: [], encounters: [], todos: [todo], weeklyRemaining: 0, scheduler: scheduler)
            XCTAssertTrue(scheduler.pending.isEmpty)
            XCTAssertTrue(scheduler.removedDelivered)
        }
    }

    private func withPreferences(_ operation: @MainActor () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(true, forKey: "notificationsEnabled")
        defaults.set(true, forKey: "riskReminders")
        defaults.set(false, forKey: "periodReminders")
        defaults.set(false, forKey: "weeklyNudge")
        try operation()
    }
}

private final class MemoryScheduler: ReminderScheduler {
    var pending: [UNNotificationRequest] = []
    var removedDelivered = false

    func replacePending(with requests: [UNNotificationRequest], removeDelivered: Bool) {
        pending = requests
        removedDelivered = removeDelivered
    }
}
