import SwiftUI

@main
struct PiWatchApp: App {
    init() {
        WatchAPI.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
        }
    }
}
