import SwiftUI
import LocalAuthentication

/// Face ID / 密码锁
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    @Published private(set) var isLocked: Bool
    private var backgroundedAt: Date?
    private var isAuthenticating = false
    /// 只在启动和从后台回来时自动弹 Face ID，失败/取消后不再自动弹（避免死循环）
    private var shouldAutoPrompt = true

    /// 用真实的前后台切换测试遮罩；只在 Debug UI 测试中模拟认证。
    private static var testsBackgroundLock: Bool {
        #if DEBUG
        return TestSupport.isUITesting && ProcessInfo.processInfo.arguments.contains("-testBackgroundLock")
        #else
        return false
        #endif
    }

    static var lockEnabled: Bool {
        #if DEBUG
        if TestSupport.isUITesting { return testsBackgroundLock }
        #endif
        return UserDefaults.standard.object(forKey: "lockEnabled") as? Bool ?? true
    }
    static var lockDelay: TimeInterval {
        testsBackgroundLock ? 0 : UserDefaults.standard.double(forKey: "lockDelay")
    }

    static var canAuthenticate: Bool {
        if testsBackgroundLock { return true }
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "面容 ID"
        case .touchID: return "触控 ID"
        default: return "设备密码"
        }
    }

    static var biometrySymbol: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.open"
        }
    }

    /// UI 测试截锁屏用
    static var previewLock: Bool {
        #if DEBUG
        return TestSupport.isUITesting && ProcessInfo.processInfo.arguments.contains("-previewLock")
        #else
        return false
        #endif
    }

    private init() {
        isLocked = Self.previewLock || (!Self.testsBackgroundLock && Self.lockEnabled && Self.canAuthenticate)
    }

    func handle(_ phase: ScenePhase) {
        guard !Self.previewLock else { return }
        switch phase {
        case .background:
            if backgroundedAt == nil { backgroundedAt = Date() }
        case .active:
            if let since = backgroundedAt {
                backgroundedAt = nil
                if Self.lockEnabled, Self.canAuthenticate, Date().timeIntervalSince(since) >= Self.lockDelay {
                    isLocked = true
                    shouldAutoPrompt = true
                }
            }
            if isLocked, shouldAutoPrompt, !Self.testsBackgroundLock {
                authenticate()
            }
        default:
            break
        }
    }

    func authenticate() {
        guard isLocked, !isAuthenticating else { return }
        shouldAutoPrompt = false
        #if DEBUG
        if Self.testsBackgroundLock {
            withAnimation(.easeOut(duration: 0.2)) { isLocked = false }
            return
        }
        #endif
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // 设备没设密码时无法上锁
            isLocked = false
            return
        }
        isAuthenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁以查看内容") { success, error in
            let code = (error as? LAError)?.code
            Task { @MainActor in
                AppLock.shared.finishAuthentication(success: success, errorCode: code)
            }
        }
    }

    private func finishAuthentication(success: Bool, errorCode: LAError.Code?) {
        isAuthenticating = false
        if success {
            withAnimation(.easeOut(duration: 0.2)) { isLocked = false }
            return
        }
        // 被系统打断（比如还没完全进入前台），下次回到前台时再自动弹
        if let errorCode, [.systemCancel, .appCancel, .notInteractive].contains(errorCode) {
            shouldAutoPrompt = true
        }
    }

    func lockNow() {
        guard Self.lockEnabled, Self.canAuthenticate else { return }
        isLocked = true
    }
}

struct LockScreen: View {
    @ObservedObject var lock = AppLock.shared
    @State private var appeared = false

    var body: some View {
        ZStack {
            BrandBackground()
            VStack(spacing: 22) {
                Spacer()
                BrandGlyph(size: 84)
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)
                VStack(spacing: 10) {
                    Text("手账")
                        .font(Typo.display(30))
                    Capsule()
                        .fill(Palette.gold.opacity(0.8))
                        .frame(width: 26, height: 1.5)
                    Label("已锁定", systemImage: "lock.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .opacity(appeared ? 1 : 0)
                Spacer()
                Button {
                    lock.authenticate()
                } label: {
                    Label("使用\(AppLock.biometryName)解锁", systemImage: AppLock.biometrySymbol)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: 230)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.wine)
                .accessibilityIdentifier("unlockApp")
                .padding(.bottom, 48)
                .opacity(appeared ? 1 : 0)
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) { appeared = true }
        }
    }
}

/// 锁屏和后台遮罩放在一个最上层的单独窗口里。
/// 这样在「记一次」之类的弹窗里、或者全屏看照片视频时切到后台，内容也一样会被盖住，
/// 回来时要先解锁才能看到
@MainActor
final class PrivacyShield {
    static let shared = PrivacyShield()

    private let state = ShieldState()
    private var window: UIWindow?
    private weak var previousKeyWindow: UIWindow?
    private var presentationGeneration = 0

    func update(locked: Bool, covered: Bool) {
        state.locked = locked
        if locked || covered {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        // 只让当前输入结束，再由遮罩接管焦点，避免底层 SwiftUI 焦点重新拉起键盘。
        hideKeyboard()
        if let window {
            window.makeKeyAndVisible()
            return
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        // 淡出期间再次显示时，保留最初的内容窗口，不能把旧遮罩记成恢复目标。
        if previousKeyWindow == nil {
            previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
                ?? scene.windows.first { $0.windowLevel == .normal && $0.rootViewController != nil }
        }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        window.overrideUserInterfaceStyle = Self.interfaceStyle
        let host = UIHostingController(rootView: ShieldView(state: state))
        host.view.backgroundColor = .clear
        // 遮住时辅助功能也只访问这个窗口，不能读到下面的敏感内容。
        host.view.accessibilityViewIsModal = true
        window.rootViewController = host
        presentationGeneration += 1
        self.window = window
        window.makeKeyAndVisible()
    }

    /// 淡出后收起。淡出途中又要显示时会新建一个窗口，不受影响
    private func hide() {
        guard let window else { return }
        self.window = nil
        let generation = presentationGeneration
        UIView.animate(withDuration: 0.2, animations: {
            window.alpha = 0
        }, completion: { [weak self] _ in
            window.isHidden = true
            guard let self, self.window == nil, self.presentationGeneration == generation else { return }
            self.previousKeyWindow?.makeKey()
            self.previousKeyWindow = nil
        })
    }

    private static var interfaceStyle: UIUserInterfaceStyle {
        switch AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

final class ShieldState: ObservableObject {
    @Published var locked = false
}

private struct ShieldView: View {
    @ObservedObject var state: ShieldState

    var body: some View {
        ZStack {
            if state.locked {
                LockScreen()
                    .transition(.opacity)
            } else {
                PrivacyCover()
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("privacyShield")
        .animation(.easeOut(duration: 0.2), value: state.locked)
    }
}

/// 进入多任务界面时盖住内容
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            BrandBackground()
            BrandGlyph(size: 72)
        }
    }
}

struct BrandBackground: View {
    var body: some View {
        ZStack {
            Palette.canvas
            RadialGradient(colors: [Color.accentColor.opacity(0.16), .clear],
                           center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 460)
            LinearGradient(colors: [.clear, Palette.gold.opacity(0.1)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

/// App 图标本身（皮面手账），锁屏和遮罩上用
struct BrandGlyph: View {
    var size: CGFloat = 80

    var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.28), radius: size * 0.22, y: size * 0.12)
    }
}
