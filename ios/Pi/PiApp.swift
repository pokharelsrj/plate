import SwiftUI
import UIKit

/// Registers background work during launch: the BGTaskScheduler full-sync task
/// (which must be registered before launch finishes) and HealthKit background
/// delivery so new samples push automatically even when the app is closed.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        HealthBackgroundTasks.shared.register()
        Task { @MainActor in HealthService.shared.startBackgroundDelivery() }
        return true
    }
}

@main
struct PiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("themePreference") private var themePreference = "system"
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = Session()
    @State private var appLock = AppLock()

    private var preferredColorScheme: ColorScheme? {
        switch themePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if session.isAuthenticated {
                        RootView()
                    } else {
                        LoginView()
                    }
                }
                if appLock.isLocked {
                    LockScreenView {
                        Task { await appLock.unlock() }
                    }
                    .transition(.opacity)
                }
            }
            .environment(session)
            .environment(appLock)
            .preferredColorScheme(preferredColorScheme)
            .tint(.piPrimary)
            .task {
                WatchRelay.shared.session = session
                WatchRelay.shared.activate()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    appLock.lockIfEnabled()
                case .active:
                    if appLock.isLocked {
                        Task { await appLock.unlock() }
                    }
                default:
                    break
                }
            }
        }
    }
}
