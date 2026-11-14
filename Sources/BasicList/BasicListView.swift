import SwiftUI

// MARK: - BasicListView — the "array in — item out" engine
//
// One view for both shapes: flat (`items:`) and sectioned with a sticky
// header per group (`sections:`). Includes the 2-mode header, empty-state,
// footer, swipe actions, row tap, refresh, continuous load-more, flat-list
// reorder (onMove + editMode). The base is `BasicPlainList` — a bare .plain
// house list.
//
// COLORS/METRICS: passed in via `BasicListConfig` — the engine stays pure
// SwiftUI and reads no design layer. Which view to pick, the config, the
// load-more mechanics and the mandatory rules — see the module README.md.

/// Base "array in — item out" for house lists.
///
/// The engine's three principles:
/// - **Data in, events out** — swipe/tap/move/refresh/load-more are all
///   closures passed in by the caller; the engine keeps no business state,
///   the single data source is the array/sections passed in.
/// - **Immutable, modifiers return `Self`** — chain freely, no hidden state
///   that changes with modifier call order.
/// - **Design goes through config** — no hardcoded color/metric inside the
///   module; missing config is a compile error.
///
/// ```swift
/// BasicListView(items: accounts, config: .house) { account in
///     AccountRowView(account)
/// }
/// .basicListHeader { AccountBalanceHeader() }
/// .onRefresh { try await api.reload() }
/// .onLoadMore { try? await api.nextPage() }
/// .rowSwipeActions { account in deleteActions(for: account) }
///
/// BasicListView(sections: dayGroups, config: .house) { transaction in
///     TransactionRowView(transaction)
/// }
/// ```
public struct BasicListView<Item, Content: View>: View {

    private struct Row: Identifiable {
        let item: Item
        let id: AnyHashable
    }

    /// Internal section: flat is a single group with an empty header.
    private struct Group: Identifiable {
        let section: AnyHashable
        let header: () -> AnyView
        let footer: (() -> AnyView)?
        let rows: [Row]
        var id: AnyHashable { section }
    }

    /// The one data shape — flat rows or sectioned groups. One source of
    /// truth instead of the old flag + two arrays (one always empty).
    private enum Shape {
        case flat([Row])
        case sectioned([Group])
    }

    private let shape: Shape
    private let content: (Item) -> Content
    /// Colors/metrics passed in by the caller (see `BasicListConfig`) — the
    /// engine never reads design values by itself.
    private let config: BasicListConfig
    private var headerBuilder: (() -> AnyView)?
    private var headerMode: BasicListHeaderMode = .scrollsWithContent
    private var emptyStateBuilder: (() -> AnyView)?
    private var footerBuilder: (() -> AnyView)?
    private var rowSwipeHandler: ((Item) -> [BasicListSwipeAction])?
    private var rowSwipeLeadingHandler: ((Item) -> [BasicListSwipeAction])?
    private var rowContextMenuHandler: ((Item) -> AnyView)?
    private var rowTapHandler: ((Item) -> Void)?
    private var onMoveHandler: ((IndexSet, Int) -> Void)?
    #if os(iOS)
    private var editModeBinding: Binding<EditMode>?
    #endif
    private var onRefreshHandler: (() async throws -> Void)?
    private var onLoadMoreHandler: (() async -> Void)?
    private var loadMoreMode: BasicListLoadMoreMode = .pixelDefault
    /// Shared fire gate across the probe and the sentinel — collapses the
    /// duplicate fires (transition + estimate steps + sentinel) into one per
    /// cooldown window. One per list identity.
    @State private var loadGate = BasicListLoadGate()

    /// Items that are already `Identifiable`.
    ///
    /// Identity contract: `id` must be unique across the array (same contract
    /// as `ForEach`) — duplicates produce undefined row identity.
    public init(
        items: [Item],
        config: BasicListConfig,
        @ViewBuilder content: @escaping (Item) -> Content
    ) where Item: Identifiable {
        self.shape = .flat(items.map { Row(item: $0, id: $0.id) })
        self.content = content
        self.config = config
    }

    /// Items that are not `Identifiable` — attach an id via closure, like
    /// `ForEach(id:)`. The returned id must be unique across the array —
    /// duplicates produce undefined row identity.
    public init(
        items: [Item],
        id: @escaping (Item) -> any Hashable,
        config: BasicListConfig,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.shape = .flat(items.map { Row(item: $0, id: AnyHashable(id($0))) })
        self.content = content
        self.config = config
    }

    /// A list of sections, each group with a sticky header (`section.header`)
    /// and an optional footer (`section.footer`).
    ///
    /// Identity contract: `section` must be unique across the array and item
    /// ids unique within each section (same contract as `ForEach`) —
    /// duplicates produce undefined identity.
    public init(
        sections: [BasicListSection<Item>],
        config: BasicListConfig,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.shape = .sectioned(sections.map { section in
            Group(
                section: section.section,
                header: section.header,
                footer: section.footer,
                rows: section.items.map { Row(item: $0, id: section.itemID($0)) })
        })
        self.content = content
        self.config = config
    }

    // MARK: Modifiers (builder-style, return Self to chain)

    /// Header at the top of the list, two modes:
    /// - `.scrollsWithContent` — scrolls with the content (default).
    /// - `.pinnedTop` — pinned to the top, sticky like a UIKit supplementary
    ///   view.
    ///
    /// ⚠️ `.pinnedTop` + sectioned is UNVERIFIED: the pinned header is a
    /// Section wrapping the groups' Sections — this combination has no caller
    /// yet; avoid it until it's needed and tested.
    public func basicListHeader(
        mode: BasicListHeaderMode = .scrollsWithContent,
        @ViewBuilder _ builder: @escaping () -> some View
    ) -> Self {
        var copy = self
        copy.headerBuilder = { AnyView(builder()) }
        copy.headerMode = mode
        return copy
    }

    /// Replacement content for the rows when the list is empty — an empty
    /// hero that runs INSIDE the list (scrolls with it, keeps the list
    /// identity across the empty/loaded phases) instead of an outer `if`
    /// branch making the list appear/disappear.
    ///
    /// With `onLoadMore` attached, the load-more sentinel still sits after the
    /// empty state — an empty list fires load-more exactly once at attach; the
    /// VM's exhausted guard decides whether more pages exist.
    public func basicListEmptyState(@ViewBuilder _ builder: @escaping () -> some View) -> Self {
        var copy = self
        copy.emptyStateBuilder = { AnyView(builder()) }
        return copy
    }

    /// Bottom content — after all rows (or the empty-state), before the
    /// load-more sentinel; suggestion categories live here so they scroll
    /// with the content like a real section of the list.
    public func basicListFooter(@ViewBuilder _ builder: @escaping () -> some View) -> Self {
        var copy = self
        copy.footerBuilder = { AnyView(builder()) }
        return copy
    }

    /// Swipe actions per row — data in, events out: the handler returns the
    /// action list per item, the list draws the buttons and reports back.
    /// `edge` defaults to `.trailing`; call again with `.leading` to get
    /// swipe from the left edge — both edges can coexist, full swipe works
    /// the same (the handler is a confirm hand-off, it never deletes the row
    /// itself). Calling the modifier again with the SAME edge REPLACES that
    /// edge's handler (not append) — the last call wins.
    public func rowSwipeActions(
        edge: HorizontalEdge = .trailing,
        _ handler: @escaping (Item) -> [BasicListSwipeAction]
    ) -> Self {
        var copy = self
        if edge == .leading {
            copy.rowSwipeLeadingHandler = handler
        } else {
            copy.rowSwipeHandler = handler
        }
        return copy
    }

    /// Long-press context menu per row — data in, events out: the menu is
    /// built per item, doesn't steal regular taps or the row's swipe gesture.
    /// VoiceOver: the SwiftUI contextMenu is exposed via rotor actions.
    public func rowContextMenu(
        @ViewBuilder _ handler: @escaping (Item) -> some View
    ) -> Self {
        var copy = self
        copy.rowContextMenuHandler = { item in AnyView(handler(item)) }
        return copy
    }

    /// Tap on a row — data in, events out like swipe actions: passing a
    /// handler gives the row a full-area tap (contentShape) that reports the
    /// item; passing none leaves the row untouched. The tap doesn't steal the
    /// horizontal drag of swipe actions so both modifiers can coexist.
    public func onRowTap(_ handler: @escaping (Item) -> Void) -> Self {
        var copy = self
        copy.rowTapHandler = handler
        return copy
    }

    /// Drag-to-reorder rows (flat list) — data in, events out: the screen
    /// passes a handler, the List reports source/destination when the user
    /// drags the handle. The handle only appears when `editMode` is
    /// `.active` (the screen controls it via `basicEditMode`); without a
    /// handler the list is untouched. Applies to the flat shape only —
    /// sectioned lists don't support reorder yet.
    public func onMoveRows(_ handler: @escaping (IndexSet, Int) -> Void) -> Self {
        var copy = self
        copy.onMoveHandler = handler
        return copy
    }

    #if os(iOS)
    /// Pins the List's `editMode` to the screen's binding — `.active` shows
    /// the drag handle of `onMoveRows`, `.inactive` returns the list to
    /// regular interaction. Without one (default) the list keeps its
    /// environment state. iOS-only: `EditMode` is unavailable on macOS.
    public func basicEditMode(_ binding: Binding<EditMode>?) -> Self {
        var copy = self
        copy.editModeBinding = binding
        return copy
    }
    #endif

    /// Pull-to-refresh. Handler errors are NOT thrown up into SwiftUI — the
    /// closure runs inside `refreshable` and the spinner ends regardless of
    /// the result (`try?` swallows the error): to present an error, handle it
    /// inside the handler (alert/state owned by the screen).
    public func onRefresh(_ handler: @escaping () async throws -> Void) -> Self {
        var copy = self
        copy.onRefreshHandler = handler
        return copy
    }

    /// Continuous load-more — mechanics documented in `BasicListBottomProbeModifier`
    /// (engine-private, this file) + `BasicListScrollSentinel` (probe on the List
    /// body, sentinel backstops short lists, loop prevention lives on the VM
    /// side). The handler is the LAST closure so trailing syntax works freely:
    /// `.onLoadMore { ... }`.
    ///
    /// The handler is NON-THROWING — handle errors inside it (alert/state owned
    /// by the screen); the engine has no error surface to present them.
    ///
    /// Fires run as unstructured Tasks (fire + cooldown retries) that are NOT
    /// cancelled when the list leaves the hierarchy — the handler may still run
    /// after the view disappears. Keep handler work VM-owned so late runs are
    /// harmless.
    ///
    /// An EMPTY list still fires once at attach through the sentinel (it
    /// materializes immediately) — the VM's exhausted/loop guards decide what
    /// happens next, the engine does not skip the fire.
    ///
    /// The mode is an ENUM passed in — the two mechanisms are mutually
    /// exclusive BY TYPE, no silent override:
    /// - `.pixelThreshold(CGFloat)` — static pixel threshold (default 600pt).
    /// - `.pagesAhead(Int)` — ASDK/IGListKit-style prefetch: loads BEFORE the
    ///   user reaches the bottom; bottom region = N × viewport height, and
    ///   inside the region the probe loads CONTINUOUSLY as pages attach until
    ///   the distance exceeds the region or pages run out (VM `exhausted`).
    ///   `.pagesAhead(2)` ≈ "keep 2 pages ahead".
    public func onLoadMore(
        mode: BasicListLoadMoreMode = .pixelDefault,
        _ handler: @escaping () async -> Void
    ) -> Self {
        var copy = self
        copy.onLoadMoreHandler = handler
        copy.loadMoreMode = mode
        return copy
    }

    // MARK: Body

    public var body: some View {
        BasicPlainList(config: config) {
            if let headerBuilder, headerMode == .pinnedTop {
                Section {
                    rowsList
                } header: {
                    headerBuilder().basicListRowStyle()
                }
            } else {
                if let headerBuilder {
                    headerBuilder().basicListRowStyle()
                }
                rowsList
            }
            if let footerBuilder {
                footerBuilder().basicListRowStyle()
            }
            if let onLoadMoreHandler {
                BasicListScrollSentinel(onLoadMore: onLoadMoreHandler, gate: loadGate)
            }
        }
        .basicListRefreshable(onRefreshHandler)
        .modifier(BasicListBottomProbeModifier(
            mode: loadMoreMode,
            gate: loadGate,
            handler: onLoadMoreHandler))
        #if os(iOS)
        .basicListEditMode(editModeBinding)
        #endif
    }

    @ViewBuilder
    private var rowsList: some View {
        // Emptiness must be computed for the EXACT shape in use (see isEmpty):
        // a sectioned list with groups would wrongly check a flat row array.
        if isEmpty, let emptyStateBuilder {
            emptyStateBuilder().basicListRowStyle()
        } else {
            switch shape {
            case .sectioned(let groups):
                ForEach(groups) { group in
                    Section {
                        ForEach(group.rows) { rowView(_: $0) }
                    } header: {
                        group.header().basicListRowStyle()
                    } footer: {
                        // A group without a declared footer → EmptyView: the List
                        // renders no footer row for that group.
                        (group.footer?() ?? AnyView(EmptyView())).basicListRowStyle()
                    }
                }
            case .flat(let rows):
                if let onMoveHandler {
                    // Flat + reorder: `.onMove` on the data ForEach itself — the drag
                    // handle appears when `editMode` is `.active`, a move reports back
                    // to the handler (the store handles local move + persistence).
                    ForEach(rows) { rowView(_: $0) }
                        .onMove(perform: onMoveHandler)
                } else {
                    ForEach(rows) { rowView(_: $0) }
                }
            }
        }
    }

    /// Whether the list has no items to show — per the shape in use: a
    /// sectioned list is empty when EVERY group is empty.
    private var isEmpty: Bool {
        switch shape {
        case .flat(let rows): return rows.isEmpty
        case .sectioned(let groups): return groups.allSatisfy(\.rows.isEmpty)
        }
    }

    private func rowView(_ row: Row) -> some View {
        contextLayer(row.item, tapLayer(row, baseRow(row)))
    }

    /// Tap layer: with a handler the row gets a full-area tap + the VoiceOver
    /// "button" trait; without one the row stays untouched.
    @ViewBuilder
    private func tapLayer(_ row: Row, _ view: some View) -> some View {
        if let rowTapHandler {
            view
                // Hit area across the full row width — the cell only covers
                // its content; taps on the padding must count too.
                .contentShape(Rectangle())
                .onTapGesture { rowTapHandler(row.item) }
                // VoiceOver: a row with an activating action must be a
                // "button" and activatable via the default action
                // (rotor/double-tap), not just the raw tap gesture.
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { rowTapHandler(row.item) }
        } else {
            view
        }
    }

    /// Context menu layer: the menu is built per item, long-press — doesn't
    /// steal regular taps or the row's swipe gesture.
    @ViewBuilder
    private func contextLayer(_ item: Item, _ view: some View) -> some View {
        if let rowContextMenuHandler {
            view.contextMenu { rowContextMenuHandler(item) }
        } else {
            view
        }
    }

    private func baseRow(_ row: Row) -> some View {
        content(row.item)
            .basicListRowStyle()
            .basicRowSwipeActions(
                rowSwipeHandler?(row.item),
                edge: .trailing,
                destructiveTint: config.destructiveActionTint)
            .basicRowSwipeActions(
                rowSwipeLeadingHandler?(row.item),
                edge: .leading,
                destructiveTint: config.destructiveActionTint)
    }
}

// MARK: - Private internals (engine only — private extension, same file)

private extension View {
    /// Refresh only when a handler exists — otherwise leave the list
    /// untouched; errors are swallowed inside refreshable itself (the pull
    /// spinner ends on its own).
    @ViewBuilder
    func basicListRefreshable(_ handler: (() async throws -> Void)?) -> some View {
        if let handler {
            refreshable { try? await handler() }
        } else {
            self
        }
    }

    #if os(iOS)
    /// Pins the List's `editMode` only when a binding exists — a list without
    /// reorder keeps its environment state.
    @ViewBuilder
    func basicListEditMode(_ binding: Binding<EditMode>?) -> some View {
        if let binding {
            self.environment(\.editMode, binding)
        } else {
            self
        }
    }
    #endif

    /// If the handler returns actions, attach them to the row; otherwise keep
    /// the row untouched. `allowsFullSwipe: true` — full swipe fires the
    /// handler immediately, but the handler is only a confirm hand-off
    /// (popup). Do NOT use `role: .destructive`:
    /// destructive-role + full swipe triggers the row slide-away animation
    /// (SwiftUI considers the row deleted) — if nothing re-renders, the row
    /// disappears even though the data is intact. The red look is kept by
    /// `.tint` on the Button — the color comes from `BasicListConfig`
    /// (`destructiveTint`), the engine never reads design tokens itself.
    /// Each action also exposes `.accessibilityAction(named:)`: the swipe
    /// gesture doesn't exist for VoiceOver, actions must be activatable from
    /// the rotor.
    @ViewBuilder
    func basicRowSwipeActions(
        _ actions: [BasicListSwipeAction]?,
        edge: HorizontalEdge,
        destructiveTint: Color
    ) -> some View {
        if let actions, !actions.isEmpty {
            #if os(watchOS) || os(tvOS)
            // Swipe actions don't exist on watchOS/tvOS — expose
            // accessibility actions only.
            self
                .basicRowSwipeAccessibility(actions)
            #else
            self
                .swipeActions(edge: edge, allowsFullSwipe: true) {
                    // Identity by position: two actions with the same title are
                    // still two separate buttons (id \.title would collide →
                    // undefined ForEach).
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        Button {
                            action.handler()
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                        // Only destructive actions take the config tint — regular
                        // actions keep the system default like the stock look. Do
                        // NOT use role .destructive (see the doc above).
                        .tint(action.isDestructive ? destructiveTint : nil)
                    }
                }
                .basicRowSwipeAccessibility(actions)
            #endif
        } else {
            self
        }
    }

    /// Swipe gestures don't exist for VoiceOver — every action must be
    /// activatable from the rotor.
    func basicRowSwipeAccessibility(_ actions: [BasicListSwipeAction]) -> some View {
        self.accessibilityActions {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                Button(action.title) { action.handler() }
            }
        }
    }

    /// The bottom probe attaches to the List BODY (`onScrollGeometryChange`
    /// observes the scroll view at the attach point): the observer lives for
    /// the whole list lifetime and receives every geometry change from the
    /// moment the list appears — this is the difference from the old approach
    /// of attaching the probe to a sentinel row, which a lazy List only
    /// materializes when the user has already scrolled near the bottom, so
    /// the observer didn't exist for the whole scroll journey and the
    /// threshold was meaningless (load-more only fired when the last cell
    /// showed up).
    ///
    /// Fires on STATE TRANSITIONS, not on scroll ticks: (1) entering the
    /// bottom region — outside the threshold → inside; (2) a new page
    /// attaching (`contentHeight` changed) while still in the region — keeps
    /// loading until the distance exceeds the region or pages run out. For a
    /// short first page — not filling a screen yet — the
    /// `BasicListScrollSentinel` backstops via `onAppear`.
    ///
    /// The gate (FIX B, F2/F3) collapses the duplicate sources (transition +
    /// estimate steps + sentinel, measured 1–400 ms apart) to one fire per
    /// cooldown window across the whole list. A legitimate chain fire that
    /// lands inside the window is NOT dropped: it retries after the window
    /// and re-checks the CURRENT geometry, so continuous loading never
    /// strands (a page is never silently skipped) while a duplicate never
    /// resurrects (the first retry consumes the window, the rest are
    /// dropped, and a retry whose region check fails is discarded).
}

/// The load-more bottom probe modifier — stateful on purpose: it keeps the
/// latest probe value so a gate-blocked chain fire can retry after the
/// cooldown window against fresh geometry (see the gate doc).
private struct BasicListBottomProbeModifier: ViewModifier {
    let mode: BasicListLoadMoreMode
    let gate: BasicListLoadGate
    let handler: (() async -> Void)?

    @State private var latestProbe: BasicListBottomProbe?

    private func threshold(for probe: BasicListBottomProbe) -> CGFloat {
        switch mode {
        case .pixelThreshold(let points):
            return points
        case .pagesAhead(let screens):
            return CGFloat(max(screens, 0)) * probe.viewportHeight
        }
    }

    func body(content: Content) -> some View {
        if let handler {
            content
                .onScrollGeometryChange(for: BasicListBottomProbe.self) { geometry in
                    BasicListBottomProbe(
                        // FIX A (F1/F4): distance measured from Apple's own
                        // visibleRect — computed by SwiftUI from offset+insets+
                        // container. Manual algebra over the parts was biased by
                        // how the list is embedded (containerSize semantics are
                        // unstable across structures — measured 782/724/702/844).
                        // visibleRect is 0 at the true bottom without insets and
                        // −bottomInset with them — identical across embeddings.
                        distanceFromBottom: geometry.contentSize.height
                            - geometry.visibleRect.maxY,
                        contentHeight: geometry.contentSize.height,
                        viewportHeight: geometry.containerSize.height)
                } action: { old, new in
                    latestProbe = new
                    let isNearBottom = new.distanceFromBottom <= threshold(for: new)
                    let wasNearBottom = old.distanceFromBottom <= threshold(for: old)
                    guard isNearBottom,
                          !wasNearBottom || new.contentHeight != old.contentHeight
                    else { return }
                    if gate.tryFire() {
                        Task { await handler() }
                    } else {
                        // Blocked by the cooldown window — a legitimate chain
                        // fire (page attached while still in the region).
                        // Retry after the window against the CURRENT geometry:
                        // out of the region → discarded; still in → fires.
                        // Duplicates blocked the same way collapse on the
                        // retry (the first one consumes the window).
                        Task {
                            try? await Task.sleep(for: .seconds(gate.cooldown))
                            guard let probe = latestProbe,
                                  probe.distanceFromBottom <= threshold(for: probe),
                                  gate.tryFire()
                            else { return }
                            await handler()
                        }
                    }
                }
        } else {
            content
        }
    }
}

/// The load-more bottom probe — values derived from scroll geometry to
/// compare against "reached the bottom region". `contentHeight` is part of
/// the probe so a new page attaching (the list grows taller) is a SEPARATE
/// change event even when the distance happens to stay the same.
/// `viewportHeight` serves the `pagesAhead` prefetch threshold (N × screens)
/// — the action closure only sees the probe value, not raw geometry.
private struct BasicListBottomProbe: Equatable {
    let distanceFromBottom: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
}
