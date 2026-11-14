import SwiftUI

/// The bare `.plain` house list — the base of every list in the app.
///
/// Three settings define the word "bare": transparent background (the screen
/// pours its own background via `basicBackground`, the list brings no color
/// of its own), content margins 0 (content touches the edges, cells draw
/// their own padding/card), minimum row height 0 (a row is as tall as its
/// content says, never lifted by system padding).
///
/// Which view to pick:
/// - The screen builds its own complex sections/rows (custom sections,
///   interleaved content) → use this view directly.
/// - "Array in — item out" with built-in header/empty-state/swipe/tap/
///   refresh/load-more → use `BasicListView` (built ON TOP of this — every
///   list in the app shares one render language).
///
/// The bottom clearance of the list (clearing the tab bar) comes from
/// `config.bottomClearance` — the caller passes the app's standard value
/// (`BasicListConfig.house`); contexts that don't cover the bottom pass 0.
public struct BasicPlainList<Content: View>: View {

    package let config: BasicListConfig
    package let content: () -> Content

    public init(
        config: BasicListConfig,
        @ViewBuilder _ content: @escaping () -> Content
    ) {
        self.config = config
        self.content = content
    }

    public var body: some View {
        List {
            content()
            if config.bottomClearance > 0 {
                BasicListSpacer(height: config.bottomClearance)
            }
        }
        .listStyle(.plain)
        .basicListBackgroundHidden()
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    /// `scrollContentBackground` is unavailable on watchOS/tvOS — their lists
    /// manage backgrounds through platform chrome instead.
    @ViewBuilder
    func basicListBackgroundHidden() -> some View {
        #if os(tvOS) || os(watchOS)
        self
        #else
        self.scrollContentBackground(.hidden)
        #endif
    }
}
