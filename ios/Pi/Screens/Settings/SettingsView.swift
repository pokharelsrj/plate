import SwiftUI

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(AppLock.self) private var appLock
    @StateObject private var health = HealthService.shared

    @AppStorage("themePreference") private var themePreference = "system"
    @AppStorage("dailyStepGoal") private var stepGoal = 10000
    @AppStorage("sleepGoalHours") private var sleepGoal = 7.5

    @State private var showRotateConfirm = false
    @State private var showSignOutConfirm = false
    @State private var toast: Toast?
    @State private var healthSyncing = false

    var body: some View {
        NavigationStack {
            List {
                userSection
                accountSection
                securitySection
                appearanceSection
                goalsSection
                integrationsSection
                diagnosticsSection
                if session.user?.isAdmin == true {
                    adminSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.piBg)
            .navigationTitle("Settings")
            .toast($toast)
            .confirmationDialog("Rotate API key?", isPresented: $showRotateConfirm, titleVisibility: .visible) {
                Button("Rotate key", role: .destructive) {
                    Task { await rotateKey() }
                }
            } message: {
                Text("The old key stops working immediately. This device updates itself; other devices will need to sign in again.")
            }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    session.signOut()
                }
            }
        }
    }

    // MARK: - Sections

    private var userSection: some View {
        Section {
            HStack(spacing: 12) {
                InitialsAvatar(name: session.user?.name ?? "?", size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.user?.name ?? "Unknown")
                        .font(.piHeadline)
                        .foregroundStyle(Color.piText)
                    Text(session.user?.email ?? "")
                        .font(.piCaption)
                        .foregroundStyle(Color.piTextMuted)
                }
                Spacer()
                Pill(session.user?.role ?? "user",
                     color: session.user?.isAdmin == true ? .piWorkoutGold : .piTextMuted)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.piBg2)
    }

    private var accountSection: some View {
        Section("Account") {
            NavigationLink("Edit profile") {
                ProfileView()
            }
            Button("Rotate API key") {
                showRotateConfirm = true
            }
            .foregroundStyle(Color.piText)
            Button("Sign out", role: .destructive) {
                showSignOutConfirm = true
            }
        }
        .listRowBackground(Color.piBg2)
    }

    private var securitySection: some View {
        Section("Security") {
            Toggle("Require \(AppLock.biometryLabel)", isOn: Binding(
                get: { appLock.isEnabled },
                set: { appLock.isEnabled = $0 }
            ))
            .disabled(!AppLock.biometryAvailable)
            if !AppLock.biometryAvailable {
                Text("Set up Face ID or a device passcode to use the app lock.")
                    .font(.piCaption)
                    .foregroundStyle(Color.piTextMuted)
            }
        }
        .listRowBackground(Color.piBg2)
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $themePreference) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(Color.piBg2)
    }

    private var goalsSection: some View {
        Section("Goals") {
            Stepper("Daily steps: \(stepGoal.formatted())", value: $stepGoal, in: 1000...50000, step: 500)
            Stepper(String(format: "Sleep: %.1f h", sleepGoal), value: $sleepGoal, in: 4...12, step: 0.5)
        }
        .listRowBackground(Color.piBg2)
    }

    private var integrationsSection: some View {
        Section("Integrations") {
            NavigationLink {
                SyncStatusView()
            } label: {
                Label("Sync status", systemImage: "arrow.triangle.2.circlepath")
            }
            if HealthService.isAvailable {
                Menu {
                    Button("Last 7 days") { Task { await syncHealth(daysBack: 7) } }
                    Button("Last 30 days") { Task { await syncHealth(daysBack: 30) } }
                    Button("Last 90 days") { Task { await syncHealth(daysBack: 90) } }
                } label: {
                    HStack {
                        Label("Sync Apple Health", systemImage: "heart.fill")
                        Spacer()
                        if healthSyncing {
                            ProgressView().controlSize(.small)
                        } else if let last = health.lastSyncAt {
                            Text(last.formatted(.relative(presentation: .named)))
                                .font(.piCaption)
                                .foregroundStyle(Color.piTextMuted)
                        }
                    }
                }
                .foregroundStyle(Color.piText)
                .disabled(healthSyncing)
            }
        }
        .listRowBackground(Color.piBg2)
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            LabeledContent("Server", value: session.baseURL.absoluteString)
                .font(.piSubheadline)
            LabeledContent("Version",
                           value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            LabeledContent("Widget cache", value: widgetCacheStatus)
                .font(.piSubheadline)
        }
        .listRowBackground(Color.piBg2)
    }

    /// Quick app-group health check — "unavailable" means the App Group
    /// entitlement isn't provisioned and the widget can't receive data.
    private var widgetCacheStatus: String {
        guard FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedCache.groupID) != nil else {
            return "unavailable — check App Group signing"
        }
        guard let cached = SharedCache.read() else { return "empty — open Today once" }
        return "updated \(cached.fetchedAt.formatted(.relative(presentation: .named)))"
    }

    private var adminSection: some View {
        Section("Admin") {
            NavigationLink {
                AdminUsersView()
            } label: {
                Label("Manage users", systemImage: "person.2")
            }
            NavigationLink {
                ExercisesView()
            } label: {
                Label("Exercise library", systemImage: "books.vertical")
            }
        }
        .listRowBackground(Color.piBg2)
    }

    // MARK: - Actions

    private func rotateKey() async {
        do {
            let resp = try await session.client.rotateKey()
            session.setAPIKey(resp.apiKey)
            toast = Toast(message: "API key rotated")
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func syncHealth(daysBack: Int) async {
        healthSyncing = true
        defer { healthSyncing = false }
        do {
            try await health.requestAuthorization()
            try await health.sync(daysBack: daysBack, client: session.client)
            toast = Toast(message: "Synced last \(daysBack) days of health data")
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}
