import SwiftUI
import SwiftData

/// 等级卡：酒红皮面质感 + 月桂 + 金色进度
struct LevelCard: View {
    let level: LevelInfo
    let unlocked: Int
    let total: Int

    @State private var shown = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "laurel.leading")
                    .font(.system(size: 34, weight: .light))
                VStack(spacing: 0) {
                    Text("LV")
                        .font(.caption2.weight(.semibold))
                        .tracking(2)
                        .opacity(0.7)
                    Text("\(level.level)")
                        .font(Typo.display(46, weight: .medium))
                        .contentTransition(.numericText())
                }
                Image(systemName: "laurel.trailing")
                    .font(.system(size: 34, weight: .light))
            }
            .foregroundStyle(Palette.gold)

            VStack(spacing: 4) {
                Text(level.title)
                    .font(Typo.display(22))
                    .foregroundStyle(.white)
                Text("魅力值 \(level.points)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .monospacedDigit()
            }

            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.gold.opacity(0.8), Palette.gold], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, geo.size.width * (shown ? level.progress : 0)))
                    }
                }
                .frame(height: 5)
                HStack {
                    Text("已解锁 \(unlocked) / \(total)")
                    Spacer()
                    if let next = level.nextThreshold, let title = level.nextTitle {
                        Text("距「\(title)」还差 \(next - level.points)")
                    } else {
                        Text("已达最高等级")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.6))
                .monospacedDigit()
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(LeatherBackground(cornerRadius: 26))
        .onAppear {
            withAnimation(.smooth(duration: 1.0).delay(0.15)) { shown = true }
        }
    }
}

/// 深酒红皮面背景（和 App 图标呼应）
struct LeatherBackground: View {
    var cornerRadius: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.12, blue: 0.20), Color(red: 0.20, green: 0.05, blue: 0.10)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RadialGradient(colors: [.white.opacity(0.14), .clear], center: UnitPoint(x: 0.2, y: 0.0),
                               startRadius: 0, endRadius: 260)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: max(cornerRadius - 7, 0), style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.white.opacity(0.14))
                    .padding(7)
            )
            .shadow(color: Color(red: 0.3, green: 0.05, blue: 0.12).opacity(0.35), radius: 16, y: 8)
    }
}

// MARK: - 成就馆

struct AchievementsView: View {
    @ObservedObject private var center = AchievementCenter.shared
    @Environment(\.modelContext) private var context
    @State private var filter: AchievementCategory?
    @State private var selected: AchievementResult?

    private var shown: [AchievementResult] {
        guard let filter else { return center.results }
        return center.results.filter { $0.def.category == filter }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LevelCard(level: center.level, unlocked: center.unlocked.count, total: center.results.count)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ChoiceChip(title: "全部", selected: filter == nil) { filter = nil }
                        ForEach(AchievementCategory.allCases) { c in
                            let all = center.results.filter { $0.def.category == c }
                            ChoiceChip(title: "\(c.title) \(all.filter(\.unlocked).count)/\(all.count)",
                                       symbol: c.symbol, selected: filter == c) {
                                filter = filter == c ? nil : c
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                ForEach(AchievementCategory.allCases.filter { filter == nil || $0 == filter }) { category in
                    let items = shown.filter { $0.def.category == category }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(category.title).font(Typo.display(19))
                                Spacer()
                                Text("\(items.filter(\.unlocked).count) / \(items.count)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 18) {
                                ForEach(items) { r in
                                    MedalCell(result: r, date: center.unlockDate(r))
                                        .onTapGesture { selected = r }
                                }
                            }
                        }
                        .padding(18)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 12)
            .animation(.snappy, value: filter)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("成就馆")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { r in
            AchievementDetailSheet(result: r, date: center.unlockDate(r))
        }
        .onAppear { center.refresh(context: context) }
    }
}

struct MedalCell: View {
    let result: AchievementResult
    let date: Date?

    private var hidden: Bool { result.def.secret && !result.unlocked }

    var body: some View {
        VStack(spacing: 8) {
            MedalView(symbol: result.def.symbol, tier: result.def.tier, unlocked: result.unlocked,
                      secret: result.def.secret, progress: result.progress, size: 64)
            Text(hidden ? "隐藏成就" : result.def.title)
                .font(.footnote.weight(result.unlocked ? .semibold : .regular))
                .foregroundStyle(result.unlocked ? Color.primary : Color.secondary)
                .lineLimit(1)
            Group {
                if result.unlocked {
                    Text(date.map { Fmt.shortDate($0) } ?? result.def.tier.title)
                } else if hidden {
                    Text("???")
                } else {
                    Text("\(min(result.current, result.target)) / \(result.target)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct AchievementDetailSheet: View {
    let result: AchievementResult
    let date: Date?

    @Environment(\.dismiss) private var dismiss

    private var hidden: Bool { result.def.secret && !result.unlocked }

    var body: some View {
        VStack(spacing: 18) {
            MedalView(symbol: result.def.symbol, tier: result.def.tier, unlocked: result.unlocked,
                      secret: result.def.secret, progress: result.progress, size: 132, shine: result.unlocked)
                .padding(.top, 28)
            VStack(spacing: 8) {
                Text(hidden ? "隐藏成就" : result.def.title)
                    .font(Typo.display(28))
                Text(hidden ? "满足某个特别的条件后揭晓" : result.def.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Badge(text: result.def.tier.title, color: Palette.gold)
                Badge(text: "+\(result.def.tier.points) 魅力值", color: .accentColor)
                Badge(text: result.def.category.title, color: .secondary)
            }
            if result.unlocked {
                Label(date.map { "解锁于 \(Fmt.date($0))" } ?? "已解锁", systemImage: "checkmark.seal")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.gold)
            } else if !hidden {
                VStack(spacing: 6) {
                    ProgressView(value: result.progress)
                        .tint(Palette.gold)
                        .frame(maxWidth: 220)
                    Text("进度 \(min(result.current, result.target)) / \(result.target)，还差 \(result.remaining)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            Button("完成") { dismiss() }
                .font(.body.weight(.semibold))
                .padding(.bottom, 12)
                .accessibilityIdentifier("closeAchievement")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .composerSheet(detents: [.medium])
    }
}
