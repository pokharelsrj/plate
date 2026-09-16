import SwiftUI
import Observation

enum AppTab: Hashable {
    case today, calendar, workout, body, finance, settings
}

@Observable
final class Router {
    var tab: AppTab = .today

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PI_TEST_TAB"] == "finance" { tab = .finance }
        #endif
    }
}

struct RootView: View {
    @Environment(Session.self) private var session
    @State private var router = Router()

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "house.fill") }
                .tag(AppTab.today)
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)
            WorkoutView()
                .tabItem { Label("Workout", systemImage: "dumbbell.fill") }
                .tag(AppTab.workout)
            BodyView()
                .tabItem { Label("Body", systemImage: "figure.arms.open") }
                .tag(AppTab.body)
            FinanceView()
                .tabItem { Label("Finance", systemImage: "creditcard.fill") }
                .tag(AppTab.finance)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .environment(router)
        .task {
            await session.refreshProfile()
        }
    }
}
