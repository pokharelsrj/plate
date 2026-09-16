import SwiftUI

/// Compact ring used for calories-vs-budget and system dials.
struct ProgressRing: View {
    let progress: Double      // 0...1+ (clamped visually)
    let color: Color
    var lineWidth: CGFloat = 8
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.piBg3, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

/// Stacked horizontal bar of sleep stages.
struct SleepStageBar: View {
    let deep: Double
    let core: Double
    let rem: Double
    let awake: Double

    private var total: Double { max(deep + core + rem + awake, 0.001) }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                segment(deep, .piSleepDeep, in: geo.size.width)
                segment(core, .piSleepCore, in: geo.size.width)
                segment(rem, .piSleepRem, in: geo.size.width)
                segment(awake, .piSleepAwake, in: geo.size.width)
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func segment(_ hours: Double, _ color: Color, in width: CGFloat) -> some View {
        if hours > 0 {
            color.frame(width: max(width * hours / total - 2, 2))
        }
    }
}

/// Horizontal macro bar with label and grams.
struct MacroBar: View {
    let label: String
    let grams: Double
    let maxGrams: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Eyebrow(label)
                Spacer()
                Text("\(Int(grams))g")
                    .font(.piCaption)
                    .foregroundStyle(Color.piText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.piBg3)
                    Capsule()
                        .fill(color)
                        .frame(width: max(min(grams / max(maxGrams, 1), 1), 0.02) * geo.size.width)
                }
            }
            .frame(height: 6)
        }
    }
}

/// Standard async-state wrapper: spinner / error with retry / content.
struct LoadableView<Value, Content: View>: View {
    let value: Value?
    let error: String?
    let retry: () -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        if let value {
            content(value)
        } else if let error {
            ContentUnavailableView {
                Label("Can't reach Pi", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .controlSize(.large)
        }
    }
}
