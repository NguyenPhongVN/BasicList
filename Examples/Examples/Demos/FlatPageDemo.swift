import SwiftUI
import BasicList

// MARK: - Flat page demo — the full engine surface on one screen
//
// Search (caller-owned filtering), leading/trailing slots, swipe on BOTH
// edges (Pin without full swipe / Delete with the confirm hand-off), row
// tap, pull-to-refresh and continuous load-more — one `BasicListPage`.

struct FlatPageDemo: View {
    @State private var items: [DemoItem] = (1...12).map { demoItem(at: $0) }
    @State private var query = ""
    @State private var loadRound = 0
    @State private var isLoading = false

    /// The search filters the ARRAY on the caller's side — the page renders
    /// the field, the data stays the screen's business.
    private var filtered: [DemoItem] {
        query.isEmpty ? items : items.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        BasicListPage(title: "Transactions", subtitle: "\(items.count) items", items: filtered, config: DemoTheme.page) {
            DemoRowView(item: $0)
        }
        .basicPageSearch($query, prompt: "Search transactions")
        .basicPageTrailing {
            // A REAL slot — adds a fixture, so the screen reacts to chrome.
            Button {
                items.insert(demoItem(at: items.count + 1), at: 0)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
            }
        }
        .basicPageIsLoading(isLoading)
        .basicPageEmptyState {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("No transaction matches \"\(query)\"")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        }
        // BOTH edges: swipe left → Pin (full swipe OFF — the tap must be
        // explicit), swipe right → Delete (full swipe fires it, the handler
        // is only the confirm hand-off).
        .basicPageRowSwipeActions { item in
            [BasicListSwipeAction(title: "Delete", systemImage: "trash", role: .destructive) {
                items.removeAll { $0.id == item.id }
            }]
        }
        .basicPageRowSwipeActions(edge: .leading, allowsFullSwipe: false) { item in
            [BasicListSwipeAction(
                title: item.isPinned ? "Unpin" : "Pin",
                systemImage: item.isPinned ? "pin.slash" : "pin.fill") {
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].isPinned.toggle()
                }
            }]
        }
        .basicPageRowContextMenu { item in
            Button("Duplicate \"\(item.title)\"") {
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items.insert(item, at: index + 1)
                }
            }
        }
        .basicPageRowTap { tapped in
            if let index = items.firstIndex(where: { $0.id == tapped.id }) {
                items[index].isPinned.toggle()
            }
        }
        .basicPageRefresh {
            isLoading = true
            try? await Task.sleep(for: .seconds(1))
            isLoading = false
        }
        .basicPageLoadMore(mode: .pixelDefault) {
            try? await Task.sleep(for: .seconds(0.3))
            loadRound += 1
            items += (1...6).map { offset in
                demoItem(at: loadRound * 6 + offset, note: "Loaded round \(loadRound)")
            }
        }
    }
}
