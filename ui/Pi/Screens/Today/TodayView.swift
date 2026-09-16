import SwiftUI
import WidgetKit

struct TodayView: View {
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router

    @State private var snapshot: TodaySnapshot?
    @State private var error: String?
    @State private var lastRefresh: Date?

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = session.user?.displayName?.split(separator: " ").first.map(String.init)
        let base: String
        switch hour {
        case 5..<12: base = "Good morning"
        case 12..<17: base = "Good afternoon"
        default: base = "Good evening"
        }
        return name.map { "\(base), \($0)" } ?? base
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LoadableView(value: snapshot, error: error, retry: { Task { await load() } }) { snap in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(PiDate.longLabel(snap.date))
                                .font(.piSubheadline)
                                .foregroundStyle(Color.piTextMuted)
                            Spacer()
                            if let lastRefresh {
                                Text("Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                                    .font(.piCaption)
                                    .foregroundStyle(Color.piTextMuted)
                            }
                        }
                        DaySnapshotCards(snapshot: snap, router: router)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.piBg)
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        TrendsView()
                    } label: {
                        Image(systemName: "chart.xyaxis.line")
                    }
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            let snap = try await session.client.today()
            snapshot = snap
            lastRefresh = Date()
            error = nil
            SharedCache.write(snap)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            if snapshot == nil {
                self.error = error.localizedDescription
            }
        }
    }
}
