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
// pill, loading row) belong to the Examples app — host tests can't build a page.

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
            bottomClearance: 60,
            pagerChevronColor: .primary,
            pagerTextColor: .primary,
            pagerTextFont: .title3)
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
            bottomClearance: 60,
            pagerChevronColor: .primary,
            pagerTextColor: .primary,
            pagerTextFont: .title3)
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
            bottomClearance: 80,
            pagerChevronColor: .primary,
            pagerTextColor: .primary,
            pagerTextFont: .title3)
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
                bottomClearance: 60,
                pagerChevronColor: .primary,
                pagerTextColor: .primary,
                pagerTextFont: .title3)
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
        bottomClearance: 60,
        pagerChevronColor: .primary,
        pagerTextColor: .primary,
        pagerTextFont: .title3)

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

    // NOTE: `.basicPageRowTap` / `.basicPageMoveRows` / `.basicPageRefresh`
    // / `.basicPageRowContextMenu` forward onto engine fields that are
    // `private` in BasicListView (rowTapHandler, onMoveHandler,
    // onRefreshHandler, rowContextMenuHandler) — not observable from the
    // host suite without touching the engine file. Their forwarding is
    // compile-checked by the calls themselves; the replace-semantics
    // pattern is pinned on the fields the engine DOES expose
    // (headerMode / loadMoreMode / swipe handlers above).
}

// MARK: - BasicListDatePager — stepping math + page wiring
//
// The pager is the page's period-paging row (the app's BudgetDetail stepper
// pattern): one tap = one `BasicListPeriodUnit`, forward stops at the
// anchor. The testable parts are the pure stepping math (day/week direct,
// month/year re-derived from the anchor against calendar-clamp drift) and
// the wiring through `.basicPageDatePager`. Construction of view values is
// a main-actor operation at runtime (same rule as `BasicListPageTests`).

@MainActor
struct BasicListDatePagerTests {

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
        bottomClearance: 60,
        pagerChevronColor: .primary,
        pagerTextColor: .primary,
        pagerTextFont: .title3)

    /// Midnight-local date — same builder the stepper math starts from.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("Day stepping — ±1 unit is exactly ±1 day")
    func dayStepping() {
        let start = date(2026, 10, 15)
        #expect(BasicListDatePager.step(start, by: 1, anchor: start, unit: .day) == date(2026, 10, 16))
        #expect(BasicListDatePager.step(start, by: -1, anchor: start, unit: .day) == date(2026, 10, 14))
    }

    @Test("Week stepping — one unit is exactly 7 days")
    func weekStepping() {
        let start = date(2026, 10, 15)
        #expect(BasicListDatePager.step(start, by: 1, anchor: start, unit: .week) == date(2026, 10, 22))
        #expect(BasicListDatePager.step(start, by: -1, anchor: start, unit: .week) == date(2026, 10, 8))
    }

    @Test("Month stepping re-derives from the anchor — clamp never accumulates")
    func monthSteppingResistsAnchorDrift() {
        // Anchor on the 31st: +1 clamps to Feb 28…
        let anchor = date(2026, 1, 31)
        let stepped = BasicListDatePager.step(anchor, by: 1, anchor: anchor, unit: .month)
        #expect(stepped == date(2026, 2, 28))
        // …and stepping BACK from the clamped page must land on Jan 31 —
        // compounding from Feb 28 would drift to Jan 28 and lose the page.
        let back = BasicListDatePager.step(stepped, by: -1, anchor: anchor, unit: .month)
        #expect(back == date(2026, 1, 31))
        // Forward from a history page keeps the anchor's day-of-month:
        // Feb 28 + 1 = Mar 31, not Mar 28.
        let forwardAgain = BasicListDatePager.step(stepped, by: 1, anchor: anchor, unit: .month)
        #expect(forwardAgain == date(2026, 3, 31))
    }

    @Test("Year stepping — re-derived from the anchor like month")
    func yearStepping() {
        let anchor = date(2026, 1, 1)
        #expect(BasicListDatePager.step(anchor, by: -1, anchor: anchor, unit: .year) == date(2025, 1, 1))
        #expect(BasicListDatePager.step(anchor, by: 1, anchor: anchor, unit: .year) == date(2027, 1, 1))
    }

    @Test("Forward disabled exactly at the anchor — back never disabled")
    func forwardDisabledAtAnchorOnly() {
        let anchor = date(2026, 11, 1)
        let history = date(2026, 10, 1)
        let bound = BasicListDatePager(
            text: "Nov 1 - Nov 30",
            windowStart: .constant(anchor),
            anchor: anchor,
            unit: .month,
            chevronColor: .primary,
            textColor: .primary,
            textFont: .title3)
        let behind = BasicListDatePager(
            text: "Oct 1 - Oct 31",
            windowStart: .constant(history),
            anchor: anchor,
            unit: .month,
            chevronColor: .primary,
            textColor: .primary,
            textFont: .title3)
        #expect(bound.isForwardDisabled == true)
        #expect(behind.isForwardDisabled == false)
    }

    @Test("basicPageDatePager stores the spec verbatim — text, unit, binding, anchor")
    func pageStoresPagerSpec() throws {
        let anchor = date(2026, 11, 1)
        let windowStart = date(2026, 10, 1)
        var navigations: [Bool] = []
        let page = BasicListPage(
            title: "T", items: [Item(id: 1)],
            config: pageConfig) { _ in Text("Row") }
            .basicPageDatePager(
                text: "Oct 1 - Oct 31",
                windowStart: Binding(
                    get: { windowStart },
                    set: { _ = $0 }),
                anchor: anchor,
                unit: .month,
                onNavigate: { navigations.append($0) })

        let spec = try #require(page.datePagerSpec)
        #expect(spec.text == "Oct 1 - Oct 31")
        #expect(spec.anchor == anchor)
        #expect(spec.unit == .month)
        #expect(spec.windowStart.wrappedValue == windowStart)
        #expect(spec.onNavigate != nil)

        // The wiring reaches a pager value with the config's look — the
        // bound derivation follows the spec's window vs anchor.
        let pager = BasicListDatePager(
            text: spec.text,
            windowStart: spec.windowStart,
            anchor: spec.anchor,
            unit: spec.unit,
            onNavigate: spec.onNavigate,
            chevronColor: pageConfig.pagerChevronColor,
            textColor: pageConfig.pagerTextColor,
            textFont: pageConfig.pagerTextFont)
        #expect(pager.isForwardDisabled == false)
    }

    @Test("basicPageContentKey stores the key + transition for the content flip")
    func contentKeyForwarding() {
        let anchor = date(2026, 11, 1)
        let windowStart = date(2026, 10, 1)
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
}
