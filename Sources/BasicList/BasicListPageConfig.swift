import SwiftUI

// MARK: - BasicListPage config

/// Every color/metric of the page chrome flows IN through this struct — the
/// same contract as `BasicListConfig`: the page stays pure SwiftUI and reads
/// no design layer (app colors, fonts) anywhere; the caller decides the look.
///
/// Must be passed at construction — the page ships no default that injects
/// design values: missing config is a compile error instead of a silent look.
/// The app layer collects the standard values at ONE point instead of
/// scattering colors/metrics across screens — changing the look of every
/// list page means editing exactly that one wiring file.
///
/// ## What belongs here vs. what stays internal
/// - DESIGN values (colors, fonts) and caller-varying metrics
///   (`headerListSpacing`, `bottomClearance`) live here.
/// - Small internal chrome layout paddings (the header's own horizontal
///   padding, the search field's inset) stay package-internal like the
///   engine's fixed sentinel height — they are layout, not design.
///
/// ## Default empty state
/// The page carries its own fallback empty state (`BasicListPage` applies it
/// when the caller never chains `.basicPageEmptyState`): the SF Symbol
/// (`emptyIcon`), the title (`emptyTitle`) and the optional message
/// (`emptyMessage`) all come from here — wording is caller-owned content,
/// localized at the wiring point like the colors are. The empty title renders
/// with `titleFont`, the message with `subtitleFont`.
///
/// ## Evolution policy
/// Same semver rule as `BasicListConfig`: new fields ship ONLY as new `init`
/// overloads with defaults (the existing init signature never changes) or as
/// builder methods — never as a change to an existing signature.
public struct BasicListPageConfig: Sendable, Equatable {

    // MARK: Page header

    /// Color of the page title — the mandatory first line of the header.
    package let titleColor: Color
    /// Font of the page title. A font IS design — it comes in like the
    /// colors do; the page never picks a typeface by itself.
    package let titleFont: Font
    /// Color of the optional subtitle line under the title.
    package let subtitleColor: Color
    /// Font of the optional subtitle line.
    package let subtitleFont: Font
    /// The page pours its own background — same language as the bare list
    /// (`BasicPlainList` hides the list's background; the screen owns the
    /// canvas). Applied across the whole page, chrome and list together.
    package let backgroundColor: Color
    /// Gap between the page chrome (header + search field + loading row) and
    /// the list below. The rows' internal spacing is the cells' business —
    /// this only separates the chrome from the content.
    package let headerListSpacing: CGFloat

    // MARK: Inline search field

    /// Fill of the search field pill (only rendered when
    /// `.basicPageSearch` is attached).
    package let searchBackground: Color
    /// Foreground of the search glyph and the typed text.
    package let searchForeground: Color

    // MARK: Default empty state

    /// SF Symbol name of the default empty state's icon. An invalid symbol
    /// name renders an empty image — the caller owns the validity, the page
    /// never guesses a fallback.
    package let emptyIcon: String
    /// Title line of the default empty state.
    package let emptyTitle: String
    /// Optional message line under the empty title — `nil` renders no
    /// message row at all.
    package let emptyMessage: String?
    /// Tint of the default empty state's icon.
    package let emptyIconColor: Color

    // MARK: Loading row

    /// Tint of the loading indicator shown between the chrome and the list
    /// while `.basicPageIsLoading(true)` is set. The row sits ABOVE the list
    /// and does not swap the list out — list identity is never lost across
    /// the loading/loaded phases (the same reason the engine's empty state
    /// runs inside the list).
    package let progressTint: Color

    // MARK: Forwarded to the inner list

    /// Forwarded into the inner `BasicListConfig.destructiveActionTint` —
    /// the page builds the list's config from here so a screen wires ONE
    /// config (`BasicListPageConfig`), not two.
    package let destructiveActionTint: Color
    /// Forwarded into the inner `BasicListConfig.bottomClearance` — the
    /// tab-bar clearance of the list inside the page.
    package let bottomClearance: CGFloat

    // MARK: Date pager (only rendered when `.basicPageDatePager` is attached)

    /// Tint of the pager's chevron glyphs.
    package let pagerChevronColor: Color
    /// Color of the window label between the chevrons.
    package let pagerTextColor: Color
    /// Font of the window label — a font IS design, it comes in like the
    /// colors do.
    package let pagerTextFont: Font

    /// `emptyMessage` defaults to `nil` (no message row) — every color/metric
    /// stays explicit: no default injects a design value.
    public init(
        titleColor: Color,
        titleFont: Font,
        subtitleColor: Color,
        subtitleFont: Font,
        backgroundColor: Color,
        headerListSpacing: CGFloat,
        searchBackground: Color,
        searchForeground: Color,
        emptyIcon: String,
        emptyTitle: String,
        emptyMessage: String? = nil,
        emptyIconColor: Color,
        progressTint: Color,
        destructiveActionTint: Color,
        bottomClearance: CGFloat,
        pagerChevronColor: Color,
        pagerTextColor: Color,
        pagerTextFont: Font
    ) {
        self.titleColor = titleColor
        self.titleFont = titleFont
        self.subtitleColor = subtitleColor
        self.subtitleFont = subtitleFont
        self.backgroundColor = backgroundColor
        self.headerListSpacing = headerListSpacing
        self.searchBackground = searchBackground
        self.searchForeground = searchForeground
        self.emptyIcon = emptyIcon
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.emptyIconColor = emptyIconColor
        self.progressTint = progressTint
        self.destructiveActionTint = destructiveActionTint
        self.bottomClearance = bottomClearance
        self.pagerChevronColor = pagerChevronColor
        self.pagerTextColor = pagerTextColor
        self.pagerTextFont = pagerTextFont
    }

    /// The inner list's config, derived from the two forwarded fields at
    /// construction — `package` so the host test suite can pin the wiring
    /// (a page config change must reach the list, not die at the page).
    package var listConfig: BasicListConfig {
        BasicListConfig(
            destructiveActionTint: destructiveActionTint,
            bottomClearance: bottomClearance)
    }
}
