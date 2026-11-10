import SwiftUI

/// 长表单（建档、记一次）共用的两样东西：顶上的分区索引，和输入框下面「以前填过的」

struct FormRailItem: Identifiable, Equatable {
    let id: String
    let title: String
    let filled: Bool
}

/// 固定在导航栏下面的一排小胶囊：点一下滚到那一块。
/// 填过的带实心点，没填的是空心圈，表单再长也能一眼看出记到哪了
struct FormRail: View {
    let items: [FormRailItem]
    let onSelect: (String) -> Void

    @State private var taps = 0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // 用标题当身份：表单里的卡片也用分区 id 做 .id()，两边同名的话 scrollTo 会认错
                ForEach(items, id: \.title) { item in
                    Button {
                        taps += 1
                        onSelect(item.id)
                    } label: {
                        HStack(spacing: 5) {
                            // 填上的那一刻，小点从空心圈长成实心
                            Circle()
                                .fill(item.filled ? Color.accentColor : Color.clear)
                                .overlay(Circle().strokeBorder(Color.secondary.opacity(item.filled ? 0 : 0.5), lineWidth: 1))
                                .frame(width: 6, height: 6)
                                .scaleEffect(item.filled ? 1.15 : 0.9)
                            Text(item.title)
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(item.filled ? Color.primary : Color.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Palette.surface))
                        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 0.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.chip)
                    .accessibilityLabel(item.filled ? "\(item.title)，已填" : "\(item.title)，还没填")
                    .accessibilityIdentifier("rail-\(item.id)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 9)
            .animation(.snappy(duration: 0.25), value: items)
        }
        // 底色一直铺到导航栏后面，表单内容从这条下面滚过去时不会露出来
        .background(Palette.canvas, ignoresSafeAreaEdges: .top)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 0.5)
        }
        .sensoryFeedback(.selection, trigger: taps)
    }
}

/// 输入框下面的一排「以前填过的」，点一下直接填进去
struct SuggestionChips: View {
    let items: [String]
    let onPick: (String) -> Void

    var body: some View {
        ScrollChips(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button {
                    onPick(item)
                } label: {
                    Text(item)
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.chip)
            }
        }
    }
}
