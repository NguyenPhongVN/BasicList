import SwiftUI
import BasicList

// MARK: - Sectioned page demo — sticky headers + per-group footers

struct SectionedPageDemo: View {

    /// Income/expense groups — sticky headers pin while scrolling (engine
    /// behavior, untouched by the page), the group footers scroll like a
    /// real section.
    private var sections: [BasicListSection<DemoItem>] {
        let income = (1...24).filter { demoItem(at: $0).isIncome }.map { demoItem(at: $0) }
        let expense = (1...24).filter { !demoItem(at: $0).isIncome }.map { demoItem(at: $0) }
        let incomeTotal = income.reduce(0) { $0 + $1.amount }
        let expenseTotal = expense.reduce(0) { $0 + $1.amount }

        return [
            BasicListSection(section: "income", items: income, itemID: \.id) {
                sectionHeader("INCOME", count: income.count)
            } footer: {
                sectionFooter(demoAmount(incomeTotal, income: true))
            },
            BasicListSection(section: "expense", items: expense, itemID: \.id) {
                sectionHeader("EXPENSE", count: expense.count)
            } footer: {
                sectionFooter(demoAmount(expenseTotal, income: false))
            }
        ]
    }

    var body: some View {
        BasicListPage(
            title: "Transactions",
            subtitle: "Grouped by direction",
            sections: sections,
            config: DemoTheme.page) { DemoRowView(item: $0) }
        .basicPageTrailing {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 20))
        }
    }

    private func sectionHeader(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count) items")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func sectionFooter(_ total: String) -> some View {
        HStack {
            Text("Total")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text(total)
                .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
