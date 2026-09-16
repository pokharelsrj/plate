import SwiftUI

struct LoginView: View {
    @Environment(Session.self) private var session

    @State private var email = ""
    @State private var password = ""
    @State private var baseURLString = ""
    @State private var showAdvanced = false
    @State private var showNoAccountInfo = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("π")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.piPrimary)
                    Text("Sign in to your Pi")
                        .font(.piTitle)
                        .foregroundStyle(Color.piText)
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

                Button("Don't have an account?") {
                    showNoAccountInfo = true
                }
                .font(.piSubheadline)
                .foregroundStyle(Color.piTextMuted)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.piBg)
        .onAppear {
            email = session.lastEmail
            baseURLString = session.baseURL.absoluteString
        }
        .alert("Private service", isPresented: $showNoAccountInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This is a private service. Ask the admin to create your account.")
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
                errorMessage = "Can't reach Pi at \(url.absoluteString) — \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
