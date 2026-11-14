import SwiftUI

// MARK: - BasicList preview catalog
//
// Live demo suite covering EVERY public API of the module — one preview per
// capability so each is visible and tweakable in isolation. Moved out of
// BasicListView.swift to keep the engine file focused on mechanics (audit D1).
// All demo fixtures/configs here are file-private; the real design values
// stay with the caller (BasicListConfig.house).
//
// API → preview coverage matrix:
//
//   BasicListView init(items:config:content:)        → Flat — swipe, tap, load-more
//   BasicListView init(items:id:config:content:)     → Non-Identifiable items
//   BasicListView init(sections:config:content:)     → Sectioned — sticky headers
//   .basicListHeader(.scrollsWithContent)            → Flat / Sectioned / most others
//   .basicListHeader(.pinnedTop)                     → Pinned header
//   .basicListEmptyState(_:)                         → Flat (after removing rows)
//                                                       + Empty at launch
//   .basicListFooter(_:)                             → Small list / Refresh error
//   .rowSwipeActions(.trailing)                      → Flat / Small list
//   .rowSwipeActions(.leading)                       → Small list (Pin)
//   .rowContextMenu(_:)                              → Flat
//   .onRowTap(_:)                                    → Flat / Non-Identifiable / Small list
//   .onMoveRows(_:) + .basicEditMode(_:)             → Reorder (iOS)
//   .onRefresh(_:)                                   → Empty at launch / 4 pages /
//                                                       slow spinner / error
//   .onLoadMore(mode: .pixelDefault)                 → Flat (library default 600pt)
//   .onLoadMore(mode: .pixelThreshold(150))          → Tight threshold
//   .onLoadMore(mode: .pagesAhead(2))                → 4 pages
//   BasicPlainList(config:_:)                        → Bare list
//   BasicListConfig (tint + bottomClearance)         → previewConfig, visible in
//                                                       every swipe/spacer demo
//   BasicListSection (footer / no footer)            → Sectioned
//   BasicListSwipeAction (destructive / regular)     → Flat / Small list
//   BasicListHeaderMode (both cases)                 → Flat + Pinned header
//   BasicListLoadMoreMode (all three forms)          → Flat / Tight threshold / 4 pages
//   BasicListSpacer(height:)                         → Self-built List (manual) +
//                                                       Bare list (via config)
//   BasicListScrollSentinel (standalone, no gate)    → Self-built List
//   View.basicListRowStyle()                         → PreviewRow cells + explicit
//                                                       in Bare / Self-built
//
// ⚠️ NOT demonstrated on purpose: `.pinnedTop` + sectioned — documented as
// UNVERIFIED (see BasicListView.basicListHeader); avoid until it's tested.
//
// Data is English transaction fixtures rendered through `PreviewRow` (round
// glyph + title + subtitle + money) so every shape has its own look, without
// going through the app's Localizable tables.

// MARK: Fixtures

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

/// Fixture tuple (1-based index, wraps around) — negative or zero indices
/// are normalized to 1 so a bad call can't crash on a negative array index.
private func fixture(
    at index: Int
) -> (title: String, note: String, symbol: String, amount: Double, isIncome: Bool) {
    previewFixtures[(max(index, 1) - 1) % previewFixtures.count]
}

/// Item from the fixture (1-based index, wraps around) — `note` overrides the
/// fixture label when the caller needs its own (e.g. "Loaded round 2").
private func fixtureItem(at index: Int, note: String? = nil) -> PreviewItem {
    let fixture = fixture(at: index)
    return PreviewItem(
        title: fixture.title, note: note ?? fixture.note,
        symbol: fixture.symbol, amount: fixture.amount,
        isIncome: fixture.isIncome)
}

/// Item from the fixture with a page label — the load-more rhythm shows up
/// right in the data.
private func pagedFixtureItem(at index: Int, page: Int) -> PreviewItem {
    fixtureItem(at: index, note: "\(fixture(at: index).note) · page \(page)")
}

/// "+$2,400.00" / "−$86.40" — income green, expense regular, digits uniform
/// (monospaced) so the money column stays aligned.
private func previewAmount(_ item: PreviewItem) -> String {
    String(format: item.isIncome ? "+$%.2f" : "−$%.2f", item.amount)
}

/// Demo row for previews: colored round glyph + title + subtitle + money —
/// closer to the opening bars of a real app cell than a bare `Text`. The cell
/// applies `.basicListRowStyle()` ITSELF — the engine never re-styles it.
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

// MARK: 1. BasicListView — the three data-in shapes

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
            // `.pixelDefault` — the library's own default constant
            // (pixelThreshold(600)), passed explicitly here to show the form.
            .onLoadMore(mode: .pixelDefault) {
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

private struct NonIdentifiablePreview: View {
    /// Plain strings carry no `id` — the `init(items:id:config:content:)`
    /// form attaches one via closure, like `ForEach(id:)`. Names stay unique:
    /// the closure IS the identity.
    @State private var names = ["Whole Foods", "Salary", "Uber", "Rent", "Netflix"]

    var body: some View {
        BasicListView(items: names, id: { $0 }, config: previewConfig) { name in
            Text(name)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .basicListRowStyle()
        }
        .basicListHeader {
            PreviewHeader(
                title: "Non-Identifiable items",
                subtitle: "init(items:id:) — tap a row to remove it")
        }
        .onRowTap { name in
            names.removeAll { $0 == name }
        }
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

    /// First group declares a footer, second omits it — both
    /// `BasicListSection` inits in one list.
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

// MARK: 2. Header modes

/// 30 rows — long enough to really scroll: the `.pinnedTop` header stays
/// glued to the top while the rows slide under it. Flat list only —
/// `.pinnedTop` + sectioned is documented as UNVERIFIED.
private struct PinnedHeaderPreview: View {
    @State private var items = (1...30).map { fixtureItem(at: $0) }

    var body: some View {
        BasicListView(items: items, config: previewConfig) { PreviewRow(item: $0) }
            .basicListHeader(mode: .pinnedTop) {
                PreviewHeader(
                    title: "Pinned header",
                    subtitle: "mode: .pinnedTop — stays at the top while rows scroll")
            }
            .background(Color.secondary.opacity(0.12))
    }
}

// MARK: 3. Empty & few rows

/// Starts with ZERO items — the empty state is visible immediately (the usual
/// demos only reach it after removing every row). Pull to refresh loads the
/// first data; no `onLoadMore` attached → the list never fires load-more,
/// even while empty (the engine adds no sentinel without a handler).
private struct EmptyStartPreview: View {
    @State private var items: [PreviewItem] = []

    var body: some View {
        BasicListView(items: items, config: previewConfig) { PreviewRow(item: $0) }
            .basicListHeader {
                PreviewHeader(
                    title: "Empty at launch",
                    subtitle: "Empty state inside the list — pull to load rows")
            }
            .basicListEmptyState {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Nothing yet — pull to refresh to load rows")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(40)
            }
            .onRefresh {
                try? await Task.sleep(for: .seconds(0.8))
                items = [7, 3, 1].map { fixtureItem(at: $0) }
            }
            .background(Color.secondary.opacity(0.12))
    }
}

/// 3 rows — under one screen: no onLoadMore attached, so the bottom probe has
/// no meaning (a short list produces no geometry change after attach); header
/// and footer still scroll with content, swipe on BOTH edges + tap stay
/// alive. The "little data" shape of real apps: a few rows must keep the
/// exact rhythm, no artificial blank space.
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

// MARK: 4. Load-more modes

/// `.pixelThreshold(150)` — a TIGHT region: fires only 150pt from the bottom
/// (vs the 600pt library default `.pixelDefault`). 4 pages × 25 rows; the
/// handler no-ops once out of pages (the VM-side `exhausted` contract).
private struct TightThresholdPreview: View {
    private static let rowsPerPage = 25
    private static let lastPage = 4

    @State private var page = 1
    @State private var items = (1...25).map { pagedFixtureItem(at: $0, page: 1) }

    var body: some View {
        BasicListView(items: items, config: previewConfig) { PreviewRow(item: $0) }
            .basicListHeader {
                PreviewHeader(
                    title: "Tight threshold",
                    subtitle: page < Self.lastPage
                        ? "Page \(page)/\(Self.lastPage) — mode: .pixelThreshold(150)"
                        : "Page \(page)/\(Self.lastPage) — exhausted, load-more no-ops")
            }
            .onLoadMore(mode: .pixelThreshold(Self.threshold)) {
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

    private static let threshold: CGFloat = 150
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

// MARK: 5. Refresh behaviors

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

// MARK: 6. Reorder (iOS)

/// Drag-to-reorder: `.onMoveRows` + `.basicEditMode` — the drag handle only
/// appears when `editMode` is `.active`; the footer button toggles it (an
/// `EditButton` would need a navigation context). The handler is a hand-off —
/// the screen owns the array mutation and persistence.
#if os(iOS)
private struct ReorderPreview: View {
    @State private var items = [1, 7, 3, 5, 2, 8].map { fixtureItem(at: $0) }
    @State private var editMode: EditMode = .inactive

    var body: some View {
        BasicListView(items: items, config: previewConfig) { PreviewRow(item: $0) }
            .basicListHeader {
                PreviewHeader(
                    title: "Reorder",
                    subtitle: "Toggle Edit — drag the handles to move rows")
            }
            .basicListFooter {
                Button(editMode == .active ? "Done" : "Edit") {
                    editMode = editMode == .active ? .inactive : .active
                }
                .buttonStyle(.borderedProminent)
                .padding(12)
            }
            .onMoveRows { source, destination in
                items.move(fromOffsets: source, toOffset: destination)
            }
            .basicEditMode($editMode)
            .background(Color.secondary.opacity(0.12))
    }
}
#endif

// MARK: 7. Bare building blocks — screens that build their own list

/// A screen that builds its own rows — `BasicPlainList` gives the bare house
/// list (transparent background, content margins 0, minimum row height 0) and
/// the cells apply `.basicListRowStyle()` themselves. The bottom clearance
/// comes from the config (`previewConfig.bottomClearance` = 60) — the list
/// inserts its own spacer, no manual `BasicListSpacer` needed here.
private struct BareListPreview: View {
    var body: some View {
        BasicPlainList(config: previewConfig) {
            Text("Self-built screen")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            ForEach(1...12, id: \.self) { index in
                PreviewRow(item: fixtureItem(at: index))
            }
            Text("Own footer — the list inserted the bottom-clearance spacer")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(12)
        }
        .background(Color.secondary.opacity(0.12))
    }
}

/// A screen that writes its OWN `List` and assembles the house look from the
/// shared vocabulary: `.basicListRowStyle()` on each row (via `PreviewRow`),
/// `BasicListSpacer` for the tab-bar clearance, and a standalone
/// `BasicListScrollSentinel` (no shared gate — fires on `onAppear`) as the
/// load-more trigger. Loop prevention lives on THIS side: the demo caps
/// itself at 4 rounds, the way a real VM would guard with `inFlight`/`exhausted`.
private struct SelfBuiltSentinelPreview: View {
    @State private var items = (1...8).map { fixtureItem(at: $0) }
    @State private var loadRound = 0
    private static let maxRounds = 4

    var body: some View {
        List {
            ForEach(items) { item in
                PreviewRow(item: item)
            }
            BasicListScrollSentinel {
                guard loadRound < Self.maxRounds else { return } // VM-side cap
                try? await Task.sleep(for: .seconds(0.3))
                loadRound += 1
                items += (1...4).map {
                    fixtureItem(at: loadRound * 4 + $0, note: "Loaded round \(loadRound)")
                }
            }
            BasicListSpacer(height: previewConfig.bottomClearance)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 0)
        .background(Color.secondary.opacity(0.12))
    }
}

// MARK: - Preview catalog

#Preview("Flat — swipe, tap, load-more") {
    FlatListPreview()
}

#Preview("Non-Identifiable items — id closure") {
    NonIdentifiablePreview()
}

#Preview("Sectioned — sticky headers") {
    SectionedListPreview()
}

#Preview("Pinned header — .pinnedTop") {
    PinnedHeaderPreview()
}

#Preview("Empty at launch — pull to load") {
    EmptyStartPreview()
}

#Preview("Flat — few rows (no load-more)") {
    FewItemsPreview()
}

#Preview("Tight threshold — .pixelThreshold(150)") {
    TightThresholdPreview()
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

#if os(iOS)
#Preview("Reorder — onMoveRows + editMode") {
    ReorderPreview()
}
#endif

#Preview("Bare list — BasicPlainList") {
    BareListPreview()
}

#Preview("Self-built List — sentinel + spacer") {
    SelfBuiltSentinelPreview()
}
