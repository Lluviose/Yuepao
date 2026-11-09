import SwiftUI
import UIKit

/// 统一的配色
enum Palette {
    static let period = Color(red: 0.93, green: 0.30, blue: 0.38)
    static let fertile = Color(red: 0.98, green: 0.62, blue: 0.22)
    static let encounter = Color.accentColor
    static let todo = Color(red: 0.25, green: 0.52, blue: 0.96)
    static let date = Color(red: 0.97, green: 0.55, blue: 0.20)
    static let memo = Color(red: 0.45, green: 0.45, blue: 0.85)
    static let gift = Color(red: 0.85, green: 0.38, blue: 0.75)
    static let status = Color(red: 0.35, green: 0.65, blue: 0.55)

    /// 根据名字生成稳定的柔和渐变，用于没有头像时
    static func avatarGradient(for name: String) -> LinearGradient {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let hue = Double(abs(sum) % 360) / 360
        let top = Color(hue: hue, saturation: 0.38, brightness: 0.96)
        let bottom = Color(hue: (hue + 0.06).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.82)
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func avatarUIColors(for name: String) -> (UIColor, UIColor) {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let hue = CGFloat(abs(sum) % 360) / 360
        return (UIColor(hue: hue, saturation: 0.38, brightness: 0.96, alpha: 1),
                UIColor(hue: (hue + 0.06).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.82, alpha: 1))
    }
}

extension View {
    /// 统计数字：圆体 + 数字滚动动画
    func statNumber() -> some View {
        self
            .fontDesign(.rounded)
            .monospacedDigit()
            .contentTransition(.numericText())
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

/// 圆形图标（时间线、日程里用）
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: Circle())
    }
}

/// 详情页顶部的圆形快捷按钮
struct QuickAction: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    let action: () -> Void

    @State private var bounce = 0

    var body: some View {
        Button {
            bounce += 1
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolEffect(.bounce, value: bounce)
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.12), in: Circle())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.impact(weight: .light), trigger: bounce)
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
