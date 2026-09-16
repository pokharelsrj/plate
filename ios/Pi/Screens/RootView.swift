import SwiftUI
import Observation

enum AppTab: Hashable {
    case today, calendar, workout, body, settings
}

@Observable
final class Router {
    var tab: AppTab = .today
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
