import SwiftUI
import BasicList

// MARK: - Empty state demo — the config-driven default, and out of it
//
// Starts empty: the page applies the config's icon/title/message through a
// CUSTOM builder (the config carries no action — the HIG asks an empty
// state to offer the user a way out, so the builder adds the primary
// action). The trailing + button appends real items — the list identity
// never breaks across the empty/loaded phases because the empty state runs
// INSIDE the list.

struct EmptyPageDemo: View {
    @State private var items: [DemoItem] = []
    // Monotonic id source — count-based ids collide after a delete
    // (remove item 2 of [1, 2, 3], the next append would reuse id 2).
    @State private var added = 0

    var body: some View {
        BasicListPage(title: "Accounts", items: items, config: DemoTheme.page) {
            DemoRowView(item: $0)
        }
        .basicPageTrailing {
            GlassIconButton(systemImage: "plus", label: "Add account") {
                added += 1; items.append(demoItem(at: added, page: 1))
            }
        }
        .basicPageEmptyState {
            VStack(spacing: 16) {
                Image(systemName: "tray")
                    .font(.system(.largeTitle, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    Text("Nothing here yet")
                        .font(.system(.headline, design: .rounded))
                    Text("Accounts you add will show up in this list.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                // The HIG empty-state escape hatch: one primary action.
                Button {
                    Haptics.tap()
                    added += 1; items.append(demoItem(at: added, page: 1))
                } label: {
                    Label("Add your first account", systemImage: "plus")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .basicPageSwipeActions { item in
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
