import SwiftUI
import UniformTypeIdentifiers

/// Pick a PDF statement from Files and upload it to the backend for parsing +
/// idempotent import (re-uploading the same statement won't duplicate).
struct UploadStatementView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let onDone: (_ imported: Bool) -> Void

    @State private var picking = false
    @State private var uploading = false
    @State private var result: UploadResult?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.piPrimary)
                        .padding(.top, 24)
                    Text("Upload a PDF statement")
                        .font(.piTitle)
                        .foregroundStyle(Color.piText)
                    Text("Rockland Trust checking/savings or the Elan credit card. It's parsed on the Pi and merged in — duplicates are skipped automatically.")
                        .font(.piSubheadline)
                        .foregroundStyle(Color.piTextMuted)
                        .multilineTextAlignment(.center)

                    Button { picking = true } label: {
                        Label("Choose PDF", systemImage: "folder")
                            .font(.piHeadline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color.piPrimary)
                            .foregroundStyle(Color.piOnPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.piPressable)
                    .disabled(uploading)

                    if uploading { ProgressView("Parsing…").padding(.top, 8) }

                    if let result {
                        resultCard(result)
                    }
                    if let error {
                        Text(error)
                            .font(.piCallout)
                            .foregroundStyle(Color.piDanger)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 20)
            }
            .background(Color.piBg)
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(result != nil); dismiss() }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf]) { res in
                switch res {
                case .success(let url): Task { await upload(url) }
                case .failure(let err): error = err.localizedDescription
                }
            }
        }
    }

    private func resultCard(_ r: UploadResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Imported", color: .piCalGood)
            Text(r.file).font(.piBody).foregroundStyle(Color.piText).lineLimit(2)
            row("New transactions", "\(r.inserted)")
            row("Already present", "\(r.duplicates)")
            row("Auto-categorized", "\(r.categorizedOnImport)")
            if let ok = r.reconciled {
                row("Reconciled", ok ? "✓ balanced" : "⚠︎ check totals")
            }
        }
        .piCard()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.piSubheadline).foregroundStyle(Color.piTextMuted)
            Spacer()
            Text(value).font(.piBody).foregroundStyle(Color.piText)
        }
    }

    private func upload(_ url: URL) async {
        uploading = true; error = nil; result = nil
        defer { uploading = false }
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            result = try await session.financeClient.uploadStatement(fileData: data, filename: url.lastPathComponent)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
