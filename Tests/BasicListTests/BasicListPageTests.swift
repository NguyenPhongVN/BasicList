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

    @Test("Init stores the values passed in")
    func initStoresValues() {
        let config = BasicListPageConfig(
            titleColor: .primary,
            titleFont: .title2,
            subtitleColor: .secondary,
            subtitleFont: .footnote,
            backgroundColor: .blue,
            headerListSpacing: 12,
            searchBackground: .gray,
            searchForeground: .white,
            emptyIcon: "tray",
            emptyTitle: "Empty",
            emptyMessage: "Nothing here",
            emptyIconColor: .orange,
            progressTint: .green,
            destructiveActionTint: .red,
            bottomClearance: 60)
        #expect(config.titleColor == .primary)
        #expect(config.titleFont == .title2)
        #expect(config.subtitleColor == .secondary)
        #expect(config.subtitleFont == .footnote)
        #expect(config.backgroundColor == .blue)
        #expect(config.headerListSpacing == 12)
        #expect(config.searchBackground == .gray)
        #expect(config.searchForeground == .white)
        #expect(config.emptyIcon == "tray")
        #expect(config.emptyTitle == "Empty")
        #expect(config.emptyMessage == "Nothing here")
        #expect(config.emptyIconColor == .orange)
        #expect(config.progressTint == .green)
        #expect(config.destructiveActionTint == .red)
        #expect(config.bottomClearance == 60)
    }

    @Test("Init without message → emptyMessage nil")
    func messageOptional() {
        let config = BasicListPageConfig(
            titleColor: .primary,
            titleFont: .title2,
            subtitleColor: .secondary,
            subtitleFont: .footnote,
            backgroundColor: .blue,
            headerListSpacing: 12,
            searchBackground: .gray,
            searchForeground: .white,
            emptyIcon: "tray",
            emptyTitle: "Empty",
            emptyIconColor: .orange,
            progressTint: .green,
            destructiveActionTint: .red,
            bottomClearance: 60)
        #expect(config.emptyMessage == nil)
    }

    @Test("listConfig derives the inner BasicListConfig from the two forwarded fields")
    func listConfigDerived() {
        let config = BasicListPageConfig(
            titleColor: .primary,
            titleFont: .title2,
            subtitleColor: .secondary,
            subtitleFont: .footnote,
            backgroundColor: .blue,
            headerListSpacing: 12,
            searchBackground: .gray,
            searchForeground: .white,
            emptyIcon: "tray",
            emptyTitle: "Empty",
            emptyIconColor: .orange,
            progressTint: .green,
            destructiveActionTint: .red,
            bottomClearance: 80)
        #expect(config.listConfig.destructiveActionTint == .red)
        #expect(config.listConfig.bottomClearance == 80)
    }

    @Test("Equatable — same values are equal, different values differ")
    func equality() {
        func config(tint: Color) -> BasicListPageConfig {
            BasicListPageConfig(
                titleColor: .primary,
                titleFont: .title2,
                subtitleColor: .secondary,
                subtitleFont: .footnote,
                backgroundColor: .blue,
                headerListSpacing: 12,
                searchBackground: .gray,
                searchForeground: .white,
                emptyIcon: "tray",
                emptyTitle: "Empty",
                emptyIconColor: .orange,
                progressTint: .green,
                destructiveActionTint: tint,
                bottomClearance: 60)
        }
        #expect(config(tint: .red) == config(tint: .red))
        #expect(config(tint: .red) != config(tint: .blue))
    }
}

// The suite constructs `BasicListPage` values — the engine's stored `@State`
// (the load-more gate) carries a @MainActor init, so construction is a
// main-actor operation at runtime: same convention as `BasicListViewTests`.
@MainActor
struct BasicListPageTests {

    private struct Item: Identifiable { let id: Int }

    private let pageConfig = BasicListPageConfig(
        titleColor: .primary,
        titleFont: .title2,
        subtitleColor: .secondary,
        subtitleFont: .footnote,
        backgroundColor: .blue,
        headerListSpacing: 12,
        searchBackground: .gray,
        searchForeground: .white,
        emptyIcon: "tray",
        emptyTitle: "Empty",
        emptyIconColor: .orange,
        progressTint: .green,
        destructiveActionTint: .red,
        bottomClearance: 60)

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

    @Test("basicPageRowSwipeActions forwards per edge — trailing and leading coexist")
    func swipeForwarding() {
        var page = BasicListPage(
            title: "T", items: [Item(id: 1)],
            config: pageConfig) { _ in Text("Row") }

        page = page.basicPageRowSwipeActions(allowsFullSwipe: false) { _ in [] }
        #expect(page.innerList.rowSwipeHandler != nil)
        #expect(page.innerList.rowSwipeAllowsFullSwipe == false)
        #expect(page.innerList.rowSwipeLeadingHandler == nil)

        page = page.basicPageRowSwipeActions(edge: .leading) { _ in [] }
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
    // / `.basicPageRowContextMenu` forward onto engine fields that are
    // `private` in BasicListView (rowTapHandler, onMoveHandler,
    // onRefreshHandler, rowContextMenuHandler) — not observable from the
    // host suite without touching the engine file. Their forwarding is
    // compile-checked by the calls themselves; the replace-semantics
    // pattern is pinned on the fields the engine DOES expose
    // (headerMode / loadMoreMode / swipe handlers above).
}
