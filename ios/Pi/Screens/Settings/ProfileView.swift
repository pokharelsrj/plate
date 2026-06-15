import SwiftUI

struct ProfileView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var hasDOB = false
    @State private var dob = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01
    @State private var sex = ""
    @State private var isSaving = false
    @State private var toast: Toast?

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Display name", text: $displayName)
                Toggle("Date of birth", isOn: $hasDOB)
                if hasDOB {
                    DatePicker("Born", selection: $dob, in: ...Date(), displayedComponents: .date)
                }
                Picker("Sex", selection: $sex) {
                    Text("—").tag("")
                    Text("Male").tag("male")
                    Text("Female").tag("female")
                }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving)
            } footer: {
                Text("Date of birth is used for the body-fat calculation.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.piBg)
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .toast($toast)
        .onAppear(perform: populate)
    }

    private func populate() {
        guard let user = session.user else { return }
        displayName = user.displayName ?? ""
        sex = user.sex ?? ""
        if let dobStr = user.dateOfBirth, let d = PiDate.parseDay(dobStr) {
            hasDOB = true
            dob = d
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await session.client.updateMe(
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                dateOfBirth: hasDOB ? PiDate.dayString(dob) : nil,
                sex: sex.isEmpty ? nil : sex
            )
            session.setUser(updated)
            dismiss()
        } catch {
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }
}
