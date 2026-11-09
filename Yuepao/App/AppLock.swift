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

    static var lockEnabled: Bool {
        if TestSupport.isUITesting { return false }
        return UserDefaults.standard.object(forKey: "lockEnabled") as? Bool ?? true
    }
    static var lockDelay: TimeInterval { UserDefaults.standard.double(forKey: "lockDelay") }

    static var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
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
    static var previewLock: Bool { ProcessInfo.processInfo.arguments.contains("-previewLock") }

    private init() {
        isLocked = Self.previewLock || (Self.lockEnabled && Self.canAuthenticate)
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
            if isLocked, shouldAutoPrompt {
                authenticate()
            }
        default:
            break
        }
    }

    func authenticate() {
        guard isLocked, !isAuthenticating else { return }
        shouldAutoPrompt = false
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
