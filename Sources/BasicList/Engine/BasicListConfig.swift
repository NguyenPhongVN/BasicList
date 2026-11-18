import SwiftUI

// MARK: - BasicList config

/// Every color/metric of the BasicList family flows IN through this struct —
/// the module never reads a design layer (app colors, tab metrics) anywhere:
/// the engine stays pure SwiftUI, the caller decides the look.
///
/// Must be passed at construction — the module ships no default that injects
/// design values: missing config is a compile error instead of a silent look.
/// The app layer collects the standard values at ONE point (e.g. a
/// `Config.house` extension in the app target) instead of scattering
/// colors/metrics across call sites — changing the look of every list in the
/// app means editing exactly that one wiring file.
///
/// ## Evolution policy
/// This struct is the library's main semver risk, so it evolves by ONE rule:
/// a new field appends to THIS init at the END with a default — labeled call
/// sites never break, and there is never a second overload to maintain.
/// Renaming or repurposing an existing parameter is the only forbidden move.
/// Derived configs never re-call the init: they chain `.updating` from the
/// house config.
///
/// ```swift
/// extension BasicListConfig { static let house = ... }            // app target
/// static let detail = BasicListConfig.house.updating { $0.bottomClearance = 64 }
/// ```
public struct BasicListConfig: Sendable, Equatable {

    /// Tint of the swipe action flagged `isDestructive: true` — the dedicated
    /// language for data-destroying actions; regular actions KEEP the system
    /// default tint (see `basicListSwipeActions`).
    public var destructiveActionTint: Color

    /// Bottom clearance of the list — `BasicPlainList` inserts a bottom spacer
    /// with this value so the last content isn't covered by a tab bar. A list
    /// in a context that doesn't cover the bottom → pass 0.
    public var bottomClearance: CGFloat

    public init(destructiveActionTint: Color, bottomClearance: CGFloat) {
        self.destructiveActionTint = destructiveActionTint
        self.bottomClearance = bottomClearance
    }

    /// Functional update — the evolution primitive for derived configs:
    /// mutate a copy, return it. The house config stays the single source;
    /// variants are one-liners instead of full re-constructions.
    public func updating(_ mutate: (inout Self) -> Void) -> Self {
        var copy = self
        mutate(&copy)
        return copy
    }
}
