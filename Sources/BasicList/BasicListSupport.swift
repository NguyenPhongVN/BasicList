import SwiftUI

// MARK: - BasicList shared vocabulary
//
// Small types that come with the engine: header mode, section, swipe action,
// spacer, sentinel, row style. Three groups share one render language:
// the engine (`BasicListView`), the bare list (`BasicPlainList`), and
// screens that build their own List (sentinel/spacer/row-style still apply).

/// Header mode of `BasicListView`:
/// - `.scrollsWithContent`: the header scrolls with the content (default).
/// - `.pinnedTop`: pinned to the top — sticky like a UIKit supplementary view.
public enum BasicListHeaderMode {
    case scrollsWithContent
    case pinnedTop
}

/// One group with its own sticky header — the typical shape: one day + the
/// transactions of that day.
///
/// The header stores a CLOSURE instead of an already-built view: the sections
/// array is usually a computed property of the screen (re-evaluated on every
/// body pass) — pre-building `AnyView` here would build headers for renders
/// that get thrown away; the closure only pays its cost when the list
/// actually renders that group.
public struct BasicListSection<Item> {
    package let section: AnyHashable
    package let header: () -> AnyView
    /// Group footer — nil when not declared: the List renders no footer
    /// row for that group.
    package let footer: (() -> AnyView)?
    package let items: [Item]
    package let itemID: (Item) -> AnyHashable

    public init(
        section: any Hashable,
        items: [Item],
        itemID: @escaping (Item) -> any Hashable,
        @ViewBuilder header: @escaping () -> some View
    ) {
        self.section = AnyHashable(section)
        self.items = items
        self.itemID = { item in AnyHashable(itemID(item)) }
        self.header = { AnyView(header()) }
        self.footer = nil
    }

    /// Group footer — symmetric with the header: rendered after the items of
    /// the group, scrolling with the content.
    public init(
        section: any Hashable,
        items: [Item],
        itemID: @escaping (Item) -> any Hashable,
        @ViewBuilder header: @escaping () -> some View,
        @ViewBuilder footer: @escaping () -> some View
    ) {
        self.section = AnyHashable(section)
        self.items = items
        self.itemID = { item in AnyHashable(itemID(item)) }
        self.header = { AnyView(header()) }
        self.footer = { AnyView(footer()) }
    }
}

/// One swipe action returned by the `.rowSwipeActions` handler — data in,
/// events out: the caller describes the button (title/glyph/destructive flag),
/// the engine draws it and reports back when the user taps. The tint of a
/// destructive button does NOT live here — it comes from the list's
/// `BasicListConfig.destructiveActionTint`.
public struct BasicListSwipeAction {
    package let title: String
    package let systemImage: String
    package let isDestructive: Bool
    package let handler: () -> Void

    public init(
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.handler = handler
    }
}

/// Standard style of ONE row in a house list: no inset, no separator,
/// transparent background — the cell draws its own background/card. Idempotent:
/// the engine already applies it to styled rows internally; calling it again
/// changes nothing.
public extension View {
    func basicListRowStyle() -> some View {
        self
            .listRowInsets(EdgeInsets.zero)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

package extension EdgeInsets {
    /// The counterpart of `EdgeInsets.zero` for a house list — used with
    /// `basicListRowStyle()`.
    static let zero = EdgeInsets()
}

/// Transparent row of `height` — inserted at the bottom of `BasicPlainList`
/// (clearing the tab bar) or anywhere else scroll-with-content padding is
/// needed inside a list.
public struct BasicListSpacer: View {
    package let height: CGFloat

    public init(height: CGFloat) {
        self.height = height
    }

    public var body: some View {
        Color.clear
            .frame(height: height)
            .basicListRowStyle()
            // Purely mechanical spacer — not a VoiceOver stop.
            .accessibilityHidden(true)
    }
}

/// Bottom sentinel: a transparent 1pt row carrying `onAppear` — fires
/// load-more when it materializes. Used by `BasicListView` internally and as
/// the last row of screens that build their own List.
///
/// ⚠️ Measured reality (2026-11-14, see `Docs/LoadMoreVerification.md`): the
/// probe ALSO fires at attach for in-region lists (the zero→settled
/// transition is an observed geometry change), so short lists currently
/// double-fire at attach — known issue F3, fix plan in the same doc.
///
/// Role: backstops the attach-time fire for short lists. The primary load-more
/// runs through the geometry probe on the List body (`.basicListBottomProbe`,
/// private to the engine) — the observer lives for the whole list lifetime and
/// fires on state transitions into the bottom region. But when the first page
/// doesn't fill a screen yet, no geometry change can happen after the probe
/// attaches (the distance is already inside the region and never "enters" it
/// again): the sentinel at the end of a short list materializes RIGHT AWAY and
/// its `onAppear` calls back to the VM until the list grows past the region.
/// For long lists, a lazy List only materializes the sentinel when the user
/// has scrolled into the bottom region — the right condition anyway. Duplicate
/// fires (probe + sentinel going off together) are blocked on the VM side
/// (`Paging.inFlight` / `exhausted`) — the sentinel keeps no state.
public struct BasicListScrollSentinel: View {

    /// Enter the trigger region when still this far from the bottom — the
    /// default threshold shared with the List-body probe
    /// (`.basicListBottomProbe`).
    public static let defaultBottomThreshold: CGFloat = 600

    package let onLoadMore: () async -> Void

    public init(onLoadMore: @escaping () async -> Void) {
        self.onLoadMore = onLoadMore
    }

    public var body: some View {
        Color.clear
            .frame(height: 1)
            .basicListRowStyle()
            // 1pt virtual row — hidden from VoiceOver (not content).
            .accessibilityHidden(true)
            .onAppear {
                Task { await onLoadMore() }
            }
    }
}
