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
/// .onLoadMore { try await api.nextPage() }
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

    private let isSectioned: Bool
    private let groups: [Group]
    private let rows: [Row]
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
    private var loadMoreMode: BasicListLoadMoreMode =
        .pixelThreshold(BasicListScrollSentinel.defaultBottomThreshold)

    /// Items that are already `Identifiable`.
    public init(
        items: [Item],
        config: BasicListConfig,
        @ViewBuilder content: @escaping (Item) -> Content
    ) where Item: Identifiable {
        self.isSectioned = false
        self.groups = []
        self.rows = items.map { Row(item: $0, id: $0.id) }
        self.content = content
        self.config = config
    }

    /// Items that are not `Identifiable` — attach an id via closure, like
    /// `ForEach(id:)`.
    public init(
        items: [Item],
        id: @escaping (Item) -> any Hashable,
        config: BasicListConfig,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.isSectioned = false
        self.groups = []
        self.rows = items.map { Row(item: $0, id: AnyHashable(id($0))) }
        self.content = content
        self.config = config
    }

    /// A list of sections, each group with a sticky header (`section.header`)
    /// and an optional footer (`section.footer`).
    public init(
        sections: [BasicListSection<Item>],
        config: BasicListConfig,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.isSectioned = true
        self.groups = sections.map { section in
            Group(
                section: section.section,
                header: section.header,
                footer: section.footer,
                rows: section.items.map { Row(item: $0, id: section.itemID($0)) })
        }
        self.rows = []
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
    /// itself).
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

    /// Continuous load-more — mechanics documented in `.basicListBottomProbe`
    /// + `BasicListScrollSentinel` (probe on the List body, sentinel backstops
    /// short lists, loop prevention lives on the VM side). The handler is the
    /// LAST closure so trailing syntax works freely: `.onLoadMore { ... }`.
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
        mode: BasicListLoadMoreMode = .pixelThreshold(BasicListScrollSentinel.defaultBottomThreshold),
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
                BasicListScrollSentinel(onLoadMore: onLoadMoreHandler)
            }
        }
        .basicListRefreshable(onRefreshHandler)
        .basicListBottomProbe(
            mode: loadMoreMode,
            onLoadMoreHandler)
        #if os(iOS)
        .basicListEditMode(editModeBinding)
        #endif
    }

    @ViewBuilder
    private var rowsList: some View {
        // Emptiness must be computed for the EXACT shape in use: a sectioned
        // list keeps its data in `groups` (`rows` is always empty) — checking
        // `rows.isEmpty` on a sectioned list with data would wrongly show the
        // empty state.
        if isEmpty, let emptyStateBuilder {
            emptyStateBuilder().basicListRowStyle()
        } else if isSectioned {
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
        } else if let onMoveHandler {
            // Flat + reorder: `.onMove` on the data ForEach itself — the drag
            // handle appears when `editMode` is `.active`, a move reports back
            // to the handler (the store handles local move + persistence).
            ForEach(rows) { rowView(_: $0) }
                .onMove(perform: onMoveHandler)
        } else {
            ForEach(rows) { rowView(_: $0) }
        }
    }

    /// Whether the list has no items to show — per the shape in use.
    private var isEmpty: Bool {
        isSectioned ? groups.allSatisfy(\.rows.isEmpty) : rows.isEmpty
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
            self.swipeActions(edge: edge, allowsFullSwipe: true) {
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
            .accessibilityActions {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action.title) { action.handler() }
                }
            }
        } else {
            self
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
    /// `BasicListScrollSentinel` backstops via `onAppear`. Duplicate fires
    /// (probe + sentinel together) are blocked on the VM side:
    /// `Paging.inFlight` blocks parallel loads, `exhausted` skips when out of
    /// pages — the probe keeps no state, the action is stateless (old/new come
    /// from the modifier itself).
    @ViewBuilder
    func basicListBottomProbe(
        mode: BasicListLoadMoreMode,
        _ handler: (() async -> Void)?
    ) -> some View {
        if let handler {
            onScrollGeometryChange(for: BasicListBottomProbe.self) { geometry in
                BasicListBottomProbe(
                    distanceFromBottom: geometry.contentSize.height
                        - geometry.contentInsets.bottom
                        - (geometry.contentOffset.y + geometry.containerSize.height),
                    contentHeight: geometry.contentSize.height,
                    viewportHeight: geometry.containerSize.height)
            } action: { old, new in
                // The mode decides the region: .pagesAhead → threshold in
                // VIEWPORT units (screens) — ASDK-style leadingScreens
                // prefetch, the region scales with the current viewport;
                // .pixelThreshold → static pixel threshold.
                let threshold: CGFloat
                switch mode {
                case .pixelThreshold(let points):
                    threshold = points
                case .pagesAhead(let screens):
                    threshold = CGFloat(max(screens, 0)) * new.viewportHeight
                }
                let isNearBottom = new.distanceFromBottom <= threshold
                let wasNearBottom = old.distanceFromBottom <= threshold
                guard isNearBottom,
                      !wasNearBottom || new.contentHeight != old.contentHeight
                else { return }
                Task { await handler() }
            }
        } else {
            self
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

// MARK: - Preview
//
// Live demo of the engine — 6 shapes: flat (swipe/tap/load-more/empty-state),
// sectioned (sticky header), few rows, pagination + refresh, slow refresh,
// refresh error handled inside the handler. Data is English transaction
// fixtures rendered through `PreviewRow` (round glyph + title + subtitle +
// money) so every shape has its own look, without going through the app's
// Localizable tables. Neutral config (the real design values are passed by
// the caller — the app passes `BasicListConfig.house`).

private let previewConfig = BasicListConfig(
    destructiveActionTint: .red, bottomClearance: 60)

private struct PreviewItem: Identifiable {
    let id = UUID()
    let title: String
    let note: String
    let symbol: String
    let amount: Double
    let isIncome: Bool
}

/// English transaction fixtures shared by every preview — diverse enough in
/// glyphs/colors/money that the demo shapes don't look alike. The strings are
/// preview fixtures, not routed through the app's Localizable tables.
private let previewFixtures: [
    (title: String, note: String, symbol: String, amount: Double, isIncome: Bool)
] = [
    ("Whole Foods", "Groceries", "cart.fill", 86.40, false),
    ("Salary", "October payroll", "banknote.fill", 2_400, true),
    ("Uber", "Commute", "car.fill", 14.20, false),
    ("Freelance", "Logo project", "laptopcomputer", 350, true),
    ("Netflix", "Monthly plan", "play.tv.fill", 15.99, false),
    ("Rent", "Apartment", "house.fill", 780, false),
    ("Coffee", "Latte, size M", "cup.and.saucer.fill", 4.50, false),
    ("Dividend", "Quarterly payout", "chart.line.uptrend.xyaxis", 62.30, true),
]

/// Item from the fixture (1-based index, wraps around) — `note` overrides the
/// fixture label when the caller needs its own (e.g. "Loaded round 2").
private func fixtureItem(at index: Int, note: String? = nil) -> PreviewItem {
    let fixture = previewFixtures[(index - 1) % previewFixtures.count]
    return PreviewItem(
        title: fixture.title, note: note ?? fixture.note,
        symbol: fixture.symbol, amount: fixture.amount,
        isIncome: fixture.isIncome)
}

/// Item from the fixture with a page label — the load-more rhythm shows up
/// right in the data.
private func pagedFixtureItem(at index: Int, page: Int) -> PreviewItem {
    fixtureItem(at: index, note: "\(previewFixtures[(index - 1) % previewFixtures.count].note) · page \(page)")
}

/// "+$2,400.00" / "−$86.40" — income green, expense regular, digits uniform
/// (monospaced) so the money column stays aligned.
private func previewAmount(_ item: PreviewItem) -> String {
    String(format: item.isIncome ? "+$%.2f" : "−$%.2f", item.amount)
}

/// Demo row for previews: colored round glyph + title + subtitle + money —
/// closer to the opening bars of a real app cell than a bare `Text`.
private struct PreviewRow: View {
    let item: PreviewItem

    private var tint: Color { item.isIncome ? .green : .orange }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(item.note)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(previewAmount(item))
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(item.isIncome ? Color.green : Color.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .basicListRowStyle()
    }
}

/// Demo header — title + subtitle explaining the scenario, replacing a bare
/// `Text` that is hard to tell apart across previews.
private struct PreviewHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
            Text(subtitle)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Previews are built through dedicated structs — complex logic (state
/// mutations inside closures) crammed straight into a #Preview macro crashes
/// the type-checker.
private struct FlatListPreview: View {
    @State private var items: [PreviewItem] = (1...12).map { fixtureItem(at: $0) }
    @State private var loadRound = 0

    var body: some View {
        BasicListView(items: items, config: previewConfig) { PreviewRow(item: $0) }
            .basicListHeader {
                PreviewHeader(
                    title: "Demo list",
                    subtitle: "Swipe left · tap-hold for menu · tap to remove · scroll to bottom to load more")
            }
            .basicListEmptyState {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Nothing here — every row was removed")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(40)
            }
            .rowSwipeActions { _ in
                [BasicListSwipeAction(title: "Delete", systemImage: "trash", isDestructive: true) {}]
            }
            .rowContextMenu { item in
                Button("Copy \"\(item.title)\"") {}
            }
            .onRowTap { tapped in
                items.removeAll { $0.id == tapped.id }
            }
            .onLoadMore {
                try? await Task.sleep(for: .seconds(0.3))
                loadRound += 1
                items += (1...6).map { offset in
                    fixtureItem(
                        at: loadRound * 6 + offset,
                        note: "Loaded round \(loadRound)")
                }
            }
            // Neutral preview background — the module never sees app design
            // modifiers.
            .background(Color.secondary.opacity(0.12))
    }
}

private struct SectionedListPreview: View {
    /// Group header: day label + transaction count — sticky while scrolling
    /// (the counterpart of sectionHeadersPinToVisibleBounds) so it must be
    /// self-sufficient in context, never relying on content that has already
    /// scrolled past.
    private static func sectionHeader(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count) transactions")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    static let sections: [BasicListSection<PreviewItem>] = [
        BasicListSection(section: "Today", items: [
            fixtureItem(at: 7), fixtureItem(at: 3), fixtureItem(at: 1),
        ], itemID: \.id) {
            sectionHeader("TODAY", count: 3)
        } footer: {
            Text("End of TODAY — footer per group")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        },
        BasicListSection(section: "Yesterday", items: [
            fixtureItem(at: 5), fixtureItem(at: 6),
        ], itemID: \.id) {
            sectionHeader("YESTERDAY", count: 2)
        },
    ]

    var body: some View {
        BasicListView(sections: Self.sections, config: previewConfig) { PreviewRow(item: $0) }
            .basicListHeader {
                PreviewHeader(
                    title: "Day groups",
                    subtitle: "Sticky headers pin while scrolling · optional group footer")
            }
            .background(Color.secondary.opacity(0.12))
    }
}

/// 3 rows — under one screen: no onLoadMore attached, so the bottom probe has
/// no meaning (a short list produces no geometry change after attach); header
/// and footer still scroll with content, swipe + tap stay alive. The "little
/// data"
/// shape of real apps: a few rows must keep the exact rhythm, no artificial
/// blank space.
private struct FewItemsPreview: View {
    @State private var items = [7, 3, 1].map { fixtureItem(at: $0) }

    var body: some View {
        BasicListView(items: items, config: previewConfig) { PreviewRow(item: $0) }
            .basicListHeader {
                PreviewHeader(
                    title: "Small list",
                    subtitle: "3 rows — no load-more attached, nothing fires")
            }
            .basicListFooter {
                Text("Footer scrolls with content")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            .rowSwipeActions { item in
                [BasicListSwipeAction(
                    title: "Delete \(item.title)", systemImage: "trash",
                    isDestructive: true) {}]
            }
            .rowSwipeActions(edge: .leading) { _ in
                [BasicListSwipeAction(title: "Pin", systemImage: "pin.fill") {}]
            }
            .onRowTap { tapped in
                items.removeAll { $0.id == tapped.id }
            }
            .background(Color.secondary.opacity(0.12))
    }
}

/// 4 pages × 25 rows — the first page is long enough to really scroll: once
/// in the bottom region the probe fires, a page attaching inside the region
/// keeps it loading CONTINUOUSLY until page 4; out of pages the handler
/// no-ops — mimicking the VM-side `exhausted`, where the real thing blocks
/// duplicate probe + sentinel fires. Refresh overrides load-more: back to
/// page 1 rebuilding the data — two mechanisms sharing one list with no
/// identity conflict.
private struct PagedListPreview: View {
    private static let rowsPerPage = 25
    private static let lastPage = 4

    @State private var page = 1
    @State private var items = (1...25).map { pagedFixtureItem(at: $0, page: 1) }

    var body: some View {
        BasicListView(items: items, config: previewConfig) { PreviewRow(item: $0) }
            .basicListHeader {
                PreviewHeader(
                    title: "Recent activity",
                    subtitle: page < Self.lastPage
                        ? "Page \(page)/\(Self.lastPage) — prefetching 2 screens ahead"
                        : "Page \(page)/\(Self.lastPage) — exhausted, load-more no-ops")
            }
            .onRefresh {
                try? await Task.sleep(for: .seconds(0.8))
                page = 1
                items = (1...Self.rowsPerPage).map { pagedFixtureItem(at: $0, page: 1) }
            }
            .onLoadMore(mode: .pagesAhead(2)) {
                guard page < Self.lastPage else { return }
                try? await Task.sleep(for: .seconds(0.4))
                let next = page + 1
                items += (1...Self.rowsPerPage).map {
                    pagedFixtureItem(at: (next - 1) * Self.rowsPerPage + $0, page: next)
                }
                page = next
            }
            .background(Color.secondary.opacity(0.12))
    }
}

/// A long-enough refresh spinner (1.5s) to clearly see the pull: the spinner
/// holds until the handler finishes and ends by itself — no tick fan-out.
/// The header counts pulls proving each pull is exactly one round;
/// `items.shuffle()` gives a visible change after every pull.
private struct SlowRefreshPreview: View {
    @State private var refreshCount = 0
    @State private var items = [7, 3, 1, 5].map { fixtureItem(at: $0) }

    var body: some View {
        BasicListView(items: items, config: previewConfig) { PreviewRow(item: $0) }
            .basicListHeader {
                PreviewHeader(
                    title: "Wallet",
                    subtitle: "Refreshed ×\(refreshCount) — pull to refresh (1.5s)")
            }
            .onRefresh {
                try? await Task.sleep(for: .seconds(1.5))
                refreshCount += 1
                items.shuffle()
            }
            .background(Color.secondary.opacity(0.12))
    }
}

/// An error thrown by the handler gets swallowed by refreshable — the spinner
/// ends by itself, NOTHING shows up in SwiftUI: to present an error you must
/// handle it inside the handler (see `.onRefresh` docs). The preview catches
/// the error and shows a footer banner — pull refresh makes it visible,
/// demonstrating the "error handled in the handler" path.
private enum PreviewRefreshError: String, Error {
    case networkDown = "network down (simulated)"
}

private struct RefreshErrorPreview: View {
    @State private var lastError: String?

    var body: some View {
        BasicListView(items: [7, 2].map { fixtureItem(at: $0) }, config: previewConfig) { PreviewRow(item: $0) }
            .basicListHeader {
                PreviewHeader(
                    title: "Sync",
                    subtitle: "Pull to refresh — fails on purpose")
            }
            .basicListFooter {
                if let lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundStyle(.red)
                        .padding(12)
                }
            }
            .onRefresh {
                do {
                    try await Task.sleep(for: .seconds(0.8))
                    throw PreviewRefreshError.networkDown
                } catch {
                    lastError = error.localizedDescription
                }
            }
            .background(Color.secondary.opacity(0.12))
    }
}

#Preview("Flat — swipe, tap, load-more") {
    FlatListPreview()
}

#Preview("Sectioned — sticky headers") {
    SectionedListPreview()
}

#Preview("Flat — few rows (no load-more)") {
    FewItemsPreview()
}

#Preview("Flat — 4 pages, load-more + refresh") {
    PagedListPreview()
}

#Preview("Refresh — slow spinner") {
    SlowRefreshPreview()
}

#Preview("Refresh — error handled in handler") {
    RefreshErrorPreview()
}
