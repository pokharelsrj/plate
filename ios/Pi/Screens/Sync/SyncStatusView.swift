import SwiftUI

struct SyncStatusView: View {
    @Environment(Session.self) private var session

    @State private var data: SyncStatusResponse?
    @State private var error: String?
    @State private var triggering: Set<String> = []
    @State private var toast: Toast?

    var body: some View {
        ScrollView {
            LoadableView(value: data, error: error, retry: { Task { await load() } }) { status in
                VStack(spacing: 14) {
                    ForEach(status.sources) { source in
                        sourceCard(source)
                    }
                    recentRuns(status.recentRuns)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color.piBg)
        .navigationTitle("Sync")
        .task { await load() }
        .refreshable { await load() }
        .toast($toast)
    }

    private func sourceCard(_ source: SyncStatusResponse.SyncSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(displayName(source.name))
                    .font(.piTitle2)
                    .foregroundStyle(Color.piText)
                Spacer()
                if source.running {
                    ProgressView().controlSize(.small)
                } else if source.pushBased == true {
                    Pill("push", color: .piGymCyan)
                } else {
                    Button {
                        Task { await trigger(source.name) }
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                            .font(.piSubheadline)
                    }
                    .buttonStyle(.bordered)
                    .disabled(triggering.contains(source.name))
                }
            }
            if let last = source.lastSuccessAt, let date = PiDate.parseISO(last) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.piCaption)
                        .foregroundStyle(Color.piCalGood)
                    Text("Last success \(date.formatted(.relative(presentation: .named)))")
                        .font(.piCaption)
                        .foregroundStyle(Color.piTextMuted)
                    if let records = source.lastRecords {
                        Text("· \(records) records")
                            .font(.piCaption)
                            .foregroundStyle(Color.piTextMuted)
                    }
                }
            } else {
                Text("Never synced")
                    .font(.piCaption)
                    .foregroundStyle(Color.piWarn)
            }
        }
        .piCard()
    }

    private func recentRuns(_ runs: [SyncStatusResponse.SyncRun]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Recent runs")
            if runs.isEmpty {
                Text("No sync runs yet")
                    .font(.piSubheadline)
                    .foregroundStyle(Color.piTextMuted)
            }
            ForEach(runs) { run in
                HStack(spacing: 10) {
                    Image(systemName: run.status == "success" ? "checkmark.circle.fill"
                          : run.status == "running" ? "circle.dotted" : "xmark.circle.fill")
                        .foregroundStyle(run.status == "success" ? Color.piCalGood
                                         : run.status == "running" ? Color.piTextMuted : Color.piDanger)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(displayName(run.source))
                                .font(.piSubheadline)
                                .foregroundStyle(Color.piText)
                            Spacer()
                            if let started = PiDate.parseISO(run.startedAt) {
                                Text(started.formatted(date: .abbreviated, time: .shortened))
                                    .font(.piCaption)
                                    .foregroundStyle(Color.piTextMuted)
                            }
                        }
                        if let err = run.errorMessage {
                            Text(err)
                                .font(.piCaption)
                                .foregroundStyle(Color.piDanger)
                                .lineLimit(2)
                        } else {
                            Text("\(run.recordsSynced) records")
                                .font(.piCaption)
                                .foregroundStyle(Color.piTextMuted)
                        }
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .piCard()
    }

    private func displayName(_ source: String) -> String {
        switch source {
        case "lafitness": return "LA Fitness"
        case "healthifyme": return "HealthifyMe"
        case "apple_health": return "Apple Health"
        default: return source
        }
    }

    private func load() async {
        do {
            data = try await session.client.syncStatus()
            error = nil
        } catch {
            if data == nil { self.error = error.localizedDescription }
        }
    }

    private func trigger(_ source: String) async {
        triggering.insert(source)
        defer { triggering.remove(source) }
        do {
            try await session.client.triggerSync(source: source, days: 60)
            toast = Toast(message: "Sync started for \(displayName(source))")
            try? await Task.sleep(for: .seconds(1))
            await load()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}
