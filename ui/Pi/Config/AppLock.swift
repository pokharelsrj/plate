import SwiftUI
import LocalAuthentication
import Observation

/// Optional biometric gate over the whole app. The API key stays in the
/// Keychain regardless — this controls UI access only.
@Observable
final class AppLock {
    static let enabledKey = "appLock.enabled"

    var isLocked: Bool
    private var isAuthenticating = false

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if !newValue { isLocked = false }
        }
    }

    init() {
        isLocked = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    static var biometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var biometryLabel: String {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return "Passcode"
        }
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }

    @MainActor
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let ctx = LAContext()
        do {
            // Biometrics with device-passcode fallback so you can't get locked out.
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: "Unlock Pi")
            if ok { isLocked = false }
        } catch {
            // user cancelled or auth failed — stay locked
        }
    }
}

struct LockScreenView: View {
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("π")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(Color.piPrimary)
            Text("Plate is locked")
                .font(.piTitle)
                .foregroundStyle(Color.piText)
            Button {
                unlock()
            } label: {
                Label("Unlock with \(AppLock.biometryLabel)", systemImage: "faceid")
                    .font(.piHeadline)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 50)
                    .background(Color.piPrimary)
                    .foregroundStyle(Color.piOnPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.piPressable)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.piBg)
    }
}
