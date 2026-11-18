import SwiftUI
import Testing
@testable import BasicList

// MARK: - BasicListPage — tested on a macOS host (no UI rendering)
//
// Same contract as the engine tests: the testable parts are pure value
// behavior — page config storage + the derived inner list config, the shape
// passthrough (emptiness rule per shape), and the forwarding semantics of
// the basicPage* modifiers onto the inner BasicListView (replace semantics
// per the engine's last-call-wins). Rendering parts (chrome layout, search
// pill, loading row) belong to the Examples app — host tests can't build a
// page.

struct BasicListPageConfigTests {

    /// Facet wiring — one helper so every test varies exactly one knob.
    private func makeConfig(
        tint: Color = .red,
        message: String? = "Nothing here",
        bottomClearance: CGFloat = 60
    ) -> BasicListPageConfig {
        BasicListPageConfig(
            chrome: .init(
                titleColor: .primary,
                titleFont: .title2,
                subtitleColor: .secondary,
                subtitleFont: .footnote,
                backgroundColor: .blue,
                headerPadding: EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16),
                headerListSpacing: 12,
                progressTint: .green),
            search: .init(background: .gray, foreground: .white),
            emptyFallback: .init(
                icon: "tray",
                iconColor: .orange,
                title: "Empty",
                message: message),
            list: .init(destructiveActionTint: tint, bottomClearance: bottomClearance))
    }

    @Test("Init stores the values passed in — per facet")
    func initStoresValues() {
        let config = makeConfig()
        #expect(config.chrome.titleColor == .primary)
        #expect(config.chrome.titleFont == .title2)
        #expect(config.chrome.subtitleColor == .secondary)
        #expect(config.chrome.subtitleFont == .footnote)
        #expect(config.chrome.backgroundColor == .blue)
        #expect(config.chrome.headerPadding == EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
        #expect(config.chrome.headerListSpacing == 12)
        #expect(config.chrome.progressTint == .green)
        #expect(config.search.background == .gray)
        #expect(config.search.foreground == .white)
        #expect(config.emptyFallback.icon == "tray")
        #expect(config.emptyFallback.title == "Empty")
        #expect(config.emptyFallback.message == "Nothing here")
        #expect(config.emptyFallback.iconColor == .orange)
        #expect(config.list.destructiveActionTint == .red)
        #expect(config.list.bottomClearance == 60)
    }

    @Test("EmptyFallback without message → message nil")
    func messageOptional() {
        let fallback = BasicListPageConfig.EmptyFallback(icon: "tray", iconColor: .orange, title: "Empty")
        #expect(fallback.message == nil)
    }

    @Test("list facet IS the inner BasicListConfig — forwarded, not re-derived")
    func listDerived() {
        let config = makeConfig(tint: .red, bottomClearance: 80)
        #expect(config.list.destructiveActionTint == .red)
        #expect(config.list.bottomClearance == 80)
    }

    @Test("updating — mutates a copy, the source config stays untouched")
    func updatingMutatesCopy() {
        let house = makeConfig()
        let detail = house.updating {
            $0.list.bottomClearance = 64
            $0.emptyFallback.title = "No transactions"
            $0.chrome.headerListSpacing = 16
        }
        #expect(detail.list.bottomClearance == 64)
        #expect(detail.emptyFallback.title == "No transactions")
        #expect(detail.chrome.headerListSpacing == 16)
        // Source unchanged — derivation never corrupts the house config.
        #expect(house.list.bottomClearance == 60)
        #expect(house.emptyFallback.title == "Empty")
        #expect(house.chrome.headerListSpacing == 12)
    }

    @Test("Equatable — same values are equal, different values differ")
    func equality() {
        #expect(makeConfig(tint: .red) == makeConfig(tint: .red))
        #expect(makeConfig(tint: .red) != makeConfig(tint: .blue))
    }
}

// The suite constructs `BasicListPage` values — the engine's stored `@State`
// (the load-more gate) carries a @MainActor init, so construction is a
// main-actor operation at runtime: same convention as `BasicListViewTests`.
@MainActor
struct BasicListPageTests {

    private struct Item: Identifiable { let id: Int }

    private let pageConfig = BasicListPageConfig(
        chrome: .init(
            titleColor: .primary,
            titleFont: .title2,
            subtitleColor: .secondary,
            subtitleFont: .footnote,
            backgroundColor: .blue,
            headerPadding: EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16),
            headerListSpacing: 12,
            progressTint: .green),
        search: .init(background: .gray, foreground: .white),
        emptyFallback: .init(icon: "tray", iconColor: .orange, title: "Empty"),
        list: .init(destructiveActionTint: .red, bottomClearance: 60))

    @Test("Init stores title + subtitle and wires the page config")
    func initWiring() {
        let page = BasicListPage(
            title: "Accounts", subtitle: "All", items: [Item(id: 1)],
            config: pageConfig) { _ in Text("Row") }
        #expect(page.title == "Accounts")
        #expect(page.subtitle == "All")
        #expect(page.config == pageConfig)
        #expect(page.listConfig.destructiveActionTint == .red)
        #expect(page.listConfig.bottomClearance == 60)
        #expect(page.leadingSlot == nil)
        #expect(page.trailingSlot == nil)
        #expect(page.searchBinding == nil)
        #expect(page.searchPrompt == nil)
        #expect(page.isLoading == false)
        #expect(page.bottomBarBuilder == nil)
        #expect(page.contentKey == nil)
        #expect(page.contentTransition == nil)
    }

    @Test("Flat shape passthrough — the emptiness rule follows the items")
    func flatShapePassthrough() {
        let loaded = BasicListPage(
            title: "T", items: [Item(id: 1), Item(id: 2)],
            config: pageConfig) { _ in Text("Row") }
        #expect(loaded.innerList.isEmpty == false)

        let empty = BasicListPage(
            title: "T", items: [] as [Item],
            config: pageConfig) { _ in Text("Row") }
        #expect(empty.innerList.isEmpty == true)
    }

    @Test("Sectioned passthrough — per-shape emptiness: empty only when EVERY group is empty")
    func sectionedEmptinessForwarded() {
        let allEmpty = BasicListPage(
            title: "T",
            sections: [
                BasicListSection(section: "a", items: [] as [Item], itemID: { $0.id }) { Text("H") },
                BasicListSection(section: "b", items: [] as [Item], itemID: { $0.id }) { Text("H") }
            ],
            config: pageConfig) { _ in Text("Row") }
        #expect(allEmpty.innerList.isEmpty == true)

        let oneLoaded = BasicListPage(
            title: "T",
            sections: [
                BasicListSection(section: "a", items: [] as [Item], itemID: { $0.id }) { Text("H") },
                BasicListSection(section: "b", items: [Item(id: 1)], itemID: { $0.id }) { Text("H") }
            ],
            config: pageConfig) { _ in Text("Row") }
        #expect(oneLoaded.innerList.isEmpty == false)
    }

    @Test("basicPageListHeader forwards mode — last call wins")
    func listHeaderForwarding() {
        var page = BasicListPage(
            title: "T", items: [Item(id: 1)],
            config: pageConfig) { _ in Text("Row") }
        #expect(page.innerList.headerMode == .scrollsWithContent)

        page = page.basicPageListHeader(mode: .pinnedTop) { Text("List header") }
        #expect(page.innerList.headerMode == .pinnedTop)

        page = page.basicPageListHeader { Text("Replaced") }
        #expect(page.innerList.headerMode == .scrollsWithContent)
    }

    @Test("basicPageLoadMore forwards mode + handler — last call wins")
    func loadMoreForwarding() {
        var page = BasicListPage(
            title: "T", items: [Item(id: 1)],
            config: pageConfig) { _ in Text("Row") }
        #expect(page.innerList.onLoadMoreHandler == nil)

        page = page.basicPageLoadMore(mode: .pagesAhead(2)) { _ = await Task.yield() }
        #expect(page.innerList.onLoadMoreHandler != nil)
        #expect(page.innerList.loadMoreMode == .pagesAhead(2))

        page = page.basicPageLoadMore(mode: .pixelThreshold(150)) {}
        #expect(page.innerList.loadMoreMode == .pixelThreshold(150))
    }

    @Test("basicPageSwipeActions forwards per edge — trailing and leading coexist")
    func swipeForwarding() {
        var page = BasicListPage(
            title: "T", items: [Item(id: 1)],
            config: pageConfig) { _ in Text("Row") }

        page = page.basicPageSwipeActions(allowsFullSwipe: false) { _ in [] }
        #expect(page.innerList.rowSwipeHandler != nil)
        #expect(page.innerList.rowSwipeAllowsFullSwipe == false)
        #expect(page.innerList.rowSwipeLeadingHandler == nil)

        page = page.basicPageSwipeActions(edge: .leading) { _ in [] }
        #expect(page.innerList.rowSwipeLeadingHandler != nil)
        #expect(page.innerList.rowSwipeLeadingAllowsFullSwipe == true)
        // The trailing edge is untouched by the leading call.
        #expect(page.innerList.rowSwipeHandler != nil)
    }

    @Test("basicPageSearch stores the binding + prompt")
    func searchForwarding() {
        let text = Binding(get: { "" }, set: { _ in })
        var page = BasicListPage(
            title: "T", items: [Item(id: 1)],
            config: pageConfig) { _ in Text("Row") }
        #expect(page.searchBinding == nil)

        page = page.basicPageSearch(text, prompt: "Find it")
        #expect(page.searchBinding != nil)
        #expect(page.searchPrompt == "Find it")

        page = page.basicPageSearch(text)
        #expect(page.searchPrompt == nil)
    }

    @Test("basicPageIsLoading flips the chrome flag — list stays untouched")
    func loadingForwarding() {
        var page = BasicListPage(
            title: "T", items: [Item(id: 1)],
            config: pageConfig) { _ in Text("Row") }
        #expect(page.isLoading == false)

        page = page.basicPageIsLoading(true)
        #expect(page.isLoading == true)
        #expect(page.innerList.isEmpty == false)
    }

    @Test("basicPageLeading / basicPageTrailing store their slots — last call wins")
    func slotForwarding() {
        var page = BasicListPage(
            title: "T", items: [Item(id: 1)],
            config: pageConfig) { _ in Text("Row") }

        page = page.basicPageLeading { Text("L") }
        #expect(page.leadingSlot != nil)
        #expect(page.trailingSlot == nil)

        page = page.basicPageTrailing { Text("T") }
        #expect(page.leadingSlot != nil)
        #expect(page.trailingSlot != nil)
    }

    @Test("basicPageBottomBar stores the slot — last call wins")
    func bottomBarForwarding() {
        var page = BasicListPage(
            title: "T", items: [Item(id: 1)],
            config: pageConfig) { _ in Text("Row") }
        #expect(page.bottomBarBuilder == nil)

        page = page.basicPageBottomBar { Text("Bottom bar") }
        #expect(page.bottomBarBuilder != nil)
    }

    @Test("basicPageContentKey stores the key + transition for the content flip")
    func contentKeyForwarding() {
        let windowStart = Date(timeIntervalSince1970: 1_760_000_000)
        let anchor = Date(timeIntervalSince1970: 1_760_086_400)
        var page = BasicListPage(
            title: "T", items: [Item(id: 1)],
            config: pageConfig) { _ in Text("Row") }
        #expect(page.contentKey == nil)
        #expect(page.contentTransition == nil)

        page = page.basicPageContentKey(windowStart, transition: AnyTransition.asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .leading)))
        #expect(page.contentKey == AnyHashable(windowStart))
        #expect(page.contentTransition != nil)

        // Re-keying to another window replaces the key + transition
        // (last call wins — a window without a transition passes nil).
        page = page.basicPageContentKey(anchor)
        #expect(page.contentKey == AnyHashable(anchor))
        #expect(page.contentTransition == nil)
    }

    // NOTE: `.basicPageRowTap` / `.basicPageMoveRows` / `.basicPageRefresh`
    // / `.basicPageContextMenu` forward onto engine fields that are
    // `private` in BasicListView (rowTapHandler, onMoveHandler,
    // onRefreshHandler, rowContextMenuHandler) — not observable from the
    // host suite without touching the engine file. Their forwarding is
    // compile-checked by the calls themselves; the replace-semantics
    // pattern is pinned on the fields the engine DOES expose
    // (headerMode / loadMoreMode / swipe handlers above).
}
