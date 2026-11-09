import SwiftUI

/// 小窗口（备忘、礼物、纪念日、经期、待办）共用的组件

/// 可选中的胶囊
struct ChoiceChip: View {
    let title: String
    var symbol: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { action() }
        } label: {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.caption)
                }
                Text(title)
            }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background {
                if selected {
                    Capsule().fill(Palette.wineGradient)
                } else {
                    Capsule().fill(Palette.fill)
                }
            }
            .overlay {
                if !selected { Capsule().stroke(Palette.hairline, lineWidth: 0.5) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.chip)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// 一行可横向滚动的胶囊
struct ChipRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .padding(.horizontal, -20)
    }
}

/// 小节标题
struct ComposerLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .eyebrow()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// 输入框的圆角底
    func composerField() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.fill))
    }
}

/// 小窗口的外壳：标题 + 取消 / 保存
struct ComposerShell<Content: View>: View {
    let title: String
    var saveTitle = "保存"
    var canSave = true
    var saveIdentifier: String?
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        Haptics.success()
                        onSave()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                    .accessibilityIdentifier(saveIdentifier ?? "composerSave")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { hideKeyboard() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

/// 日期快捷选择：今天 / 明天 / 周末 / 自选
enum QuickDay: CaseIterable, Identifiable {
    case today, tomorrow, weekend, nextWeek

    var id: Self { self }

    var title: String {
        switch self {
        case .today: return "今天"
        case .tomorrow: return "明天"
        case .weekend: return "周末"
        case .nextWeek: return "下周"
        }
    }

    var date: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch self {
        case .today:
            return today
        case .tomorrow:
            return cal.date(byAdding: .day, value: 1, to: today) ?? today
        case .weekend:
            // 下一个周六（今天是周六就今天）
            let weekday = cal.component(.weekday, from: today)
            let delta = (7 - weekday + 7) % 7
            return cal.date(byAdding: .day, value: delta, to: today) ?? today
        case .nextWeek:
            let weekday = cal.component(.weekday, from: today)
            let delta = ((9 - weekday) % 7) + (weekday == 2 ? 7 : 0)
            return cal.date(byAdding: .day, value: delta == 0 ? 7 : delta, to: today) ?? today
        }
    }

    func matches(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: self.date)
    }
}
