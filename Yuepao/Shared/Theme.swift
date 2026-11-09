import SwiftUI
import UIKit

/// 统一的配色：酒红为主色，香槟金点缀，其余尽量中性、低饱和，
/// 只有带含义的地方（经期、易孕期）才用颜色。
enum Palette {
    static let gold = Color(red: 0.72, green: 0.58, blue: 0.40)
    static let period = Color(red: 0.76, green: 0.26, blue: 0.31)
    static let fertile = Color(red: 0.80, green: 0.55, blue: 0.27)
    static let encounter = Color.accentColor
    static let todo = Color(red: 0.33, green: 0.43, blue: 0.56)
    static let date = gold
    static let memo = Color(red: 0.45, green: 0.47, blue: 0.52)
    static let gift = Color(red: 0.60, green: 0.43, blue: 0.56)
    static let status = Color(red: 0.42, green: 0.53, blue: 0.45)

    /// 没有头像时的底色：一组精挑过的低饱和色，不用随机彩虹色
    private static let avatarTones: [(top: (Double, Double, Double), bottom: (Double, Double, Double))] = [
        ((0.85, 0.72, 0.73), (0.66, 0.50, 0.53)),   // 灰玫瑰
        ((0.74, 0.78, 0.71), (0.53, 0.60, 0.52)),   // 鼠尾草
        ((0.87, 0.81, 0.72), (0.70, 0.61, 0.49)),   // 砂岩
        ((0.72, 0.76, 0.81), (0.50, 0.56, 0.65)),   // 石板蓝
        ((0.79, 0.72, 0.80), (0.58, 0.49, 0.61)),   // 藕荷
        ((0.85, 0.74, 0.66), (0.66, 0.52, 0.44)),   // 陶土
        ((0.78, 0.76, 0.73), (0.56, 0.54, 0.51))    // 暖灰
    ]

    private static func tone(for name: String) -> (top: (Double, Double, Double), bottom: (Double, Double, Double)) {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return avatarTones[abs(sum) % avatarTones.count]
    }

    static func avatarGradient(for name: String) -> LinearGradient {
        let t = tone(for: name)
        return LinearGradient(colors: [Color(red: t.top.0, green: t.top.1, blue: t.top.2),
                                       Color(red: t.bottom.0, green: t.bottom.1, blue: t.bottom.2)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func avatarUIColors(for name: String) -> (UIColor, UIColor) {
        let t = tone(for: name)
        return (UIColor(red: t.top.0, green: t.top.1, blue: t.top.2, alpha: 1),
                UIColor(red: t.bottom.0, green: t.bottom.1, blue: t.bottom.2, alpha: 1))
    }

    /// 卡片上的细描边
    static let hairline = Color.primary.opacity(0.08)
}

/// 字体：标题和大数字用衬线（New York），正文用系统字体
enum Typo {
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension View {
    /// 统计数字：衬线数字 + 滚动动画
    func statNumber() -> some View {
        self
            .fontDesign(.serif)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    /// 小节标题：小号、加宽字距
    func eyebrow() -> some View {
        self
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    /// iOS 18 起的缩放转场，低版本直接忽略
    @ViewBuilder
    func zoomSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomDestination<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

/// 小图标：细线条的中性圆底，图形本身带一点颜色
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(uiColor: .tertiarySystemFill)))
    }
}

/// 详情页顶部的快捷按钮：中性底色、细图标
struct QuickAction: View {
    let title: String
    let symbol: String
    var tint: Color = .primary
    let action: () -> Void

    @State private var bounce = 0

    var body: some View {
        Button {
            bounce += 1
            action()
        } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .symbolEffect(.bounce, value: bounce)
                    .foregroundStyle(tint)
                    .frame(width: 50, height: 50)
                    .background(.thinMaterial, in: Circle())
                    .overlay(Circle().stroke(Palette.hairline, lineWidth: 0.5))
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.impact(weight: .light), trigger: bounce)
    }
}

/// 提醒 / 风险提示卡片：左侧色条 + 图标 + 文本
struct Callout: View {
    let symbol: String
    let tint: Color
    let title: String
    var message: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule()
                .fill(tint)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }
}

/// 半屏小窗口的统一样式
extension View {
    func composerSheet(detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        self
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(.regularMaterial)
    }
}

/// 触感反馈（视图马上关闭时也能触发）
@MainActor
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

@MainActor
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// 外观：跟随系统 / 浅色 / 深色
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension View {
    /// 表单通用：滚动时收起键盘，键盘上方加「完成」
    func formKeyboardHandling() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { hideKeyboard() }
                        .fontWeight(.semibold)
                }
            }
    }
}
