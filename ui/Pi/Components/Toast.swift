import SwiftUI

struct Toast: Equatable {
    var message: String
    var actionLabel: String?
    var isError = false
    var id = UUID()
}

/// Bottom toast overlay with optional action (e.g. "Undo").
struct ToastOverlay: ViewModifier {
    @Binding var toast: Toast?
    var action: () -> Void = {}

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                HStack(spacing: 12) {
                    if toast.isError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.piWarn)
                    }
                    Text(toast.message)
                        .font(.piCallout)
                        .foregroundStyle(Color.piText)
                        .lineLimit(2)
                    if let label = toast.actionLabel {
                        Button(label) {
                            action()
                            self.toast = nil
                        }
                        .font(.piHeadline)
                        .foregroundStyle(Color.piPrimary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.piBg3)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.piBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(5))
                    if self.toast?.id == toast.id {
                        withAnimation { self.toast = nil }
                    }
                }
            }
        }
        .animation(.snappy, value: toast)
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>, action: @escaping () -> Void = {}) -> some View {
        modifier(ToastOverlay(toast: toast, action: action))
    }
}
