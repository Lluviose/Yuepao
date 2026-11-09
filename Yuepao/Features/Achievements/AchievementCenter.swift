import Foundation
import SwiftData
import SwiftUI

/// 成就状态：负责刷新、记住哪些已经看过、排队弹出解锁动画
@MainActor
final class AchievementCenter: ObservableObject {
    static let shared = AchievementCenter()

    @Published private(set) var results: [AchievementResult] = []
    @Published private(set) var weekly = WeeklyProgress.empty
    @Published var celebrating: [AchievementResult] = []

    private var seen: Set<String> = []
    private var seenDates: [String: Date] = [:]
    private var initialized = false
    /// UI 测试时不写入磁盘，每次启动都是干净的
    private let persists: Bool

    private static let seenKey = "achievementsSeen"
    private static let datesKey = "achievementsSeenDates"
    private static let initKey = "achievementsInitialized"
    static let goalKey = "weeklyGoal"

    private init() {
        persists = !TestSupport.isUITesting
        guard persists else { return }
        let defaults = UserDefaults.standard
        seen = Set(defaults.stringArray(forKey: Self.seenKey) ?? [])
        if let raw = defaults.dictionary(forKey: Self.datesKey) as? [String: Double] {
            seenDates = raw.mapValues { Date(timeIntervalSince1970: $0) }
        }
        initialized = defaults.bool(forKey: Self.initKey)
    }

    var weeklyGoal: Int {
        let v = UserDefaults.standard.integer(forKey: Self.goalKey)
        return v > 0 ? v : 2
    }

    func setWeeklyGoal(_ goal: Int, context: ModelContext) {
        UserDefaults.standard.set(max(1, min(goal, 14)), forKey: Self.goalKey)
        refresh(context: context)
    }

    // MARK: 刷新

    func refresh(context: ModelContext) {
        let encounters = (try? context.fetch(FetchDescriptor<Encounter>())) ?? []
        let girls = (try? context.fetch(FetchDescriptor<Girl>())) ?? []
        let tests = (try? context.fetch(FetchDescriptor<HealthTest>())) ?? []
        let todos = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        let wishes = (try? context.fetch(FetchDescriptor<WishItem>())) ?? []
        let config = ConfigStore.shared
        let data = AchievementData(encounters: encounters, girls: girls, tests: tests, todos: todos, wishes: wishes,
                                   positionOptions: config.options(.positions), playOptions: config.options(.play),
                                   weeklyGoal: weeklyGoal)
        let fresh = AchievementEngine.evaluate(data)
        weekly = AchievementEngine.weekly(encounters.map(\.date), goal: weeklyGoal)
        Reminders.updateWeeklyNudge(remaining: weekly.remaining)

        let unlocked = fresh.filter(\.unlocked)
        if !initialized {
            // 第一次评估：已有的成就直接算看过，不刷屏
            initialized = true
            for r in unlocked {
                seen.insert(r.id)
                if seenDates[r.id] == nil { seenDates[r.id] = r.unlockedAt ?? Date() }
            }
            results = fresh
            save()
            return
        }

        let newOnes = unlocked.filter { !seen.contains($0.id) }
        for r in newOnes {
            seen.insert(r.id)
            if seenDates[r.id] == nil { seenDates[r.id] = r.unlockedAt ?? Date() }
        }
        results = fresh
        guard !newOnes.isEmpty else { return }
        save()
        // 等编辑页收起来再弹
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.spring(duration: 0.5)) {
                self.celebrating.append(contentsOf: newOnes)
            }
        }
    }

    func dismissCelebration() {
        guard !celebrating.isEmpty else { return }
        withAnimation(.snappy) {
            _ = celebrating.removeFirst()
        }
    }

    private func save() {
        guard persists else { return }
        let defaults = UserDefaults.standard
        defaults.set(Array(seen), forKey: Self.seenKey)
        defaults.set(seenDates.mapValues { $0.timeIntervalSince1970 }, forKey: Self.datesKey)
        defaults.set(true, forKey: Self.initKey)
    }

    // MARK: 汇总

    func unlockDate(_ r: AchievementResult) -> Date? {
        guard r.unlocked else { return nil }
        return r.unlockedAt ?? seenDates[r.id]
    }

    var unlocked: [AchievementResult] { results.filter(\.unlocked) }

    var points: Int { unlocked.reduce(0) { $0 + $1.def.tier.points } }

    var level: LevelInfo { AchievementEngine.level(points: points) }

    /// 最近解锁的
    var recent: [AchievementResult] {
        unlocked.sorted { (unlockDate($0) ?? .distantPast) > (unlockDate($1) ?? .distantPast) }
    }

    /// 最接近解锁的几个（不含隐藏成就）
    var nextGoals: [AchievementResult] {
        results.filter { !$0.unlocked && !$0.def.secret && $0.target > 0 }
            .sorted { a, b in
                if a.progress != b.progress { return a.progress > b.progress }
                return a.remaining < b.remaining
            }
    }
}
