import SwiftUI
import SwiftData

@main
struct YuepaoApp: App {
    private let container: ModelContainer

    init() {
        Self.configureNavigationBar()
        container = Persistence.makeContainer()
        // 上次播放视频、导入、打包备份留下的明文临时文件
        MediaStore.shared.purgeTemporary()
        if Persistence.loadError == nil {
            DataMigrations.run(container.mainContext)
            TestSupport.seedIfNeeded(container.mainContext)
        }
    }

    /// 导航栏标题用衬线字体（New York）
    private static func configureNavigationBar() {
        func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
            return UIFont(descriptor: descriptor, size: size)
        }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: serif(34, .bold)]
        bar.titleTextAttributes = [.font: serif(17, .semibold)]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @State private var persistenceError = Persistence.loadError

    var body: some View {
        ZStack {
            if let error = persistenceError {
                ContentUnavailableView {
                    Label("暂时无法打开数据", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("为保护已有记录，已暂停编辑。请释放存储空间后重新打开应用。\n\n\(error)")
                }
            } else {
                MainTabView()
            }
            CelebrationLayer()
                .zIndex(1.5)
        }
        .background { SecurityLifecycle() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("persistenceUnavailable"))) { _ in
            persistenceError = Persistence.loadError
        }
        .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
    }
}

/// 成就和锁的变化只刷新这一层，不重算承载编辑弹窗的主内容。
private struct CelebrationLayer: View {
    @ObservedObject private var lock = AppLock.shared
    @ObservedObject private var achievements = AchievementCenter.shared

    var body: some View {
        ZStack {
            if let current = achievements.celebrating.first, !lock.isLocked {
                CelebrationView(result: current) {
                    achievements.dismissCelebration()
                }
                .id(current.id)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }
}

/// 将安全生命周期放在稳定的独立子视图中；隐私遮罩只由顶层 UIWindow 呈现。
private struct SecurityLifecycle: View {
    @ObservedObject private var lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var girls: [Girl]

    var body: some View {
        Color.clear
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: scenePhase) { _, phase in
            lock.handle(phase)
            updateShield(phase)
            if phase == .active, Persistence.loadError == nil {
                Reminders.rescheduleDates(girls: girls)
                AchievementCenter.shared.refresh(context: context)
            }
        }
        .onChange(of: lock.isLocked) { _, _ in
            updateShield(scenePhase)
        }
        .onAppear {
            // 同步先盖住首屏（包括 previewLock），再启动认证和其他刷新。
            updateShield(scenePhase)
            if scenePhase == .active { lock.handle(.active) }
            updateShield(scenePhase)
            if Persistence.loadError == nil { AchievementCenter.shared.refresh(context: context) }
        }
    }

    private func updateShield(_ phase: ScenePhase) {
        PrivacyShield.shared.update(locked: lock.isLocked, covered: phase != .active)
    }
}

struct MainTabView: View {
    @SceneStorage("selectedTab") private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            GirlListView()
                .tabItem { Label("后宫", systemImage: "person.2.fill") }
                .tag(0)
            EncounterListView()
                .tabItem { Label("记录", systemImage: "heart.text.square.fill") }
                .tag(1)
            AgendaScreen()
                .tabItem { Label("日程", systemImage: "calendar") }
                .tag(2)
            HaremMapScreen()
                .tabItem { Label("地图", systemImage: "map.fill") }
                .tag(3)
            HubView()
                .tabItem { Label("成就", systemImage: "rosette") }
                .tag(4)
        }
        .sensoryFeedback(.selection, trigger: tab)
    }
}
