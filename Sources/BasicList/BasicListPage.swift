import SwiftUI

// MARK: - BasicListPage — the page scaffold around the list engine
//
// The page chrome the screens of a house app share: a self-rendered header
// (title + subtitle + leading/trailing slots), an optional inline search
// field, an optional loading row — and the `BasicListView` engine filling
// the rest of the screen. Modeled on how real list screens compose (see the
// module README): the page owns the chrome, the engine owns the list, the
// screen owns the data and the events.
//
// COLORS/METRICS: passed in via `BasicListPageConfig` — the page reads no
// design layer. The inner list's `BasicListConfig` is derived from the page
// config, so a screen wires ONE config, not two.

/// Page scaffold around `BasicListView` — header, search, loading row and
/// the list engine in one view.
///
/// The page keeps the engine's three principles and adds the page anatomy:
/// - **Data in, events out** — every list behavior (swipe/tap/move/refresh/
///   load-more) and every chrome decision (slots, search text, loading flag)
///   is caller-owned state or closure; the page keeps no business state.
/// - **Immutable, modifiers return `Self`** — chain freely. Chain rule: the
///   `basicPage*` modifiers only attach DIRECTLY to the `BasicListPage`
///   value — a system modifier (`padding`, `background`, …) returns `some
///   View` and ENDS the chain, so apply system modifiers LAST.
/// - **Design goes through config** — the page chrome and the inner list
///   both take their values from the one `BasicListPageConfig` passed in.
///
/// The header is self-rendered — NO `navigationTitle` — so the page runs
/// standalone (a sheet, a fullScreenCover, a plain root) and inside a
/// `NavigationStack` alike, without fighting the system bar.
///
/// ```swift
/// BasicListPage(title: "Accounts", items: accounts, config: .pageHouse) { account in
///     AccountRowView(account)
/// }
/// .basicPageSearch($query, prompt: "Search accounts")
/// .basicPageTrailing { Button { … } label: { Image(systemName: "plus") } }
/// .basicPageRowTap { route(to: $0) }
/// .basicPageRowSwipeActions { account in deleteActions(for: account) }
/// .basicPageRefresh { try await api.reload() }
/// .basicPageLoadMore { try? await api.nextPage() }
///
/// BasicListPage(title: "Log", subtitle: "October", sections: dayGroups, config: .pageHouse) { transaction in
///     TransactionRowView(transaction)
/// }
/// ```
///
/// Forwarding contract: every engine modifier has a `basicPage*` twin that
/// forwards to the inner list unchanged (replace semantics included — the
/// last call wins), so a page exposes exactly the engine's behavior surface,
/// nothing invented on top:
///
/// | Page modifier | Forwards to |
/// |---|---|
/// | `.basicPageListHeader(mode:_:)` | `.basicListHeader(mode:_:)` |
/// | `.basicPageEmptyState(_:)` | `.basicListEmptyState(_:)` |
/// | `.basicPageFooter(_:)` | `.basicListFooter(_:)` |
/// | `.basicPageRowSwipeActions(edge:allowsFullSwipe:_:)` | `.rowSwipeActions(edge:allowsFullSwipe:_:)` |
/// | `.basicPageRowContextMenu(_:)` | `.rowContextMenu(_:)` |
/// | `.basicPageRowTap(_:)` | `.onRowTap(_:)` |
/// | `.basicPageMoveRows(_:)` | `.onMoveRows(_:)` |
/// | `.basicPageEditMode(_:)` (iOS) | `.basicEditMode(_:)` |
/// | `.basicPageRefresh(_:)` | `.onRefresh(_:)` |
/// | `.basicPageLoadMore(mode:_:)` | `.onLoadMore(mode:_:)` |
///
/// Page chrome beyond the table: `.basicPageLeading`, `.basicPageTrailing`,
/// `.basicPageSearch(_:prompt:)`, `.basicPageIsLoading(_:)` and
/// `.basicPageDatePager(text:windowStart:anchor:unit:onNavigate:)` mount
/// the page's own chrome pieces (slots, inline search, loading row, the
/// below-list date pager).
///
/// Accessibility: the title carries the heading trait (VoiceOver rotor
/// navigation), the search field reads its prompt, the loading row is a
/// plain system `ProgressView` (announced by the platform), and the inner
/// list keeps the engine's full VoiceOver support (button trait, rotor
/// actions, swipe-as-actions on watchOS/tvOS).
public struct BasicListPage<Item, Content: View>: View {

    /// Page title — the mandatory first line of the header. `package` so the
    /// host test suite can pin the init wiring; invisible to consumers
    /// either way.
    package let title: String
    /// Optional subtitle line under the title — `nil` renders no subtitle.
    package let subtitle: String?

    /// Colors/metrics passed in by the caller (see `BasicListPageConfig`) —
    /// the page never reads design values by itself.
    package let config: BasicListPageConfig
    /// The inner list's engine config, derived once from the page config
    /// (`package` — host tests pin the derivation).
    package let listConfig: BasicListConfig

    /// The inner engine — built at construction with the default empty state
    /// applied; every `basicPage*` forwarding modifier re-chains it. Storing
    /// the view (not a builder closure) keeps the engine's DEBUG identity
    /// assertions at init time, exactly where they fire for a bare
    /// `BasicListView`.
    package var innerList: BasicListView<Item, Content>

    /// Chrome slots — `nil` renders nothing (the header collapses to the
    /// title block). `package` so the host tests can pin the forwarding.
    package var leadingSlot: (() -> AnyView)?
    package var trailingSlot: (() -> AnyView)?
    /// Inline search — `nil` renders no search field; when present, the
    /// binding is the caller's state (the page never keeps the text).
    package var searchBinding: Binding<String>?
    package var searchPrompt: String?
    /// Loading row above the list — caller-owned flag; the list is never
    /// swapped out for a spinner (identity stays stable).
    package var isLoading: Bool = false
    /// Date pager below the list — `nil` renders no pager; when present,
    /// the window label/binding/anchor/unit are all caller inputs (see
    /// `BasicListDatePager` — the pager owns only the mechanical stepping).
    package var datePagerSpec: BasicListPageDatePagerSpec?
    /// Content identity key of the list — when set, the inner list is
    /// rebuilt under a NEW identity whenever the key changes, so the
    /// attached transition animates the flip (the date-paging pattern:
    /// key by the window start, slide per direction). `nil` = the list
    /// keeps one identity for the page's lifetime.
    package var contentKey: AnyHashable?
    /// Transition of the keyed content — applied together with
    /// `contentKey`; `nil` = default (no explicit transition).
    package var contentTransition: AnyTransition?

    /// `Identifiable` items — same identity contract as the engine: `id`
    /// must be unique across the array.
    public init(
        title: String,
        subtitle: String? = nil,
        items: [Item],
        config: BasicListPageConfig,
        @ViewBuilder content: @escaping (Item) -> Content
    ) where Item: Identifiable {
        self.title = title
        self.subtitle = subtitle
        self.config = config
        self.listConfig = config.listConfig
        self.leadingSlot = nil
        self.trailingSlot = nil
        self.searchBinding = nil
        self.searchPrompt = nil
        self.isLoading = false
        self.datePagerSpec = nil
        self.contentKey = nil
        self.contentTransition = nil
        self.innerList = BasicListView(items: items, config: config.listConfig, content: content)
            .basicListEmptyState { BasicListPageDefaultEmptyState(config: config) }
    }

    /// Items that are not `Identifiable` — attach an id via closure, like
    /// `ForEach(id:)` / the engine's `init(items:id:config:content:)`. The
    /// returned id must be unique across the array.
    public init<ID: Hashable>(
        title: String,
        subtitle: String? = nil,
        items: [Item],
        id: @escaping (Item) -> ID,
        config: BasicListPageConfig,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.config = config
        self.listConfig = config.listConfig
        self.leadingSlot = nil
        self.trailingSlot = nil
        self.searchBinding = nil
        self.searchPrompt = nil
        self.isLoading = false
        self.datePagerSpec = nil
        self.contentKey = nil
        self.contentTransition = nil
        self.innerList = BasicListView(
            items: items, id: id, config: config.listConfig, content: content)
            .basicListEmptyState { BasicListPageDefaultEmptyState(config: config) }
    }

    /// A page of sections — each group keeps its sticky header from the
    /// engine (`BasicListSection`), the page adds the chrome around it.
    public init(
        title: String,
        subtitle: String? = nil,
        sections: [BasicListSection<Item>],
        config: BasicListPageConfig,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.config = config
        self.listConfig = config.listConfig
        self.leadingSlot = nil
        self.trailingSlot = nil
        self.searchBinding = nil
        self.searchPrompt = nil
        self.isLoading = false
        self.datePagerSpec = nil
        self.contentKey = nil
        self.contentTransition = nil
        self.innerList = BasicListView(sections: sections, config: config.listConfig, content: content)
            .basicListEmptyState { BasicListPageDefaultEmptyState(config: config) }
    }

    // MARK: Page chrome modifiers (builder-style, return Self to chain)

    /// Slot at the leading edge of the header — the nav-bar-leading role of
    /// a screen (a period menu, a close button) without a navigation bar.
    /// Rendered LEFT of the title block. Calling again replaces the slot
    /// (the last call wins); an `EmptyView` is the way to leave it empty.
    public func basicPageLeading(
        @ViewBuilder _ builder: @escaping () -> some View
    ) -> Self {
        var copy = self
        copy.leadingSlot = { AnyView(builder()) }
        return copy
    }

    /// Slot at the trailing edge of the header — the screen's actions (add
    /// button, filter menu). Rendered RIGHT of the title block, after the
    /// flexible title space. Calling again replaces the slot (the last call
    /// wins).
    public func basicPageTrailing(
        @ViewBuilder _ builder: @escaping () -> some View
    ) -> Self {
        var copy = self
        copy.trailingSlot = { AnyView(builder()) }
        return copy
    }

    /// Inline search field right under the header — NOT `.searchable`, so
    /// the page runs outside a `NavigationStack` (sheet, cover, plain root)
    /// and never fights the system bar placement inside one. The binding is
    /// the caller's state — the page renders the text and nothing else;
    /// filtering the data stays on the caller's side (data in, events out).
    ///
    /// `prompt` is the field's placeholder (defaults to none). The field
    /// carries no clear button — the keyboard's own affordances and the
    /// caller's trailing slot cover it; the scaffold adds no package-owned
    /// strings.
    public func basicPageSearch(
        _ text: Binding<String>,
        prompt: String? = nil
    ) -> Self {
        var copy = self
        copy.searchBinding = text
        copy.searchPrompt = prompt
        return copy
    }

    /// Shows the loading row between the chrome and the list while `true` —
    /// a plain system `ProgressView` tinted with
    /// `BasicListPageConfig.progressTint`. The row sits ABOVE the list and
    /// does not replace it: list identity is never lost across the loading/
    /// loaded phases (first-load skeletons belong to the caller's screen —
    /// this flag is for the light "busy" case).
    public func basicPageIsLoading(_ loading: Bool) -> Self {
        var copy = self
        copy.isLoading = loading
        return copy
    }

    /// Date pager below the list — `‹ previous — window label — next ›`,
    /// the period-paging row of time-windowed pages (the BudgetDetail
    /// stepper pattern, genericized in `BasicListDatePager`). One tap steps
    /// `windowStart` by one `unit`; forward stops at `anchor` (the newest
    /// page), back is always available.
    ///
    /// The caller owns the wording and the format: `text` is the window
    /// label, re-computed per body pass from `windowStart` with the
    /// caller's own date formatter — the package never formats dates.
    /// `onNavigate` reports the flip direction (`true` = next date) so the
    /// caller can pick the slide direction for
    /// `.basicPageContentKey(_:transition:)` — pair the two for the full
    /// page-flip effect. Colors/font come from `BasicListPageConfig`
    /// (`pager*` fields).
    public func basicPageDatePager(
        text: String,
        windowStart: Binding<Date>,
        anchor: Date,
        unit: BasicListPeriodUnit,
        onNavigate: ((Bool) -> Void)? = nil
    ) -> Self {
        var copy = self
        copy.datePagerSpec = BasicListPageDatePagerSpec(
            text: text,
            windowStart: windowStart,
            anchor: anchor,
            unit: unit,
            onNavigate: onNavigate)
        return copy
    }

    /// Keys the page's LIST CONTENT by `id` — changing the key rebuilds the
    /// list under a new identity inside the animation in flight, so the
    /// `transition` animates the content flip while the chrome (header,
    /// search, pager) stays put. This is the time-paging pattern of a
    /// windowed page: key by the window start and slide per direction —
    ///
    /// ```swift
    /// .basicPageContentKey(windowStart, transition: .asymmetric(
    ///     insertion: .move(edge: pageForward ? .trailing : .leading),
    ///     removal: .move(edge: pageForward ? .leading : .trailing)))
    /// ```
    ///
    /// The pager's `withAnimation` spring (`.basicPageDatePager`) is the
    /// animation that drives it. A key change also RESETS the list's
    /// internal state (scroll position, load-more gate) — exactly what a
    /// new page wants. Without the modifier the list keeps one identity for
    /// the page's lifetime.
    public func basicPageContentKey(
        _ id: some Hashable,
        transition: AnyTransition? = nil
    ) -> Self {
        var copy = self
        copy.contentKey = AnyHashable(id)
        copy.contentTransition = transition
        return copy
    }

    // MARK: Forwarding modifiers — the engine's behavior surface, renamed

    /// In-list header of the inner engine — the page's own title header and
    /// this are different things: this is content at the top of the LIST
    /// (a balance card, a summary strip). Forwards to
    /// `BasicListView.basicListHeader(mode:_:)` unchanged, replace
    /// semantics included (the last call wins).
    public func basicPageListHeader(
        mode: BasicListHeaderMode = .scrollsWithContent,
        @ViewBuilder _ builder: @escaping () -> some View
    ) -> Self {
        var copy = self
        copy.innerList = copy.innerList.basicListHeader(mode: mode) { builder() }
        return copy
    }

    /// Replacement for the page's DEFAULT empty state (see
    /// `BasicListPageConfig` — icon/title/message come from the config).
    /// Forwards to `BasicListView.basicListEmptyState(_:)`: the content runs
    /// INSIDE the list, keeping list identity across the empty/loaded
    /// phases. Calling again replaces the previous builder (the last call
    /// wins) — including the default the page applied at construction.
    public func basicPageEmptyState(
        @ViewBuilder _ builder: @escaping () -> some View
    ) -> Self {
        var copy = self
        copy.innerList = copy.innerList.basicListEmptyState { builder() }
        return copy
    }

    /// Bottom content of the inner engine — after all rows (or the empty
    /// state). Forwards to `BasicListView.basicListFooter(_:)` unchanged.
    public func basicPageFooter(
        @ViewBuilder _ builder: @escaping () -> some View
    ) -> Self {
        var copy = self
        copy.innerList = copy.innerList.basicListFooter { builder() }
        return copy
    }

    /// Swipe actions per row. Forwards to
    /// `BasicListView.rowSwipeActions(edge:allowsFullSwipe:_:)` unchanged —
    /// both edges coexist, `allowsFullSwipe` passes through, replace
    /// semantics per edge (the last call wins).
    public func basicPageRowSwipeActions(
        edge: HorizontalEdge = .trailing,
        allowsFullSwipe: Bool = true,
        _ handler: @escaping (Item) -> [BasicListSwipeAction]
    ) -> Self {
        var copy = self
        copy.innerList = copy.innerList.rowSwipeActions(
            edge: edge, allowsFullSwipe: allowsFullSwipe, handler)
        return copy
    }

    /// Long-press context menu per row. Forwards to
    /// `BasicListView.rowContextMenu(_:)` unchanged — doesn't steal regular
    /// taps or swipes.
    public func basicPageRowContextMenu(
        @ViewBuilder _ handler: @escaping (Item) -> some View
    ) -> Self {
        var copy = self
        copy.innerList = copy.innerList.rowContextMenu { handler($0) }
        return copy
    }

    /// Full-area row tap. Forwards to `BasicListView.onRowTap(_:)`
    /// unchanged — VoiceOver button trait included.
    public func basicPageRowTap(_ handler: @escaping (Item) -> Void) -> Self {
        var copy = self
        copy.innerList = copy.innerList.onRowTap(handler)
        return copy
    }

    /// Drag-to-reorder rows (flat shape). Forwards to
    /// `BasicListView.onMoveRows(_:)` unchanged — the handle appears when
    /// the edit mode is `.active` (see `.basicPageEditMode`).
    public func basicPageMoveRows(_ handler: @escaping (IndexSet, Int) -> Void) -> Self {
        var copy = self
        copy.innerList = copy.innerList.onMoveRows(handler)
        return copy
    }

    #if os(iOS)
    /// Pins the inner list's `editMode` — `.active` shows the drag handle of
    /// `.basicPageMoveRows`. Forwards to `BasicListView.basicEditMode(_:)`
    /// unchanged. iOS-only: `EditMode` is unavailable on macOS.
    public func basicPageEditMode(_ binding: Binding<EditMode>?) -> Self {
        var copy = self
        copy.innerList = copy.innerList.basicEditMode(binding)
        return copy
    }
    #endif

    /// Pull-to-refresh. Forwards to `BasicListView.onRefresh(_:)` unchanged
    /// — handler errors are handled inside the handler (the spinner ends by
    /// itself).
    public func basicPageRefresh(_ handler: @escaping () async throws -> Void) -> Self {
        var copy = self
        copy.innerList = copy.innerList.onRefresh(handler)
        return copy
    }

    /// Continuous load-more. Forwards to
    /// `BasicListView.onLoadMore(mode:_:)` unchanged — the mode enum
    /// (`.pixelThreshold` / `.pagesAhead`) and the cooldown gate pass
    /// through as-is. The last call wins.
    public func basicPageLoadMore(
        mode: BasicListLoadMoreMode = .pixelDefault,
        _ handler: @escaping () async -> Void
    ) -> Self {
        var copy = self
        copy.innerList = copy.innerList.onLoadMore(mode: mode, handler)
        return copy
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            pageHeader
            if let searchBinding {
                BasicListPageSearchField(
                    text: searchBinding, prompt: searchPrompt, config: config)
            }
            if isLoading {
                loadingRow
            }
            innerList
                .basicPageKeyedContent(key: contentKey, transition: contentTransition)
                .padding(.top, config.headerListSpacing)
            if let datePagerSpec {
                // BELOW the list — the BudgetDetail placement: content
                // scrolls above the pager, the pager never leaves the
                // screen. The look comes from the config (`pager*` fields).
                BasicListDatePager(
                    text: datePagerSpec.text,
                    windowStart: datePagerSpec.windowStart,
                    anchor: datePagerSpec.anchor,
                    unit: datePagerSpec.unit,
                    onNavigate: datePagerSpec.onNavigate,
                    chevronColor: config.pagerChevronColor,
                    textColor: config.pagerTextColor,
                    textFont: config.pagerTextFont)
            }
        }
        .background(config.backgroundColor)
    }

    /// The chrome row: leading slot — title block (flexible) — trailing
    /// slot. The paddings are package-internal chrome layout (see
    /// `BasicListPageConfig`'s doc for what stays internal); the title
    /// carries the heading trait for VoiceOver rotor navigation.
    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            if let leadingSlot {
                leadingSlot()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(config.titleFont)
                    .foregroundStyle(config.titleColor)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(config.subtitleFont)
                        .foregroundStyle(config.subtitleColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailingSlot {
                trailingSlot()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// The light busy indicator — a bare system `ProgressView` (the platform
    /// announces it; the page adds no package-owned strings). It never
    /// replaces the list, so identity stays stable across phases.
    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
                .tint(config.progressTint)
            Spacer()
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Private chrome pieces (page only — private, same file)

private extension View {
    /// Applies the page's content identity key + transition — all four
    /// combinations (key/transition present or nil) so the list is touched
    /// as little as possible when the caller sets none.
    @ViewBuilder
    func basicPageKeyedContent(
        key: AnyHashable?, transition: AnyTransition?
    ) -> some View {
        if let key, let transition {
            self.id(key).transition(transition)
        } else if let key {
            self.id(key)
        } else if let transition {
            self.transition(transition)
        } else {
            self
        }
    }
}

/// The page's inline search field — a pill under the header, NOT
/// `.searchable` (see `.basicPageSearch`). A `TextField` in a tinted
/// capsule: the glyph is decorative, the field reads its prompt via
/// VoiceOver, and there is no clear button (the scaffold adds no
/// package-owned strings — the keyboard's own affordances cover it).
private struct BasicListPageSearchField: View {
    @Binding var text: String
    let prompt: String?
    let config: BasicListPageConfig

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(config.searchForeground)
                .accessibilityHidden(true)
            TextField(prompt ?? "", text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .foregroundStyle(config.searchForeground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            config.searchBackground,
            in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

/// The page's fallback empty state — applied at construction when the
/// caller never chains `.basicPageEmptyState`. Icon/title/message/colors
/// all come from the config (see `BasicListPageConfig`); like the engine's
/// empty state it runs INSIDE the list, so list identity is stable across
/// the empty/loaded phases.
private struct BasicListPageDefaultEmptyState: View {
    let config: BasicListPageConfig

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: config.emptyIcon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(config.emptyIconColor)
            Text(config.emptyTitle)
                .font(config.titleFont)
                .foregroundStyle(config.titleColor)
                .multilineTextAlignment(.center)
            if let message = config.emptyMessage {
                Text(message)
                    .font(config.subtitleFont)
                    .foregroundStyle(config.subtitleColor)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

/// Caller inputs of the page's date pager, stored verbatim by
/// `.basicPageDatePager` and unpacked into `BasicListDatePager` at render —
/// `package` so the host tests can pin the wiring (binding, anchor, unit,
/// direction callback). The pager owns the stepping; this struct owns
/// nothing.
package struct BasicListPageDatePagerSpec {
    package let text: String
    package let windowStart: Binding<Date>
    package let anchor: Date
    package let unit: BasicListPeriodUnit
    package let onNavigate: ((Bool) -> Void)?
}
