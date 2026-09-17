import SwiftUI

/// Changing your own password. The current one is required, so picking up an
/// unlocked phone isn't enough to lock the owner out. A successful change also
/// replaces the API key server-side — this device gets the new one, every
/// other device is signed out.
struct ChangePasswordView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var toast: Toast?

    private var tooShort: Bool { !newPassword.isEmpty && newPassword.count < 8 }
    private var mismatch: Bool { !confirm.isEmpty && newPassword != confirm }

    private var canSubmit: Bool {
        !current.isEmpty && newPassword.count >= 8 && newPassword == confirm
    }

    var body: some View {
        List {
            Section {
                SecureField("Current password", text: $current)
                    .textContentType(.password)
            }
            .listRowBackground(Color.piBg2)

            Section {
                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirm)
                    .textContentType(.newPassword)
            } footer: {
                if tooShort {
                    Text("At least 8 characters.").foregroundStyle(Color.piWarn)
                } else if mismatch {
                    Text("The two new passwords don't match.").foregroundStyle(Color.piWarn)
                } else {
                    Text("Changing your password signs out your other devices. This one stays signed in.")
                }
            }
            .listRowBackground(Color.piBg2)

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(Color.piDanger)
                }
                .listRowBackground(Color.piBg2)
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text("Change password")
                        if isSaving {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isSaving || !canSubmit)
            }
            .listRowBackground(Color.piBg2)
        }
        .scrollContentBackground(.hidden)
        .background(Color.piBg)
        .navigationTitle("Change password")
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            // The server hands back a replacement key; storing it is what keeps
            // this device signed in while the others fall off.
            let resp = try await session.client.changePassword(current: current, new: newPassword)
            session.setAPIKey(resp.apiKey)
            toast = Toast(message: "Password changed")
            dismiss()
        } catch APIError.forbidden {
            // The server uses 403 here precisely so this doesn't trip the
            // client's expired-session handling.
            errorMessage = "That current password is incorrect."
        } catch APIError.server(let message) {
            errorMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
