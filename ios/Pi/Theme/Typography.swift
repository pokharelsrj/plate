import SwiftUI

extension Font {
    // Display & headlines (rounded)
    static let piLargeTitle  = Font.system(size: 34, weight: .bold,     design: .rounded)
    static let piTitle       = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let piTitle2      = Font.system(size: 17, weight: .semibold, design: .rounded)

    // Body (default SF Pro)
    static let piHeadline    = Font.system(size: 17, weight: .semibold)
    static let piBody        = Font.system(size: 16, weight: .regular)
    static let piCallout     = Font.system(size: 15, weight: .regular)
    static let piSubheadline = Font.system(size: 14, weight: .regular)
    static let piCaption     = Font.system(size: 12, weight: .regular)

    // Metric numbers (rounded)
    static let piMetricXL    = Font.system(size: 48, weight: .bold,     design: .rounded)
    static let piMetricLarge = Font.system(size: 32, weight: .bold,     design: .rounded)
    static let piMetricMed   = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let piMetricSmall = Font.system(size: 17, weight: .medium,   design: .rounded)

    // Letter-spaced category labels (e.g. "TODAY", "STEPS")
    static let piEyebrow     = Font.system(size: 11, weight: .semibold)
}
