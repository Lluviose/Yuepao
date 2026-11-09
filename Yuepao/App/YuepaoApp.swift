import SwiftUI
import SwiftData

@main
struct YuepaoApp: App {
    private let container: ModelContainer

    init() {
        Self.configureNavigationBar()
        container = Persistence.makeContainer()
        TestSupport.seedIfNeeded(container.mainContext)
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
    @ObservedObject private var lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase
    @Query private var girls: [Girl]
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue

    var body: some View {
        ZStack {
            MainTabView()
            if lock.isLocked {
                LockScreen()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(2)
            } else if scenePhase != .active {
                PrivacyCover()
                    .zIndex(1)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            lock.handle(phase)
            if phase == .active {
                Reminders.rescheduleDates(girls: girls)
            }
        }
        .onAppear {
            if scenePhase == .active { lock.handle(.active) }
        }
        .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
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
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
                .tag(4)
        }
        .sensoryFeedback(.selection, trigger: tab)
    }
}
