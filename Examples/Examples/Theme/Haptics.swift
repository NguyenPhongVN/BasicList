import UIKit

// MARK: - Haptics — one tiny helper for the whole demo app
//
// Light impact for button taps, per the HIG: feedback confirms an action,
// it never decorates. No-op on platforms without UIKit so every call site
// stays unguarded.

enum Haptics {

    /// Light impact — the default tap confirmation.
    static func tap() {
        #if canImport(UIKit) && !os(watchOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
