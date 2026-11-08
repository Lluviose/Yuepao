import SwiftUI
import SwiftData

@main
struct YuepaoApp: App {
    private let container: ModelContainer

    init() {
        container = Persistence.makeContainer()
        TestSupport.seedIfNeeded(container.mainContext)
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

    var body: some View {
        ZStack {
            MainTabView()
            if lock.isLocked {
                LockScreen()
                    .transition(.opacity)
            } else if scenePhase != .active {
                PrivacyCover()
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
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            GirlListView()
                .tabItem { Label("后宫", systemImage: "person.2.fill") }
            EncounterListView()
                .tabItem { Label("记录", systemImage: "heart.text.square.fill") }
            HaremMapScreen()
                .tabItem { Label("地图", systemImage: "map.fill") }
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}
