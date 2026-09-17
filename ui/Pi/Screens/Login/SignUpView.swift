import SwiftUI
import UIKit

/// Self-service account creation, shown only when the server reports that
/// sign-up is enabled. The invite code is the server operator's gate — without
/// it the endpoint refuses, so there's no point pretending it's optional.
struct SignUpView: View {
    let baseURLString: String

    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var inviteCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var passwordTooShort: Bool { !password.isEmpty && password.count < 8 }
    private var passwordsDiffer: Bool { !confirmPassword.isEmpty && password != confirmPassword }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 8
            && password == confirmPassword
            && !inviteCode.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Your data lives on the server you're signing up to, and its administrator can read it. Run your own if you'd rather it didn't.")
                        .font(.piCaption)
                        .foregroundStyle(Color.piTextMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 12) {
                        field("Email", text: $email, content: .username, keyboard: .emailAddress)
                        field("Display name (optional)", text: $displayName, content: .name)
                        secureField("Password", text: $password, content: .newPassword)
                        secureField("Confirm password", text: $confirmPassword, content: .newPassword)
                        field("Invite code", text: $inviteCode)
                    }

                    if passwordTooShort {
                        hint("Password must be at least 8 characters.", color: .piWarn)
                    } else if passwordsDiffer {
                        hint("Passwords don't match.", color: .piWarn)
                    }
                    if let errorMessage {
                        hint(errorMessage, color: .piDanger)
                    }

                    Button(action: submit) {
                        Group {
                            if isLoading {
                                ProgressView().tint(Color.piOnPrimary)
                            } else {
                                Text("Create account").font(.piHeadline)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.piPrimary)
                        .foregroundStyle(Color.piOnPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.piPressable)
                    .disabled(isLoading || !canSubmit)
                    .opacity(canSubmit ? 1 : 0.5)

                    Text("Signing up to \(baseURLString)")
                        .font(.piCaption)
                        .foregroundStyle(Color.piTextMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.piBg)
            .navigationTitle("Create account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>,
                       content: UITextContentType? = nil,
                       keyboard: UIKeyboardType = .default) -> some View {
        TextField(label, text: text)
            .textContentType(content)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(14)
            .background(Color.piBg3)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func secureField(_ label: String, text: Binding<String>,
                             content: UITextContentType? = nil) -> some View {
        SecureField(label, text: text)
            .textContentType(content)
            .padding(14)
            .background(Color.piBg3)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func hint(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.piSubheadline)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func submit() {
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespaces)),
              url.scheme != nil else {
            errorMessage = "Invalid server URL."
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await session.signUp(email: email.trimmingCharacters(in: .whitespaces),
                                         password: password,
                                         displayName: displayName.trimmingCharacters(in: .whitespaces),
                                         inviteCode: inviteCode.trimmingCharacters(in: .whitespaces),
                                         baseURL: url)
                dismiss()
            } catch APIError.server(let message) {
                errorMessage = message
            } catch APIError.forbidden {
                errorMessage = "That invite code isn't valid for this server."
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
