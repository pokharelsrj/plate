import SwiftUI

struct PiCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.piBg2)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.piBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

extension View {
    func piCard(padding: CGFloat = 16) -> some View {
        modifier(PiCard(padding: padding))
    }
}

/// Pressed-state feedback for custom-styled buttons (scale + dim) — the
/// `.plain` style gives none, which makes filled buttons feel dead.
struct PiPressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PiPressable {
    static var piPressable: PiPressable { PiPressable() }
}

/// Letter-spaced section label, e.g. "STEPS".
struct Eyebrow: View {
    let text: String
    var color: Color = .piTextMuted
    init(_ text: String, color: Color = .piTextMuted) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text.uppercased())
            .font(.piEyebrow)
            .tracking(1.5)
            .foregroundStyle(color)
    }
}

/// Small capsule tag, e.g. role or body-part labels.
struct Pill: View {
    let text: String
    var color: Color = .piTextMuted
    init(_ text: String, color: Color = .piTextMuted) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text)
            .font(.piCaption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

/// Circular avatar with the user's initials.
struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 40
    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }
        return chars.isEmpty ? "?" : String(chars).uppercased()
    }
    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.piOnPrimary)
            .frame(width: size, height: size)
            .background(Color.piPrimary)
            .clipShape(Circle())
    }
}
