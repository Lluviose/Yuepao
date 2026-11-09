import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query private var girls: [Girl]
    @Query(sort: \Encounter.date, order: .reverse) private var encounters: [Encounter]
    @Query(sort: \HealthTest.date, order: .reverse) private var tests: [HealthTest]
    @Query private var todos: [TodoItem]
    @Environment(\.modelContext) private var context

    @State private var rankingMode: RankingMode = .count
    @State private var showSettings = false
    @State private var chartsVisible = false
    @State private var selectedMonth: Date?

    enum RankingMode: String, CaseIterable, Identifiable {
        case count, rounds, spending, rating
        var id: String { rawValue }
        var title: String {
            switch self {
            case .count: return "次数"
            case .rounds: return "回合"
            case .spending: return "投入"
            case .rating: return "评分"
            }
        }
    }

    var body: some View {
        let stats = StatsData(girls: girls, encounters: encounters)
        NavigationStack {
            List {
                upcomingSection(stats)
                overviewSection(stats)
                monthlySection(stats)
                heatmapSection(stats)
                weekdaySection(stats)
                rankingSection(stats)
                channelSection(stats)
                safetySection(stats)
                spendingSection(stats)
            }
            .navigationTitle("统计")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                    .accessibilityIdentifier("openSettings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                withAnimation(.smooth(duration: 0.9).delay(0.1)) { chartsVisible = true }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func upcomingSection(_ s: StatsData) -> some View {
        let items = s.upcoming
        let cold = s.coldGirls
        let dueTodos = s.upcomingTodos(todos)
        if !items.isEmpty || !cold.isEmpty || !dueTodos.isEmpty {
            Section("近期提醒") {
                ForEach(dueTodos) { todo in
                    TodoRow(todo: todo, girlName: girls.first { $0.id == todo.girlID }?.name) {
                        TodoActions.toggle(todo, girls: girls, context: context)
                    }
                }
                ForEach(items) { item in
                    NavigationLink {
                        GirlDetailView(girl: item.girl)
                    } label: {
                        HStack(spacing: 10) {
                            AvatarView(photoID: item.girl.avatarID, name: item.girl.name, size: 32)
                            Text(item.text)
                            Spacer()
                            Text(item.days == 0 ? "今天" : "\(item.days) 天后")
                                .foregroundStyle(item.days <= 3 ? Color.orange : Color.secondary)
                        }
                    }
                }
                ForEach(cold, id: \.girl.id) { entry in
                    NavigationLink {
                        GirlDetailView(girl: entry.girl)
                    } label: {
                        HStack(spacing: 10) {
                            AvatarView(photoID: entry.girl.avatarID, name: entry.girl.name, size: 32)
                            Text("\(entry.girl.name) 被冷落了")
                            Spacer()
                            Text("\(entry.days) 天没联系").foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    private func overviewSection(_ s: StatsData) -> some View {
        Section("总览") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                StatCell(value: "\(s.haremCount)", label: "后宫")
                StatCell(value: "\(s.flirtingCount)", label: "暧昧中")
                StatCell(value: "\(s.conquered)", label: "累计拿下")
                StatCell(value: "\(s.encounters.count)", label: "累计次数")
                StatCell(value: "\(s.totalRounds)", label: "累计回合")
                StatCell(value: "\(s.placeCount)", label: "去过的地点")
                StatCell(value: "\(s.thisMonth)", label: "本月次数")
                StatCell(value: "\(s.thisYear)", label: "今年次数")
                StatCell(value: s.averageGap.map { "\($0) 天" } ?? "—", label: "平均间隔")
            }
            .padding(.vertical, 6)
        }
    }

    private func monthlySection(_ s: StatsData) -> some View {
        Section {
            Chart(s.monthly) { item in
                let isSelected = selectedMonth.map { Calendar.current.isDate($0, equalTo: item.month, toGranularity: .month) } ?? false
                BarMark(
                    x: .value("月份", item.month, unit: .month),
                    y: .value("次数", chartsVisible ? item.count : 0)
                )
                .foregroundStyle(selectedMonth == nil || isSelected
                                 ? Color.accentColor.gradient
                                 : Color.accentColor.opacity(0.25).gradient)
                .cornerRadius(3)
                .annotation(position: .top, spacing: 4) {
                    if isSelected {
                        Text("\(item.count)")
                            .font(.caption.weight(.bold))
                            .fontDesign(.rounded)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .chartXSelection(value: $selectedMonth)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits), centered: true)
                }
            }
            .frame(height: 180)
            .padding(.vertical, 6)
            .sensoryFeedback(.selection, trigger: selectedMonth.map { Calendar.current.component(.month, from: $0) })
        } header: {
            HStack {
                Text("近 12 个月")
                Spacer()
                if let m = selectedMonth, let item = s.monthly.first(where: { Calendar.current.isDate($0.month, equalTo: m, toGranularity: .month) }) {
                    Text("\(Fmt.month(item.month)) · \(item.count) 次")
                        .foregroundStyle(Color.accentColor)
                        .transition(.opacity)
                } else {
                    Text("按住柱子查看").foregroundStyle(.tertiary)
                }
            }
            .animation(.snappy, value: selectedMonth)
        }
    }

    private func heatmapSection(_ s: StatsData) -> some View {
        Section {
            HeatmapView(counts: s.dailyCounts, weeks: 20)
                .padding(.vertical, 6)
        } header: {
            Text("最近 20 周")
        }
    }

    private func weekdaySection(_ s: StatsData) -> some View {
        Section("星期 / 时段分布") {
            Chart(s.weekdays) { item in
                BarMark(
                    x: .value("星期", item.label),
                    y: .value("次数", chartsVisible ? item.count : 0)
                )
                .foregroundStyle(Color.pink.gradient)
                .cornerRadius(3)
            }
            .frame(height: 140)
            .padding(.top, 6)

            Chart(s.dayParts) { item in
                BarMark(
                    x: .value("时段", item.label),
                    y: .value("次数", chartsVisible ? item.count : 0)
                )
                .foregroundStyle(Color.purple.gradient)
                .cornerRadius(3)
            }
            .frame(height: 140)
            .padding(.vertical, 6)
        }
    }

    private func rankingSection(_ s: StatsData) -> some View {
        let ranking = s.ranking(rankingMode)
        let top = ranking.first?.value ?? 1
        return Section {
            Picker("排行", selection: $rankingMode) {
                ForEach(RankingMode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            ForEach(Array(ranking.prefix(10).enumerated()), id: \.element.girl.id) { index, entry in
                NavigationLink {
                    GirlDetailView(girl: entry.girl)
                } label: {
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(index < 3 ? Color.orange : Color.secondary)
                            .frame(width: 20)
                        AvatarView(photoID: entry.girl.avatarID, name: entry.girl.name, size: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.girl.name).font(.subheadline)
                            ProgressView(value: top > 0 ? entry.value / top : 0)
                                .tint(entry.girl.status.color)
                        }
                        Text(entry.label)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("排行榜")
        }
    }

    @ViewBuilder
    private func channelSection(_ s: StatsData) -> some View {
        let rows = s.channels
        if !rows.isEmpty {
            Section {
                ForEach(rows, id: \.channel) { row in
                    HStack {
                        Text(row.channel)
                        Spacer()
                        Text("\(row.total) 人 · 拿下 \(row.conquered)")
                            .foregroundStyle(.secondary)
                        Text("\(Int((Double(row.conquered) / Double(max(row.total, 1)) * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("认识渠道")
            } footer: {
                Text("拿下 = 至少有一次记录。")
            }
        }
    }

    private func safetySection(_ s: StatsData) -> some View {
        Section("安全") {
            InfoRow(label: "安全套", value: "\(s.protectedCount) 次")
            InfoRow(label: "有风险的", value: "\(s.riskyCount) 次")
            if s.brokeCount > 0 { InfoRow(label: "破套", value: "\(s.brokeCount) 次") }
            InfoRow(label: "未记录措施", value: "\(s.unrecordedCount) 次")
            NavigationLink {
                HealthTestListView()
            } label: {
                LabeledContent("检测记录") {
                    if let last = tests.first {
                        Text("上次 \(Fmt.daysAgo(last.date))")
                    } else {
                        Text("还没有")
                    }
                }
            }
            if let lastRisk = s.lastRiskDate, tests.first.map({ $0.date < lastRisk }) ?? true {
                Label("上次风险（\(Fmt.daysAgo(lastRisk))）之后还没做过检测", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
            }
        }
    }

    private func spendingSection(_ s: StatsData) -> some View {
        Section("花费") {
            InfoRow(label: "本月", value: Fmt.money(s.spendingThisMonth))
            InfoRow(label: "今年", value: Fmt.money(s.spendingThisYear))
            InfoRow(label: "累计（含礼物）", value: Fmt.money(s.spendingTotal))
            if s.encounters.count > 0 {
                InfoRow(label: "平均每次约会", value: Fmt.money((s.encounterSpending / Double(s.encounters.count)).rounded()))
            }
        }
    }
}

// MARK: - Heatmap

struct HeatmapView: View {
    let counts: [Date: Int]
    let weeks: Int

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.locale = Fmt.locale
        return cal
    }

    var body: some View {
        let cal = calendar
        let today = cal.startOfDay(for: Date())
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek
        let maxCount = max(counts.values.max() ?? 1, 1)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: w * 7 + d, to: start) ?? start
                            let n = counts[day] ?? 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(fill(n, maxCount: maxCount, future: day > today))
                                .frame(width: 13, height: 13)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 4) {
                Spacer()
                Text("少").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i == 0 ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(0.3 + Double(i) * 0.23))
                        .frame(width: 10, height: 10)
                }
                Text("多").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func fill(_ n: Int, maxCount: Int, future: Bool) -> Color {
        if future { return .clear }
        if n == 0 { return Color.secondary.opacity(0.15) }
        return Color.accentColor.opacity(0.3 + 0.7 * Double(n) / Double(maxCount))
    }
}

// MARK: - 数据计算

struct StatsData {
    let girls: [Girl]
    let encounters: [Encounter]

    struct MonthCount: Identifiable {
        let month: Date
        let count: Int
        var id: Date { month }
    }

    struct LabelCount: Identifiable {
        let label: String
        let count: Int
        var id: String { label }
    }

    struct Upcoming: Identifiable {
        let girl: Girl
        let text: String
        let days: Int
        var id: String { "\(girl.id)-\(text)" }
    }

    struct RankEntry {
        let girl: Girl
        let value: Double
        let label: String
    }

    var haremCount: Int { girls.filter { $0.status.inHarem }.count }
    var flirtingCount: Int { girls.filter { $0.status == .flirting }.count }
    var conquered: Int { girls.filter { !$0.encounters.isEmpty }.count }
    var totalRounds: Int { encounters.reduce(0) { $0 + $1.count } }
    var placeCount: Int { Set(encounters.compactMap { $0.place?.id }).count }

    var thisMonth: Int {
        encounters.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }.count
    }

    var thisYear: Int {
        encounters.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .year) }.count
    }

    /// 最近 10 次之间的平均间隔天数
    var averageGap: Int? {
        let dates = encounters.prefix(11).map(\.date)
        guard dates.count >= 2, let first = dates.last, let last = dates.first else { return nil }
        let days = Fmt.days(from: first, to: last)
        return Int((Double(days) / Double(dates.count - 1)).rounded())
    }

    var monthly: [MonthCount] {
        let cal = Calendar.current
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        var buckets: [Date: Int] = [:]
        for e in encounters {
            let m = cal.date(from: cal.dateComponents([.year, .month], from: e.date)) ?? e.date
            buckets[m, default: 0] += 1
        }
        return (0..<12).reversed().compactMap { offset in
            guard let m = cal.date(byAdding: .month, value: -offset, to: thisMonth) else { return nil }
            return MonthCount(month: m, count: buckets[m] ?? 0)
        }
    }

    var dailyCounts: [Date: Int] {
        var result: [Date: Int] = [:]
        let cal = Calendar.current
        for e in encounters {
            result[cal.startOfDay(for: e.date), default: 0] += 1
        }
        return result
    }

    var weekdays: [LabelCount] {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        var counts = Array(repeating: 0, count: 7)
        for e in encounters {
            counts[Calendar.current.component(.weekday, from: e.date) - 1] += 1
        }
        return [1, 2, 3, 4, 5, 6, 0].map { LabelCount(label: "周" + names[$0], count: counts[$0]) }
    }

    var dayParts: [LabelCount] {
        let parts = ["凌晨", "上午", "下午", "傍晚", "晚上", "深夜"]
        var counts = Array(repeating: 0, count: parts.count)
        for e in encounters {
            let h = Calendar.current.component(.hour, from: e.date)
            let index: Int
            switch h {
            case 0..<6: index = 0
            case 6..<12: index = 1
            case 12..<17: index = 2
            case 17..<19: index = 3
            case 19..<23: index = 4
            default: index = 5
            }
            counts[index] += 1
        }
        return parts.enumerated().map { LabelCount(label: $0.element, count: counts[$0.offset]) }
    }

    func ranking(_ mode: StatsView.RankingMode) -> [RankEntry] {
        let entries: [RankEntry] = girls.compactMap { (g: Girl) -> RankEntry? in
            switch mode {
            case .count:
                let n = g.encounters.count
                return n > 0 ? RankEntry(girl: g, value: Double(n), label: "\(n) 次") : nil
            case .rounds:
                let n = g.totalRounds
                return n > 0 ? RankEntry(girl: g, value: Double(n), label: "\(n) 回合") : nil
            case .spending:
                let v = g.encounterSpending + g.details.giftSpending
                return v > 0 ? RankEntry(girl: g, value: v, label: Fmt.money(v.rounded())) : nil
            case .rating:
                let r = g.details.ratingOverall
                return r > 0 ? RankEntry(girl: g, value: Double(r), label: "\(r) 分") : nil
            }
        }
        return entries.sorted { $0.value > $1.value }
    }

    var channels: [(channel: String, total: Int, conquered: Int)] {
        var map: [String: (Int, Int)] = [:]
        for g in girls {
            let c = g.details.channel
            guard !c.isEmpty else { continue }
            var v = map[c] ?? (0, 0)
            v.0 += 1
            if !g.encounters.isEmpty { v.1 += 1 }
            map[c] = v
        }
        return map.map { (channel: $0.key, total: $0.value.0, conquered: $0.value.1) }
            .sorted { $0.total > $1.total }
    }

    var protectedCount: Int { encounters.filter { ($0.protection == .condom || $0.protection == .both) && !$0.condomBroke }.count }
    var riskyCount: Int { encounters.filter { $0.stiRisk || $0.pregnancyRisk }.count }
    var brokeCount: Int { encounters.filter { $0.condomBroke }.count }
    var unrecordedCount: Int { encounters.filter { $0.protection == .unrecorded }.count }
    var lastRiskDate: Date? { encounters.first { $0.stiRisk }?.date }

    var encounterSpending: Double { encounters.reduce(0) { $0 + $1.totalCost } }
    var giftSpending: Double { girls.reduce(0) { $0 + $1.details.giftSpending } }
    var spendingTotal: Double { encounterSpending + giftSpending }

    var spendingThisMonth: Double { spending { Calendar.current.isDate($0, equalTo: Date(), toGranularity: .month) } }
    var spendingThisYear: Double { spending { Calendar.current.isDate($0, equalTo: Date(), toGranularity: .year) } }

    private func spending(where match: (Date) -> Bool) -> Double {
        let e = encounters.filter { match($0.date) }.reduce(0) { $0 + $1.totalCost }
        let g = girls.reduce(0.0) { sum, girl in
            sum + girl.details.gifts.filter { match($0.date) }.reduce(0) { $0 + $1.amount }
        }
        return e + g
    }

    var upcoming: [Upcoming] {
        var items: [Upcoming] = []
        for g in girls where g.status.isCurrent {
            let d = g.details
            if let bd = d.birthday {
                let n = Reminders.daysUntilNext(bd)
                if n <= 30 { items.append(Upcoming(girl: g, text: "\(g.name) 生日", days: n)) }
            }
            for item in d.importantDates {
                let n = Reminders.daysUntilNext(item.date)
                if n <= 30 { items.append(Upcoming(girl: g, text: "\(g.name) · \(item.title)", days: n)) }
            }
            let cycle = d.cycle
            if cycle.hasData, !cycle.isOngoing, let n = cycle.daysUntilNext, (0...5).contains(n) {
                items.append(Upcoming(girl: g, text: "\(g.name) 预计来例假", days: n))
            }
        }
        return items.sorted { $0.days < $1.days }
    }

    func upcomingTodos(_ todos: [TodoItem]) -> [TodoItem] {
        todos.filter { t in
            guard !t.isDone, let due = t.dueDate else { return false }
            return t.isOverdue || Fmt.days(from: Date(), to: due) <= 3
        }
        .sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
    }

    var coldGirls: [(girl: Girl, days: Int)] {
        girls.compactMap { (g: Girl) -> (girl: Girl, days: Int)? in
            guard g.status.isCurrent else { return nil }
            let d = g.details
            guard d.contactGoalDays > 0 else { return nil }
            let last = g.lastInteraction(details: d) ?? g.createdAt
            let days = Fmt.days(from: last)
            return days > d.contactGoalDays ? (girl: g, days: days) : nil
        }
        .sorted { $0.days > $1.days }
    }
}
