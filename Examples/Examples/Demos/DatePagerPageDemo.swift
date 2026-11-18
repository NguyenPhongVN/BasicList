import SwiftUI
import BasicList

// MARK: - Date pager demo — the period-paging showpiece
//
// The BudgetDetail pattern end to end: the pager below the list steps the
// window one month per tap, the list identity IS the window (content key)
// and the old page slides out while the new one slides in from the direction
// the user moved toward — spring from the pager, data per page.

struct DatePagerPageDemo: View {
    /// Start of the displayed month — paged by the stepper itself.
    @State private var windowStart = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    /// The latest flip direction — drives the asymmetric slide.
    @State private var pageForward = true

    /// The newest page — the CURRENT month's start: forward disables exactly
    /// there, back walks into history month by month.
    private static var anchor: Date {
        Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    }

    /// Displayed page index relative to the anchor (0 = current month,
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

    /// Per-page data — the fixture wheel rotates by page, so every period
    /// shows different rows (a paged page is a different window of data,
    /// not the same rows with a new label).
    private var items: [DemoItem] {
        (1...8).map { row in
            let rotated = ((row + pageIndex * 3 - 1) % 8 + 8) % 8 + 1
            return demoItem(at: rotated, page: pageIndex, note: windowText)
        }
    }

    var body: some View {
        BasicListPage(
            title: "Budget",
            subtitle: "Monthly window",
            items: items,
            config: DemoTheme.page) { DemoRowView(item: $0) }
        // The flip mechanics: the list identity is the window — a tap
        // rebuilds the list under a new identity inside the pager's spring.
        .basicPageContentKey(windowStart, transition: .asymmetric(
            insertion: .move(edge: pageForward ? .trailing : .leading),
            removal: .move(edge: pageForward ? .leading : .trailing)))
        // The pager is APP chrome (this file's sibling `BasicListDatePager`,
        // the BudgetStepperView pattern) — the page only provides the
        // below-list slot via `.basicPageBottomBar`.
        .basicPageBottomBar {
            BasicListDatePager(
                text: windowText,
                windowStart: $windowStart,
                anchor: Self.anchor,
                unit: .month,
                onNavigate: { forward in pageForward = forward },
                chevronColor: DemoTheme.pagerChevronColor,
                textColor: DemoTheme.pagerTextColor,
                textFont: DemoTheme.pagerTextFont)
        }
    }
}
