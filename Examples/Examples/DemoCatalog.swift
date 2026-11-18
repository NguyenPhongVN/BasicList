import SwiftUI
import BasicList

// MARK: - Demo catalog — the shared demo vocabulary
//
// One wiring point for every demo screen: the theme (a full
// `BasicListPageConfig` + the engine-level `BasicListConfig`), the fixture
// data and the row. Mirrors the package's philosophy on the app side —
// colors/metrics live HERE, not in the demo screens.

/// The demo look — one place to change everything.
enum DemoTheme {

    /// The canvas both the hub and every demo page pour behind themselves.
    static let canvas = Color(white: 0.96)

    /// Page-level config for every `BasicListPage` demo.
    static let page = BasicListPageConfig(
        titleColor: .primary,
        titleFont: .system(.title2, design: .rounded).weight(.bold),
        subtitleColor: .secondary,
        subtitleFont: .system(.footnote, design: .rounded),
        backgroundColor: canvas,
        headerListSpacing: 8,
        searchBackground: Color(white: 0.92),
        searchForeground: .primary,
        emptyIcon: "tray",
        emptyTitle: "Nothing here yet",
        emptyMessage: "Items you add will show up in this list.",
        emptyIconColor: .secondary,
        progressTint: .blue,
        destructiveActionTint: .red,
        bottomClearance: 0,
        pagerChevronColor: .primary,
        pagerTextColor: .primary,
        pagerTextFont: .system(.title3, design: .rounded).weight(.bold))

    /// Engine-level config for screens that mount `BasicListView` directly
    /// (the hub). Pushed pages cover the bottom — no tab bar clearance.
    static let list = BasicListConfig(destructiveActionTint: .red, bottomClearance: 0)
}

/// One demo fixture — a transaction with a stable id (per page+row) so the
/// date-pager slide keeps row identity within a page.
struct DemoItem: Identifiable {
    let id: Int
    let title: String
    let note: String
    let symbol: String
    let amount: Double
    let isIncome: Bool
    var isPinned = false
}

/// English transaction fixtures — diverse glyphs/colors/money so the demo
/// shapes don't look alike.
private let demoFixtures: [(title: String, note: String, symbol: String, amount: Double, isIncome: Bool)] = [
    ("Whole Foods", "Groceries", "cart.fill", 86.40, false),
    ("Salary", "October payroll", "banknote.fill", 2_400, true),
    ("Uber", "Commute", "car.fill", 14.20, false),
    ("Freelance", "Logo project", "laptopcomputer", 350, true),
    ("Netflix", "Monthly plan", "play.tv.fill", 15.99, false),
    ("Rent", "Apartment", "house.fill", 780, false),
    ("Coffee", "Latte, size M", "cup.and.saucer.fill", 4.50, false),
    ("Dividend", "Quarterly payout", "chart.line.uptrend.xyaxis", 62.30, true)
]

/// Fixture item (1-based index, wraps around) — `page` namespaces the id so
/// paged demos keep identity stable WITHIN a page, distinct ACROSS pages.
func demoItem(at index: Int, page: Int = 0, note: String? = nil) -> DemoItem {
    let fixture = demoFixtures[(max(index, 1) - 1) % demoFixtures.count]
    return DemoItem(
        id: page * 100 + max(index, 1),
        title: fixture.title,
        note: note ?? fixture.note,
        symbol: fixture.symbol,
        amount: fixture.amount,
        isIncome: fixture.isIncome)
}

/// "+$2,400.00" / "−$86.40" — income green, expense regular.
func demoAmount(_ item: DemoItem) -> String {
    String(format: item.isIncome ? "+$%.2f" : "−$%.2f", item.amount)
}

/// The demo row — glyph + title + note + money; the cell applies
/// `.basicListRowStyle()` ITSELF (the engine never re-styles caller content).
struct DemoRowView: View {
    let item: DemoItem

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
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
            }
            Text(demoAmount(item))
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(item.isIncome ? Color.green : Color.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .basicListRowStyle()
    }
}

// MARK: Catalog

/// The demos the hub offers — each one exercises a layer of the package.
enum DemoKind: String, CaseIterable, Identifiable {
    case flat
    case sectioned
    case datePager
    case empty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flat: return "Flat page"
        case .sectioned: return "Sectioned page"
        case .datePager: return "Date pager"
        case .empty: return "Empty state"
        }
    }

    var subtitle: String {
        switch self {
        case .flat: return "Search · slots · swipe both edges · load-more"
        case .sectioned: return "Sticky headers · group footers · swipe"
        case .datePager: return "Previous/next period · slide transition"
        case .empty: return "Default empty state · pull-to-load"
        }
    }

    var symbol: String {
        switch self {
        case .flat: return "list.bullet"
        case .sectioned: return "square.grid.2x2"
        case .datePager: return "calendar"
        case .empty: return "tray"
        }
    }

    var tint: Color {
        switch self {
        case .flat: return .blue
        case .sectioned: return .orange
        case .datePager: return .purple
        case .empty: return .secondary
        }
    }

    @ViewBuilder var destination: some View {
        switch self {
        case .flat: FlatPageDemo()
        case .sectioned: SectionedPageDemo()
        case .datePager: DatePagerPageDemo()
        case .empty: EmptyPageDemo()
        }
    }
}
