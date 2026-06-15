import SwiftUI

struct AdminUsersView: View {
    @Environment(Session.self) private var session

    @State private var users: [User] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var showNewUser = false
    @State private var createdKey: AdminCreatedUser?
    @State private var toast: Toast?

    var body: some View {
        List {
            ForEach(users) { user in
                NavigationLink {
                    UserEditView(user: user) { await load() }
                } label: {
                    HStack(spacing: 12) {
                        InitialsAvatar(name: user.name, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(user.name)
                                .font(.piBody)
                                .foregroundStyle(Color.piText)
                            Text(user.email)
                                .font(.piCaption)
                                .foregroundStyle(Color.piTextMuted)
                        }
                        Spacer()
                        if user.isActive == false {
                            Pill("inactive", color: .piWarn)
                        }
                        Pill(user.role, color: user.isAdmin ? .piWorkoutGold : .piTextMuted)
                    }
                }
                .listRowBackground(Color.piBg2)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.piBg)
        .navigationTitle("Users")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewUser = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .toast($toast)
        .sheet(isPresented: $showNewUser) {
            NewUserSheet { created in
                createdKey = created
                Task { await load() }
            }
        }
        .sheet(item: Binding(get: { createdKey.map(CreatedKeyBox.init) },
                             set: { createdKey = $0?.value })) { box in
            APIKeyRevealSheet(created: box.value)
                .presentationDetents([.medium])
        }
    }

    private func load() async {
        do {
            users = try await session.client.adminUsers().users
            error = nil
            loaded = true
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}

/// Identifiable wrapper so the created-key sheet can use sheet(item:).
private struct CreatedKeyBox: Identifiable {
    let value: AdminCreatedUser
    var id: Int64 { value.user.id }
}

// MARK: - Edit existing user

struct UserEditView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let user: User
    let onChange: () async -> Void

    @State private var displayName = ""
    @State private var role = "user"
    @State private var isActive = true
    @State private var newPassword = ""
    @State private var showDeleteConfirm = false
    @State private var toast: Toast?

    var body: some View {
        Form {
            Section("User") {
                LabeledContent("Email", value: user.email)
                TextField("Display name", text: $displayName)
                Picker("Role", selection: $role) {
                    Text("User").tag("user")
                    Text("Admin").tag("admin")
                }
                Toggle("Active", isOn: $isActive)
                Button("Save changes") {
                    Task { await save() }
                }
            }
            Section("Reset password") {
                SecureField("New password", text: $newPassword)
                Button("Reset password") {
                    Task { await resetPassword() }
                }
                .disabled(newPassword.count < 6)
            }
            Section {
                Button("Delete account", role: .destructive) {
                    showDeleteConfirm = true
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.piBg)
        .navigationTitle(user.name)
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
        .onAppear {
            displayName = user.displayName ?? ""
            role = user.role
            isActive = user.isActive ?? true
        }
        .confirmationDialog("Delete \(user.email)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) {
                Task { await deleteUser() }
            }
        } message: {
            Text("This permanently deletes the account.")
        }
    }

    private func save() async {
        do {
            _ = try await session.client.adminUpdateUser(id: user.id,
                                                         displayName: displayName,
                                                         role: role,
                                                         isActive: isActive)
            await onChange()
            toast = Toast(message: "Saved")
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func resetPassword() async {
        do {
            try await session.client.adminResetPassword(id: user.id, password: newPassword)
            newPassword = ""
            toast = Toast(message: "Password reset")
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    private func deleteUser() async {
        do {
            try await session.client.adminDeleteUser(id: user.id)
            await onChange()
            dismiss()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}

// MARK: - Create user

struct NewUserSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let onCreated: (AdminCreatedUser) -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var role = "user"
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("New user") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Initial password", text: $password)
                    TextField("Display name", text: $displayName)
                    Picker("Role", selection: $role) {
                        Text("User").tag("user")
                        Text("Admin").tag("admin")
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(Color.piDanger)
                    }
                }
            }
            .navigationTitle("Create user")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(isCreating || email.isEmpty || password.count < 6)
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            let created = try await session.client.adminCreateUser(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                role: role,
                dateOfBirth: nil,
                sex: nil
            )
            dismiss()
            onCreated(created)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - One-time API key reveal

struct APIKeyRevealSheet: View {
    let created: AdminCreatedUser
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "key.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.piWorkoutGold)
                .padding(.top, 24)
            Text("\(created.user.email) created")
                .font(.piTitle2)
                .foregroundStyle(Color.piText)
            Text(created.apiKey)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.piText)
                .padding(12)
                .background(Color.piBg3)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
            Button {
                UIPasteboard.general.string = created.apiKey
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy API key", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.piPrimary)
                    .foregroundStyle(Color.piOnPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.piPressable)
            .padding(.horizontal, 20)
            Text("They don't strictly need it — signing in with email/password fetches it — but this is the only time it's shown.")
                .font(.piCaption)
                .foregroundStyle(Color.piTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            Button("Done") { dismiss() }
                .padding(.bottom, 16)
        }
        .background(Color.piBg)
    }
}
