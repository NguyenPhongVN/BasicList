import Foundation

// MARK: - Demo data — the shared fixtures
//
// English transaction fixtures — diverse glyphs/colors/money so the demo
// shapes don't look alike. Ids are STABLE per page+row: the date-pager demo
// re-keys the list per window, and the slide transition needs rows that
// keep their identity within a page (a fresh UUID per body pass would make
// every render a full replacement).

struct DemoItem: Identifiable {
    let id: Int
    let title: String
    let note: String
    let symbol: String
    let amount: Double
    let isIncome: Bool
    var isPinned = false
}

/// One English fixture — a struct with named members instead of a
/// positional tuple so the fixture table reads at a glance.
private struct DemoFixture {
    let title: String
    let note: String
    let symbol: String
    let amount: Double
    let isIncome: Bool
}

private let demoFixtures: [DemoFixture] = [
    DemoFixture(title: "Whole Foods", note: "Groceries", symbol: "cart.fill", amount: 86.40, isIncome: false),
    DemoFixture(title: "Salary", note: "October payroll", symbol: "banknote.fill", amount: 2_400, isIncome: true),
    DemoFixture(title: "Uber", note: "Commute", symbol: "car.fill", amount: 14.20, isIncome: false),
    DemoFixture(title: "Freelance", note: "Logo project", symbol: "laptopcomputer", amount: 350, isIncome: true),
    DemoFixture(title: "Netflix", note: "Monthly plan", symbol: "play.tv.fill", amount: 15.99, isIncome: false),
    DemoFixture(title: "Rent", note: "Apartment", symbol: "house.fill", amount: 780, isIncome: false),
    DemoFixture(title: "Coffee", note: "Latte, size M", symbol: "cup.and.saucer.fill", amount: 4.50, isIncome: false),
    DemoFixture(title: "Dividend", note: "Quarterly payout", symbol: "chart.line.uptrend.xyaxis", amount: 62.30, isIncome: true)
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

/// "+$2,400.00" / "−$86.40" — income green, expense regular, digits uniform
/// (monospaced at the call site) so the money column stays aligned.
func demoAmount(_ value: Double, income: Bool) -> String {
    String(format: income ? "+$%.2f" : "−$%.2f", value)
}

/// The fixture item's signed amount.
func demoAmount(_ item: DemoItem) -> String {
    demoAmount(item.amount, income: item.isIncome)
}
