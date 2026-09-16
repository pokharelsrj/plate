import SwiftUI

struct DayDetailView: View {
    @Environment(Session.self) private var session
    let date: String

    @State private var snapshot: TodaySnapshot?
    @State private var error: String?
    @State private var syncing = false
    @State private var toast: Toast?

    var body: some View {
        ScrollView {
            LoadableView(value: snapshot, error: error, retry: { Task { await load() } }) { snap in
                DaySnapshotCards(snapshot: snap)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .background(Color.piBg)
        .navigationTitle(PiDate.longLabel(date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if HealthService.isAvailable {
                        Button {
                            Task { await syncAppleHealth() }
                        } label: {
                            Label("Apple Health (this day)", systemImage: "heart")
                        }
                    }
                    Button {
                        Task { await triggerServerSync("healthifyme") }
                    } label: {
                        Label("HealthifyMe", systemImage: "fork.knife")
                    }
                    Button {
                        Task { await triggerServerSync("lafitness") }
                    } label: {
                        Label("LA Fitness", systemImage: "figure.run")
                    }
                } label: {
                    if syncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(syncing)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .toast($toast)
    }

    private func load() async {
        do {
            snapshot = try await session.client.day(date)
            error = nil
        } catch {
            if snapshot == nil { self.error = error.localizedDescription }
        }
    }

    /// Days-back window that covers this date (server syncs sync the last N days).
    private var daysBackCoveringThisDate: Int {
        guard let d = PiDate.parseDay(date) else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: d),
                                                   to: Calendar.current.startOfDay(for: Date())).day ?? 0
        return max(days + 1, 1)
    }

    private func syncAppleHealth() async {
        guard let d = PiDate.parseDay(date) else { return }
        syncing = true
        defer { syncing = false }
        do {
            try await HealthService.shared.requestAuthorization()
            try await HealthService.shared.syncDay(d, client: session.client)
            toast = Toast(message: "Apple Health synced for this day")
            await load()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func triggerServerSync(_ source: String) async {
        syncing = true
        defer { syncing = false }
        do {
            try await session.client.triggerSync(source: source, days: daysBackCoveringThisDate)
            toast = Toast(message: "Sync started — pull to refresh in a moment")
            try? await Task.sleep(for: .seconds(3))
            await load()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}
