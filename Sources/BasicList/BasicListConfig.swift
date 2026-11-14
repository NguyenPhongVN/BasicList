import SwiftUI

// MARK: - BasicList config

/// Every color/metric of the BasicList family flows IN through this struct —
/// the module never reads a design layer (app colors, tab metrics) anywhere:
/// the engine stays pure SwiftUI, the caller decides the look.
///
/// Must be passed at construction — the module ships no default that injects
/// design values: missing config is a compile error instead of a silent look.
/// The app layer collects the standard values at ONE point (`BasicListConfig.house`)
/// instead of scattering colors/metrics across call sites — changing the look
/// of every list in the app means editing exactly that one wiring file.
public struct BasicListConfig: Sendable, Equatable {

    /// Tint of the swipe action flagged `isDestructive: true` — the dedicated
    /// language for data-destroying actions; regular actions KEEP the system
    /// default tint (see `basicRowSwipeActions`).
    package let destructiveActionTint: Color

    /// Bottom clearance of the list — `BasicPlainList` inserts a bottom spacer
    /// with this value so the last content isn't covered by a tab bar. A list
    /// in a context that doesn't cover the bottom → pass 0.
    package let bottomClearance: CGFloat

    public init(destructiveActionTint: Color, bottomClearance: CGFloat) {
        self.destructiveActionTint = destructiveActionTint
        self.bottomClearance = bottomClearance
    }
}
