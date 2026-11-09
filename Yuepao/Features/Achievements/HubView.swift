import SwiftUI
import SwiftData

/// 「成就」标签页：等级、每周目标、下一个目标、收藏入口、统计入口
struct HubView: View {
    @ObservedObject private var center = AchievementCenter.shared
    @Environment(\.modelContext) private var context
    @Query private var encounters: [Encounter]
    @Query private var places: [Place]
    @Query private var wishes: [WishItem]
    @ObservedObject private var config = ConfigStore.shared

    @State private var showSettings = false
    @State private var showReview = false
    @State private var selected: AchievementResult?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NavigationLink {
                        AchievementsView()
                    } label: {
                        LevelCard(level: center.level, unlocked: center.unlocked.count, total: center.results.count)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("levelCard")

                    WeeklyGoalCard(progress: center.weekly) { goal in
                        center.setWeeklyGoal(goal, context: context)
                    }

                    nextGoalsCard
                    recentCard
                    collectionsGrid
                    dataCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("成就")
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
            .sheet(item: $selected) { r in
                AchievementDetailSheet(result: r, date: center.unlockDate(r))
            }
            .fullScreenCover(isPresented: $showReview) {
                YearReviewView()
            }
            .onAppear { center.refresh(context: context) }
        }
    }

    // MARK: 下一个目标

    @ViewBuilder
    private var nextGoalsCard: some View {
        let goals = Array(center.nextGoals.prefix(3))
        if !goals.isEmpty {
            HubCard(title: "下一个目标", trailing: nil) {
                VStack(spacing: 14) {
                    ForEach(goals) { r in
                        Button {
                            selected = r
                        } label: {
                            HStack(spacing: 14) {
                                MedalView(symbol: r.def.symbol, tier: r.def.tier, unlocked: false,
                                          progress: r.progress, size: 44)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(r.def.title).font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text("+\(r.def.tier.points)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Palette.gold)
                                    }
                                    ProgressView(value: r.progress)
                                        .tint(Palette.gold)
                                    Text(nudge(for: r))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func nudge(for r: AchievementResult) -> String {
        switch r.def.category {
        case .milestone, .rhythm:
            return r.remaining == 1 ? "再约 1 次就能解锁" : "\(r.def.detail) · 还差 \(r.remaining)"
        case .harem:
            return "\(r.def.detail) · 还差 \(r.remaining)"
        default:
            return "\(r.def.detail) · 还差 \(r.remaining)"
        }
    }

    // MARK: 最近解锁

    @ViewBuilder
    private var recentCard: some View {
        let recent = Array(center.recent.prefix(8))
        HubCard(title: "最近解锁", trailing: "\(center.unlocked.count) / \(center.results.count)") {
            if recent.isEmpty {
                Text("记下第一次，就会解锁第一枚奖章")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(recent) { r in
                            Button {
                                selected = r
                            } label: {
                                VStack(spacing: 6) {
                                    MedalView(symbol: r.def.symbol, tier: r.def.tier, unlocked: true, size: 56)
                                    Text(r.def.title)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(1)
                                }
                                .frame(width: 70)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 18)
                }
                .padding(.horizontal, -18)
            }
        }
    }

    // MARK: 收藏

    private var codexSummary: String {
        let options = config.options(.positions)
        let used = Set(encounters.flatMap { $0.details.positions })
        return "\(options.filter { used.contains($0) }.count) / \(options.count)"
    }

    private var cityCount: Int {
        Set(encounters.compactMap { $0.place?.city.trimmed }.filter { !$0.isEmpty }).count
    }

    private var collectionsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            NavigationLink {
                CodexView()
            } label: {
                CollectionTile(symbol: "square.grid.3x3", title: "图鉴", value: codexSummary, caption: "体位 · 玩法 · 星座")
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("codexCard")

            NavigationLink {
                CityStampsView()
            } label: {
                CollectionTile(symbol: "seal", title: "城市印章", value: "\(cityCount)", caption: "去过的城市")
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("stampsCard")

            NavigationLink {
                WishListView()
            } label: {
                CollectionTile(symbol: "star", title: "心愿清单",
                               value: "\(wishes.filter(\.isDone).count) / \(wishes.count)", caption: "已实现")
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("wishCard")

            Button {
                showReview = true
            } label: {
                CollectionTile(symbol: "sparkles.rectangle.stack", title: "年度回顾",
                               value: "\(Calendar.current.component(.year, from: Date()))", caption: "这一年的故事")
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("reviewCard")
        }
    }

    // MARK: 数据

    private var dataCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                StatsView()
            } label: {
                DataRow(symbol: "chart.bar", title: "完整统计", detail: "\(encounters.count) 次")
            }
            .accessibilityIdentifier("openStats")
            Divider().padding(.leading, 50)
            NavigationLink {
                HealthTestListView()
            } label: {
                DataRow(symbol: "cross.case", title: "检测记录", detail: nil)
            }
            Divider().padding(.leading, 50)
            NavigationLink {
                PlaceListView()
            } label: {
                DataRow(symbol: "mappin.and.ellipse", title: "地点", detail: "\(places.count) 个")
            }
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

// MARK: - 组件

/// 点按时轻微缩小
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct HubCard<Content: View>: View {
    let title: String
    let trailing: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(Typo.display(19))
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

struct CollectionTile: View {
    let symbol: String
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Palette.gold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(Typo.display(26, weight: .medium))
                .foregroundStyle(Color.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                Text(caption).font(.caption).foregroundStyle(Color.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Palette.hairline, lineWidth: 0.5))
    }
}

struct DataRow: View {
    let symbol: String
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Palette.gold)
                .frame(width: 22)
            Text(title).foregroundStyle(Color.primary)
            Spacer()
            if let detail {
                Text(detail).foregroundStyle(Color.secondary).monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// 每周目标：进度环 + 连续周数
struct WeeklyGoalCard: View {
    let progress: WeeklyProgress
    let onChangeGoal: (Int) -> Void

    @State private var animated = false

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: animated ? progress.progress : 0)
                    .stroke(
                        AngularGradient(colors: [Palette.gold.opacity(0.7), Palette.gold, Color.accentColor.opacity(0.9)],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(progress.thisWeek)")
                        .font(Typo.display(26, weight: .medium))
                        .contentTransition(.numericText())
                    Text("/ \(progress.goal)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 86, height: 86)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("本周目标").font(Typo.display(19))
                    Spacer()
                    Menu {
                        Picker("每周目标", selection: Binding(get: { progress.goal }, set: { onChangeGoal($0) })) {
                            ForEach(1...7, id: \.self) { n in
                                Text("每周 \(n) 次").tag(n)
                            }
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(progress.met ? Palette.gold : Color.primary)
                HStack(spacing: 5) {
                    Image(systemName: "flame")
                        .foregroundStyle(progress.streak > 0 ? Color.accentColor : Color.secondary)
                    Text(progress.streak > 0 ? "已连续 \(progress.streak) 周达成" : "还没有连续记录")
                    if progress.best > progress.streak {
                        Text("· 最长 \(progress.best) 周")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .onAppear {
            withAnimation(.smooth(duration: 1.0).delay(0.2)) { animated = true }
        }
    }

    private var message: String {
        if progress.met {
            return progress.thisWeek > progress.goal ? "超额完成，状态火热" : "本周目标已达成"
        }
        if progress.thisWeek == 0 {
            return "这周还没有约，安排一下？"
        }
        return "再约 \(progress.remaining) 次就达成本周目标"
    }
}
