import SwiftUI

// MARK: - BasicListPage config

/// Every color/metric of the page chrome flows IN through this struct — the
/// same contract as `BasicListConfig`: the page stays pure SwiftUI and reads
/// no design layer (app colors, fonts) anywhere; the caller decides the look.
///
/// Must be passed at construction — the page ships no default that injects
/// design values: missing config is a compile error instead of a silent look.
/// The app layer collects the standard values at ONE point (e.g. a
/// `Config.house` extension in the app target) instead of scattering
/// colors/metrics across screens — changing the look of every list page means
/// editing exactly that one wiring file.
///
/// ## Facets
/// The config groups its values into four facets — one per chrome surface —
/// so call sites read by anatomy instead of a flat 15-argument list:
/// - `chrome` — the page header (title/subtitle colors + fonts, background,
///   header padding + list spacing) and the loading-row tint.
/// - `search` — the inline search field pill (used when `.basicPageSearch`
///   is attached).
/// - `emptyFallback` — the page's own fallback empty state (icon/title/
///   message), applied when the caller never chains `.basicPageEmptyState`.
/// - `list` — the forwarded `BasicListConfig` of the inner engine list, so a
///   screen wires ONE config, not two.
///
/// ## What belongs here vs. what stays internal
/// - DESIGN values (colors, fonts) and caller-varying metrics
///   (`headerPadding`, `headerListSpacing`) live here.
/// - Small internal chrome layout paddings (the search field's inset) stay
///   package-internal like the engine's fixed sentinel height — they are
///   layout, not design.
///
/// ## Evolution policy
/// Same one rule as `BasicListConfig`: a new field appends to its facet's
/// init at the END with a default — labeled call sites never break, and no
/// init overload is ever created. Renaming or repurposing an existing
/// parameter is the only forbidden move. Derived configs never re-call the
/// init: they chain `.updating` from the house config.
public struct BasicListPageConfig: Sendable, Equatable {

    // MARK: Facets

    /// Page header + loading row — colors, fonts, background, metrics.
    public var chrome: Chrome
    /// Inline search field pill (only rendered when `.basicPageSearch` is
    /// attached).
    public var search: Search
    /// The page's own fallback empty state — applied when the caller never
    /// chains `.basicPageEmptyState` (see `BasicListPage`).
    public var emptyFallback: EmptyFallback
    /// The inner list's engine config — forwarded so a screen wires ONE
    /// config (`BasicListPageConfig`), not two.
    public var list: BasicListConfig

    /// The page header: title/subtitle colors + fonts, the canvas the page
    /// pours behind itself (chrome and list together), the header's own
    /// padding + gap to the list, and the loading-row tint.
    public struct Chrome: Sendable, Equatable {

        /// Color of the page title — the mandatory first line of the header.
        public var titleColor: Color
        /// Font of the page title. A font IS design — it comes in like the
        /// colors do; the page never picks a typeface by itself.
        public var titleFont: Font
        /// Color of the optional subtitle line under the title.
        public var subtitleColor: Color
        /// Font of the optional subtitle line.
        public var subtitleFont: Font
        /// The page pours its own background — same language as the bare list
        /// (`BasicPlainList` hides the list's background; the screen owns the
        /// canvas). Applied across the whole page, chrome and list together.
        public var backgroundColor: Color
        /// The header chrome's own padding (title block, leading/trailing
        /// slots) — caller-varying metric, not a package-fixed layout value.
        public var headerPadding: EdgeInsets
        /// Gap between the page chrome (header + search field + loading row)
        /// and the list below. The rows' internal spacing is the cells'
        /// business — this only separates the chrome from the content.
        public var headerListSpacing: CGFloat
        /// Tint of the loading indicator shown between the chrome and the
        /// list while `.basicPageIsLoading(true)` is set. The row sits ABOVE
        /// the list and does not swap the list out — list identity is never
        /// lost across the loading/loaded phases (the same reason the
        /// engine's empty state runs inside the list).
        public var progressTint: Color

        public init(
            titleColor: Color,
            titleFont: Font,
            subtitleColor: Color,
            subtitleFont: Font,
            backgroundColor: Color,
            headerPadding: EdgeInsets,
            headerListSpacing: CGFloat,
            progressTint: Color
        ) {
            self.titleColor = titleColor
            self.titleFont = titleFont
            self.subtitleColor = subtitleColor
            self.subtitleFont = subtitleFont
            self.backgroundColor = backgroundColor
            self.headerPadding = headerPadding
            self.headerListSpacing = headerListSpacing
            self.progressTint = progressTint
        }
    }

    /// The inline search field pill — fill and foreground. The glyph, the
    /// typed text and the field's own inset (package-internal layout) are the
    /// only pieces; the caller owns the filtering (data in, events out).
    public struct Search: Sendable, Equatable {

        /// Fill of the search field pill.
        public var background: Color
        /// Foreground of the search glyph and the typed text.
        public var foreground: Color

        public init(background: Color, foreground: Color) {
            self.background = background
            self.foreground = foreground
        }
    }

    /// The page's fallback empty state — the SF Symbol, title and optional
    /// message rendered when the caller never chains `.basicPageEmptyState`.
    /// Wording is caller-owned content, localized at the wiring point like
    /// the colors are; a screen with its own empty-state copy overrides the
    /// builder per page (`.basicPageEmptyState`) and never touches this.
    ///
    /// The empty title renders with `chrome.titleFont`, the message with
    /// `chrome.subtitleFont`.
    public struct EmptyFallback: Sendable, Equatable {

        /// SF Symbol name of the fallback empty state's icon. An invalid
        /// symbol name renders an empty image — the caller owns the validity,
        /// the page never guesses a fallback.
        public var icon: String
        /// Tint of the fallback empty state's icon.
        public var iconColor: Color
        /// Title line of the fallback empty state.
        public var title: String
        /// Optional message line under the empty title — `nil` renders no
        /// message row at all.
        public var message: String?

        public init(icon: String, iconColor: Color, title: String, message: String? = nil) {
            self.icon = icon
            self.iconColor = iconColor
            self.title = title
            self.message = message
        }
    }

    /// Every facet is explicit — no facet defaults itself, no default
    /// injects a design value.
    public init(
        chrome: Chrome,
        search: Search,
        emptyFallback: EmptyFallback,
        list: BasicListConfig
    ) {
        self.chrome = chrome
        self.search = search
        self.emptyFallback = emptyFallback
        self.list = list
    }

    /// Functional update — the evolution primitive for derived configs:
    /// mutate a copy, return it. The house config stays the single source;
    /// page variants are one-liners instead of full re-constructions.
    ///
    /// ```swift
    /// extension BasicListPageConfig { static let house = ... }   // app target
    /// static let detail = BasicListPageConfig.house.updating {
    ///     $0.list.bottomClearance = 64
    ///     $0.emptyFallback.title = "No transactions"
    /// }
    /// ```
    public func updating(_ mutate: (inout Self) -> Void) -> Self {
        var copy = self
        mutate(&copy)
        return copy
    }

    /// The header padding of the PRE-facet look, byte-for-byte (16
    /// horizontal, 12 top, 8 bottom) — the deprecated flat init bridges it
    /// because pre-facet call sites never passed padding. Lives exactly as
    /// long as the bridge: deleted in 1.2.0 together with the deprecated
    /// init (README — Config, evolution policy, deprecation bridge).
    private static let legacyHeaderPadding =
        EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16)

    /// Deprecated flat init — kept so pre-facet call sites keep compiling.
    /// The header padding falls back to `legacyHeaderPadding` — byte-for-byte
    /// the old look.
    ///
    /// - Warning: new fields never land here. Migrate to
    ///   `init(chrome:search:emptyFallback:list:)`.
    @available(*, deprecated,
               message: "Use init(chrome:search:emptyFallback:list:) and derive variants with .updating. Deprecated in 1.0.0 — removed in 1.2.0.")
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
        bottomClearance: CGFloat
    ) {
        self.chrome = Chrome(
            titleColor: titleColor,
            titleFont: titleFont,
            subtitleColor: subtitleColor,
            subtitleFont: subtitleFont,
            backgroundColor: backgroundColor,
            headerPadding: Self.legacyHeaderPadding,
            headerListSpacing: headerListSpacing,
            progressTint: progressTint)
        self.search = Search(background: searchBackground, foreground: searchForeground)
        self.emptyFallback = EmptyFallback(
            icon: emptyIcon, iconColor: emptyIconColor,
            title: emptyTitle, message: emptyMessage)
        self.list = BasicListConfig(
            destructiveActionTint: destructiveActionTint,
            bottomClearance: bottomClearance)
    }
}
