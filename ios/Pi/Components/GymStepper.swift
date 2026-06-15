import SwiftUI

/// Big, sweaty-hands-friendly stepper. Buttons auto-repeat on long press;
/// tapping the value opens direct number entry.
struct GymStepper: View {
    @Binding var value: Double
    let step: Double
    let suffix: String
    var minimum: Double = 0
    var formatter: (Double) -> String = { v in
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }

    @State private var showEntry = false
    @State private var entryText = ""

    /// Medium haptic when crossing "round" values (multiples of 5× the step).
    private var isRound: Bool {
        let unit = max(step * 5, 1)
        return value.truncatingRemainder(dividingBy: unit) == 0
    }

    var body: some View {
        HStack(spacing: 0) {
            stepButton("−\(formatter(step))") {
                value = max(minimum, value - step)
            }
            Button {
                entryText = formatter(value)
                showEntry = true
            } label: {
                Text("\(formatter(value)) \(suffix)")
                    .font(.piMetricMed)
                    .foregroundStyle(Color.piText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                    .contentTransition(.numericText())
            }
            .buttonStyle(.piPressable)
            stepButton("+\(formatter(step))") {
                value += step
            }
        }
        .background(Color.piBg3)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.piBorder, lineWidth: 1)
        )
        .sensoryFeedback(isRound ? .impact(weight: .medium) : .impact(weight: .light), trigger: value)
        .alert("Enter \(suffix)", isPresented: $showEntry) {
            TextField(suffix, text: $entryText)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Set") {
                if let v = Double(entryText.replacingOccurrences(of: ",", with: ".")), v >= minimum {
                    value = v
                }
            }
        }
    }

    private func stepButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy(duration: 0.15)) { action() } }) {
            Text(label)
                .font(.piMetricSmall)
                .foregroundStyle(Color.piPrimary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonRepeatBehavior(.enabled)
        .buttonStyle(.piPressable)
    }
}
