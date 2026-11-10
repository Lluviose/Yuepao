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

    /// FNV-1a 哈希，让相似的名字（比如「小美」「小雨」）也能分到不同色调
    private static func tone(for name: String) -> (top: (Double, Double, Double), bottom: (Double, Double, Double)) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return avatarTones[Int(hash % UInt64(avatarTones.count))]
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

    /// UIKit 里用的主色（酒红），跟随深浅色
    static let wineUI = UIColor(named: "AccentColor") ?? UIColor(red: 0.616, green: 0.204, blue: 0.302, alpha: 1)

    // MARK: 纸面

    /// 页面底色：浅色用带一点暖意的纸色（系统默认的灰偏蓝，和酒红、香槟金不搭），
    /// 深色沿用系统的底色，弹出的页面会自动亮一级
    static let canvas = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.systemGroupedBackground.resolvedColor(with: trait)
            : UIColor(red: 0.961, green: 0.949, blue: 0.929, alpha: 1)
    })

    /// 卡片底色：和系统分组列表的行一致，自己画的卡片和列表行放在一起不会有色差
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)

    /// 胶囊、输入格、进度槽的中性底：比系统的灰暖一点
    static let fill = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.52, green: 0.48, blue: 0.49, alpha: 0.24)
            : UIColor(red: 0.47, green: 0.42, blue: 0.40, alpha: 0.12)
    })

    // MARK: 酒红

    /// 主按钮的底：深浅色下都是同一种酒红，白字始终看得清
    static let wineTop = Color(red: 0.69, green: 0.26, blue: 0.36)
    static let wineBottom = Color(red: 0.53, green: 0.16, blue: 0.26)

    static var wineGradient: LinearGradient {
        LinearGradient(colors: [wineTop, wineBottom], startPoint: .top, endPoint: .bottom)
    }
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

/// 小图标：圆底染上一点图形本身的颜色，中性色的图标还是灰底
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.12)))
    }
}

/// 详情页顶部的快捷按钮：中性底色、细图标；最主要的那个用酒红实底
struct QuickAction: View {
    let title: String
    let symbol: String
    var tint: Color = .primary
    /// 主要操作：酒红渐变底、白色图形
    var prominent = false
    let action: () -> Void

    @State private var bounce = 0

    var body: some View {
        Button {
            bounce += 1
            action()
        } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: prominent ? .semibold : .regular))
                    .symbolEffect(.bounce, value: bounce)
                    .foregroundStyle(prominent ? Color.white : tint)
                    .frame(width: 50, height: 50)
                    .background {
                        if prominent {
                            Circle()
                                .fill(Palette.wineGradient)
                                .shadow(color: Palette.wineBottom.opacity(0.3), radius: 8, y: 4)
                        } else {
                            Circle().fill(.thinMaterial)
                        }
                    }
                    .overlay(Circle().stroke(prominent ? Color.white.opacity(0.18) : Palette.hairline, lineWidth: 0.5))
                Text(title)
                    .font(.caption2.weight(prominent ? .semibold : .medium))
                    .foregroundStyle(prominent ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.impact(weight: .light), trigger: bounce)
    }
}

/// 和 QuickAction 一个样子，点开是一个菜单：放不常用的几种记录
struct QuickMenu<Items: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu {
            items()
        } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.primary)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(.thinMaterial))
                    .overlay(Circle().stroke(Palette.hairline, lineWidth: 0.5))
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
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

/// 浮在地图等内容上方的控件：iOS 26 用液态玻璃，低版本用毛玻璃 + 细描边 + 阴影
extension View {
    @ViewBuilder
    func floatingGlass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            let glass: Glass = interactive ? Glass.regular.interactive() : Glass.regular
            self.glassEffect(glass, in: shape)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Palette.hairline, lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.12), radius: 10, y: 3)
        }
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

/// 胶囊、选择块、计数按钮按下去时轻轻缩一下，松手弹回
struct ChipPressStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ChipPressStyle {
    static var chip: ChipPressStyle { ChipPressStyle() }
}

// MARK: - 纸面底色

extension View {
    /// 列表和表单的底色换成纸色（自己排版的页面直接用 `Palette.canvas` 做背景）
    func paperBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
    }
}

// MARK: - 按钮

/// 主按钮：酒红渐变的胶囊、白字。一个页面里最主要的那个操作用它
struct PrimaryButtonStyle: ButtonStyle {
    /// 撑满可用宽度
    var fill = false
    /// 底下带一圈酒红色的柔光；放在列表行里会被裁掉，就关掉
    var glow = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .frame(maxWidth: fill ? .infinity : nil)
            .background(Capsule().fill(Palette.wineGradient))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
            .shadow(color: Palette.wineBottom.opacity(glow ? (configuration.isPressed ? 0.12 : 0.3) : 0),
                    radius: 10, y: 5)
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

/// 次要按钮：卡片底色、主题色的字和细描边，和主按钮并排时不抢戏
struct SoftButtonStyle: ButtonStyle {
    var fill = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .frame(maxWidth: fill ? .infinity : nil)
            .background(Capsule().fill(Palette.surface))
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var wine: PrimaryButtonStyle { PrimaryButtonStyle() }

    static func wine(fill: Bool, glow: Bool = true) -> PrimaryButtonStyle {
        PrimaryButtonStyle(fill: fill, glow: glow)
    }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var quiet: SoftButtonStyle { SoftButtonStyle() }

    static func quiet(fill: Bool) -> SoftButtonStyle {
        SoftButtonStyle(fill: fill)
    }
}
