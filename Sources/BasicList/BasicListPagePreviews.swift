// Preview/demo code ships with the LIBRARY target — wrap the whole file in
// `#if DEBUG` so consumers never compile the demo shapes + fixtures into
// their release builds (debug builds keep the full catalog).
#if DEBUG
import SwiftUI

// MARK: - BasicListPage preview catalog
//
// Live demo suite for the page scaffold — one preview per chrome capability,
// mirroring the engine's catalog shape (BasicListPreviews.swift). All demo
// fixtures/configs here are file-private; the real design values stay with
// the caller. Page fixtures are SEPARATE from the engine's fixtures so each
// catalog stays tweakable in isolation.
//
// API → preview coverage matrix:
//
//   BasicListPage init(items:config:content:)      → Flat + minimal
//   BasicListPage init(sections:config:content:)   → Sectioned
//   .basicPageLeading(_:)                          → Sectioned
//   .basicPageTrailing(_:)                         → Flat
//   .basicPageSearch(_:prompt:)                    → Flat (with search)
//   (no .basicPageSearch)                          → Minimal / Sectioned /
//                                                    Empty / Loading
//   .basicPageIsLoading(_:)                        → Loading row
//   .basicPageRowTap(_:)                           → Flat
//   .basicPageRowSwipeActions(.trailing)           → Flat (Delete)
//   .basicPageRowSwipeActions(.leading,
//                             allowsFullSwipe: false) → Flat (Pin)
//   .basicPageRefresh(_:)                          → Flat
//   .basicPageLoadMore(_:)                         → Flat
//   Default empty state (from config)              → Empty at launch
//   .basicPageDatePager(...)                       → Date pager (below list)
//   .basicPageContentKey(_:transition:)            → Date pager (slide per
//                                                    flip direction)
//   Standalone (no NavigationStack)                → every preview here
//   Embedded in NavigationStack                    → Embedded preview
//
// Data is English account fixtures rendered through `PagePreviewRow` so the
// shapes have their own look, without going through any Localizable tables.

// MARK: Fixtures

private let previewPageConfig = BasicListPageConfig(
    titleColor: .primary,
    titleFont: .system(.title2, design: .rounded).weight(.bold),
    subtitleColor: .secondary,
    subtitleFont: .system(.footnote, design: .rounded),
    backgroundColor: Color(white: 0.96),
    headerListSpacing: 8,
    searchBackground: Color(white: 0.92),
    searchForeground: .primary,
    emptyIcon: "tray",
    emptyTitle: "Nothing here yet",
    emptyMessage: "Accounts you add will show up in this list.",
    emptyIconColor: .secondary,
    progressTint: .blue,
    destructiveActionTint: .red,
    bottomClearance: 60,
    pagerChevronColor: .primary,
    pagerTextColor: .primary,
    pagerTextFont: .system(.title3, design: .rounded).weight(.bold))

private struct PagePreviewItem: Identifiable {
    /// STABLE identity per page+row — the date-pager preview re-keys the
    /// list per window, and the slide transition needs rows that keep
    /// their identity within a page (a fresh UUID per body pass would make
    /// every render a full replacement).
    let id: Int
    let title: String
    let note: String
    let symbol: String
    let amount: Double
    let isIncome: Bool
}

/// English account fixtures shared by every preview — diverse enough that
/// the demo shapes don't look alike.
private let pagePreviewFixtures: [(title: String, note: String, symbol: String, amount: Double, isIncome: Bool)] = [
    ("Main checking", "Everyday spending", "banknote.fill", 2_400, true),
    ("Savings vault", "6-month buffer", "shield.fill", 8_120, true),
    ("Groceries card", "Weekly market", "cart.fill", 186.40, false),
    ("Transport card", "Commute", "car.fill", 74.20, false),
    ("Subscriptions", "Monthly plans", "play.tv.fill", 45.99, false),
    ("Rent escrow", "Apartment", "house.fill", 780, false),
    ("Coffee fund", "Latte, size M", "cup.and.saucer.fill", 24.50, false),
    ("Investments", "Index portfolio", "chart.line.uptrend.xyaxis", 1_062.30, true)
]

/// Item from the fixture (1-based index, wraps around) — negative or zero
/// indices are normalized to 1 so a bad call can't crash on a negative
/// array index. `page` namespaces the identity so paged previews (date
/// pager) keep row identity stable WITHIN a page and distinct ACROSS pages.
private func pageFixtureItem(at index: Int, page: Int = 0, note: String? = nil) -> PagePreviewItem {
    let fixture = pagePreviewFixtures[(max(index, 1) - 1) % pagePreviewFixtures.count]
    return PagePreviewItem(
        id: page * 100 + max(index, 1),
        title: fixture.title, note: note ?? fixture.note,
        symbol: fixture.symbol, amount: fixture.amount,
        isIncome: fixture.isIncome)
}

/// "+$2,400.00" / "−$86.40" — income green, expense regular, digits uniform
/// (monospaced) so the money column stays aligned.
private func pagePreviewAmount(_ item: PagePreviewItem) -> String {
    String(format: item.isIncome ? "+$%.2f" : "−$%.2f", item.amount)
}

/// Demo row for the page previews — the cell applies `.basicListRowStyle()`
/// ITSELF (same contract as the engine's previews: the page never re-styles
/// caller content).
private struct PagePreviewRow: View {
    let item: PagePreviewItem

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
            Text(pagePreviewAmount(item))
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(item.isIncome ? Color.green : Color.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .basicListRowStyle()
    }
}

/// Demo trailing slot — a round add button, the typical screen action.
private struct PagePreviewTrailing: View {
    var body: some View {
        Button {
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24))
        }
    }
}

/// Demo leading slot — a close glyph, the sheet/cover role.
private struct PagePreviewLeading: View {
    var body: some View {
        Image(systemName: "xmark.circle.fill")
            .font(.system(size: 24))
            .foregroundStyle(.secondary)
    }
}

// Previews are built through dedicated structs — complex logic (state
// mutations inside closures) crammed straight into a #Preview macro crashes
// the type-checker.

// MARK: 1. Flat page — search + trailing slot + the engine behaviors

private struct FlatPagePreview: View {
    @State private var items: [PagePreviewItem] = (1...12).map { pageFixtureItem(at: $0) }
    @State private var query = ""
    @State private var loadRound = 0

    /// The search text filters the ARRAY on the caller's side — the page
    /// renders the field, the data stays the caller's business.
    private var filtered: [PagePreviewItem] {
        query.isEmpty ? items : items.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        BasicListPage(title: "Accounts", items: filtered, config: previewPageConfig) {
            PagePreviewRow(item: $0)
        }
        .basicPageSearch($query, prompt: "Search accounts")
        .basicPageTrailing { PagePreviewTrailing() }
        .basicPageEmptyState {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("No account matches \"\(query)\"")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        }
        // BOTH edges in one list: swipe left → Pin (full swipe OFF — the
        // tap must be explicit), swipe right → Delete (full swipe fires it,
        // the handler is only the confirm hand-off).
        .basicPageRowSwipeActions { _ in
            [BasicListSwipeAction(title: "Delete", systemImage: "trash", role: .destructive) {}]
        }
        .basicPageRowSwipeActions(edge: .leading, allowsFullSwipe: false) { _ in
            [BasicListSwipeAction(title: "Pin", systemImage: "pin.fill") {}]
        }
        .basicPageRowTap { tapped in
            items.removeAll { $0.id == tapped.id }
        }
        .basicPageRefresh {
            try? await Task.sleep(for: .seconds(0.6))
        }
        .basicPageLoadMore(mode: .pixelDefault) {
            try? await Task.sleep(for: .seconds(0.3))
            loadRound += 1
            items += (1...6).map { offset in
                pageFixtureItem(
                    at: loadRound * 6 + offset,
                    note: "Loaded round \(loadRound)")
            }
        }
    }
}

// MARK: 2. Sectioned page — leading slot, no search

private struct SectionedPagePreview: View {
    /// Group header: label + count — sticky while scrolling (engine
    /// behavior, untouched by the page).
    private static func sectionHeader(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count) accounts")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    static let sections: [BasicListSection<PagePreviewItem>] = [
        BasicListSection(section: "Active", items: [
            pageFixtureItem(at: 1), pageFixtureItem(at: 3), pageFixtureItem(at: 4)
        ], itemID: \.id) {
            sectionHeader("ACTIVE", count: 3)
        },
        BasicListSection(section: "Archived", items: [
            pageFixtureItem(at: 5), pageFixtureItem(at: 7)
        ], itemID: \.id) {
            sectionHeader("ARCHIVED", count: 2)
        }
    ]

    var body: some View {
        BasicListPage(
            title: "Accounts",
            subtitle: "Grouped by state",
            sections: Self.sections,
            config: previewPageConfig) { PagePreviewRow(item: $0) }
        .basicPageLeading { PagePreviewLeading() }
    }
}

// MARK: 3. Empty at launch — the config-driven default empty state

private struct EmptyPagePreview: View {
    @State private var items: [PagePreviewItem] = []

    var body: some View {
        BasicListPage(title: "Accounts", items: items, config: previewPageConfig) {
            PagePreviewRow(item: $0)
        }
        // No .basicPageEmptyState — the page applies the config-driven
        // default (icon + title + message from previewPageConfig).
    }
}

// MARK: 4. Loading row — chrome busy flag, list stays mounted

private struct LoadingPagePreview: View {
    @State private var items: [PagePreviewItem] = (1...4).map { pageFixtureItem(at: $0) }
    @State private var isLoading = true

    var body: some View {
        BasicListPage(title: "Accounts", items: items, config: previewPageConfig) {
            PagePreviewRow(item: $0)
        }
        .basicPageIsLoading(isLoading)
        .basicPageRefresh {
            try? await Task.sleep(for: .seconds(1.5))
            isLoading = false
        }
    }
}

// MARK: 5. Minimal — title only, no slots, no search

private struct MinimalPagePreview: View {
    @State private var items = (1...6).map { pageFixtureItem(at: $0) }

    var body: some View {
        BasicListPage(title: "Accounts", items: items, config: previewPageConfig) {
            PagePreviewRow(item: $0)
        }
        .basicPageRowTap { _ in }
    }
}

// MARK: 6. Embedded in a NavigationStack — no fighting the system bar

private struct EmbeddedPagePreview: View {
    @State private var items = (1...8).map { pageFixtureItem(at: $0) }
    @State private var query = ""

    var body: some View {
        NavigationStack {
            BasicListPage(title: "Accounts", items: items, config: previewPageConfig) {
                PagePreviewRow(item: $0)
            }
            .basicPageSearch($query, prompt: "Search")
            .basicPageTrailing { PagePreviewTrailing() }
            .navigationTitle("Bank")   // the PAGE renders the title block —
                                       // the nav bar stays free for the app
        }
    }
}

// MARK: 7. Date pager — previous/next period paging (BudgetDetail pattern)

private struct DatePagerPagePreview: View {
    /// Start of the displayed month — paged by the stepper itself.
    @State private var windowStart = Calendar.current.date(
        from: DateComponents(year: 2026, month: 10, day: 1)) ?? .now
    /// The latest flip direction — drives the asymmetric slide, the same
    /// way the app screens track it (new page enters from the direction
    /// the user moved toward).
    @State private var pageForward = true

    /// The newest page — the CURRENT month's start: forward disables
    /// exactly there, back walks into history month by month.
    private static var anchor: Date {
        Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    }

    /// Displayed page index, relative to the anchor (0 = current month,
    /// −1 = last month, …) — the DATA key of the page.
    private var pageIndex: Int {
        Calendar.current.dateComponents([.month], from: Self.anchor, to: windowStart)
            .month ?? 0
    }

    /// Caller-owned format (the wiring point) — the package never formats
    /// dates.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// Window label between the chevrons — re-computed per body pass.
    private var windowText: String {
        let end = Calendar.current.date(
            byAdding: DateComponents(month: 1, day: -1), to: windowStart) ?? windowStart
        return "\(Self.dayFormatter.string(from: windowStart)) - "
            + Self.dayFormatter.string(from: end)
    }

    /// Per-page data — the fixture wheel ROTATES by page, so every period
    /// shows different rows (a paged page is a different window of data,
    /// not the same rows with a new label). Row identity is stable within
    /// a page and distinct across pages (id = page · 100 + row).
    private var items: [PagePreviewItem] {
        (1...8).map { row in
            let rotated = ((row + pageIndex * 3 - 1) % 8 + 8) % 8 + 1
            return pageFixtureItem(at: rotated, page: pageIndex, note: windowText)
        }
    }

    var body: some View {
        BasicListPage(
            title: "Budget",
            subtitle: "Monthly window",
            items: items,
            config: previewPageConfig) { PagePreviewRow(item: $0) }
        // The BudgetDetail paging mechanics: the list identity is the
        // window — a tap rebuilds the list under a new identity inside the
        // pager's spring, and the OLD page slides out while the NEW one
        // slides in FROM THE DIRECTION the user moved toward.
        .basicPageContentKey(windowStart, transition: .asymmetric(
            insertion: .move(edge: pageForward ? .trailing : .leading),
            removal: .move(edge: pageForward ? .leading : .trailing)))
        .basicPageDatePager(
            text: windowText,
            windowStart: $windowStart,
            anchor: Self.anchor,
            unit: .month,
            onNavigate: { forward in pageForward = forward })
    }
}

// MARK: - Preview catalog

#Preview("Flat — search, slots, swipe both edges, tap, load-more") {
    FlatPagePreview()
}

#Preview("Sectioned — leading slot") {
    SectionedPagePreview()
}

#Preview("Empty at launch — default empty state") {
    EmptyPagePreview()
}

#Preview("Loading row — busy flag") {
    LoadingPagePreview()
}

#Preview("Minimal — title only") {
    MinimalPagePreview()
}

#Preview("Embedded in NavigationStack") {
    EmbeddedPagePreview()
}

#Preview("Date pager — previous/next period") {
    DatePagerPagePreview()
}
#endif
