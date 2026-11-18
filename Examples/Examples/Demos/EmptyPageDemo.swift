import SwiftUI
import BasicList

// MARK: - Empty state demo — the config-driven default, and out of it
//
// Starts empty: the page applies the DEFAULT empty state from the config
// (icon + title + message). The trailing + button appends real items —
// the list identity never breaks across the empty/loaded phases because
// the empty state runs INSIDE the list.

struct EmptyPageDemo: View {
    @State private var items: [DemoItem] = []

    var body: some View {
        BasicListPage(title: "Accounts", items: items, config: DemoTheme.page) {
            DemoRowView(item: $0)
        }
        .basicPageTrailing {
            Button {
                items.append(demoItem(at: items.count + 1))
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
            }
        }
        .basicPageRowSwipeActions { item in
            [BasicListSwipeAction(title: "Delete", systemImage: "trash", role: .destructive) {
                items.removeAll { $0.id == item.id }
            }]
        }
        .basicPageRefresh {
            // Pull-to-load on an empty list — a light "fetch" then land
            // with data, showing the in-list empty→loaded hand-off.
            guard items.isEmpty else { return }
            try? await Task.sleep(for: .seconds(0.8))
            items = (1...8).map { demoItem(at: $0) }
        }
    }
}
