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

    private init() {
        isLocked = Self.lockEnabled && Self.canAuthenticate
    }

    func handle(_ phase: ScenePhase) {
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
                VStack(spacing: 6) {
                    Text("手账")
                        .font(.title2.weight(.semibold))
                        .fontDesign(.rounded)
                    Label("已锁定", systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, options: .repeating)
                }
                .opacity(appeared ? 1 : 0)
                Spacer()
                Button {
                    lock.authenticate()
                } label: {
                    Label("使用\(AppLock.biometryName)解锁", systemImage: "faceid")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: 280)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
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
            Color(uiColor: .systemBackground)
            RadialGradient(colors: [Color.accentColor.opacity(0.18), .clear],
                           center: .top, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color.orange.opacity(0.10), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

/// 和 App 图标一致的笔记本图形
struct BrandGlyph: View {
    var size: CGFloat = 80

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.38, blue: 0.47),
                                          Color(red: 0.96, green: 0.63, blue: 0.47)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color.accentColor.opacity(0.35), radius: size * 0.2, y: size * 0.08)
    }
}
