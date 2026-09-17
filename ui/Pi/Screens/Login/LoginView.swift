import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session

    @State private var email = ""
    @State private var password = ""
    @State private var baseURLString = ""
    @State private var showAdvanced = false
    @State private var showSignUp = false
    @State private var signupOffered = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    PlateMark()
                    Text("Plate")
                        .font(.piTitle)
                        .foregroundStyle(Color.piText)
                    Text("Sign in to your server")
                        .font(.piSubheadline)
                        .foregroundStyle(Color.piTextMuted)
                }
                .padding(.top, 60)

                if session.sessionExpired {
                    banner("Session expired — sign in again.", color: .piWarn)
                }

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Color.piBg3)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding(14)
                        .background(Color.piBg3)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        TextField("Base URL", text: $baseURLString)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(Color.piBg3)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 8)
                    }
                    .font(.piSubheadline)
                    .foregroundStyle(Color.piTextMuted)
                }

                if let errorMessage {
                    banner(errorMessage, color: .piDanger)
                }

                Button(action: signIn) {
                    Group {
                        if isLoading {
                            ProgressView().tint(Color.piOnPrimary)
                        } else {
                            Text("Sign in").font(.piHeadline)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.piPrimary)
                    .foregroundStyle(Color.piOnPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.piPressable)
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1)

                if signupOffered {
                    Button("Create an account") { showSignUp = true }
                        .font(.piSubheadline)
                        .foregroundStyle(Color.piPrimary)
                } else {
                    Text("Accounts on this server are created by its admin.")
                        .font(.piCaption)
                        .foregroundStyle(Color.piTextMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.piBg)
        .onAppear {
            email = session.lastEmail
            baseURLString = session.baseURL.absoluteString
        }
        .task(id: baseURLString) { await probeSignup() }
        .sheet(isPresented: $showSignUp) {
            SignUpView(baseURLString: baseURLString)
        }
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.piSubheadline)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func signIn() {
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespaces)),
              url.scheme != nil else {
            errorMessage = "Invalid base URL."
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await session.login(email: email.trimmingCharacters(in: .whitespaces),
                                        password: password,
                                        baseURL: url)
            } catch APIError.unauthorized {
                errorMessage = "Invalid credentials"
            } catch {
                errorMessage = "Can't reach the server at \(url.absoluteString) — \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    /// Asks the server whether it takes sign-ups, so the app never offers a
    /// button the server will refuse. Any failure just hides it.
    private func probeSignup() async {
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespaces)),
              url.scheme != nil else {
            signupOffered = false
            return
        }
        let ping = try? await APIClient.ping(baseURL: url)
        signupOffered = ping?.signupEnabled ?? false
    }
}

/// The app icon's mark: a plate rim with a hub, which reads as either the
/// dinner kind or the kind that goes on a bar.
private struct PlateMark: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.piPrimary, lineWidth: 11)
                .frame(width: 74, height: 74)
            Circle()
                .stroke(Color.piPrimary.opacity(0.55), lineWidth: 2)
                .frame(width: 50, height: 50)
            Circle()
                .stroke(Color.piPrimary, lineWidth: 2)
                .frame(width: 12, height: 12)
        }
        .accessibilityHidden(true)
    }
}
