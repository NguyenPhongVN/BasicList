import SwiftUI
import BasicList

// MARK: - Refresh & load-more demo — paging end to end, SLOW on purpose
//
// The network is fake but the CONTRACT is real: the VM-side guards
// (`inFlight` + `exhausted`) live HERE, the engine only fires. Pages load
// with a 0.6 s delay so the footer progress is visible, the pull-to-refresh
// reloads page 1 with the page loading row above the list (list identity
// never breaks), and the exhausted state ends the chain cleanly.

struct PagedListDemo: View {
    /// Page 1 — ten rows, every row labeled with its page so the paging
    /// rhythm shows right in the data.
    @State private var items: [DemoItem] = (1...10).map {
        demoItem(at: $0, page: 1, note: "Page 1")
    }
    @State private var page = 1
    /// Load-more in flight — drives the footer progress row (the engine has
    /// no error/progress surface; state belongs to the screen).
    @State private var isFetching = false
    /// Pull-to-refresh in flight — drives the chrome loading row.
    @State private var isRefreshing = false
    /// Out of pages — the load-more handler stops; the footer announces it.
    @State private var exhausted = false

    /// The demo's page budget — a real VM stops when the API says so.
    private static let maxPages = 6

    var body: some View {
        BasicListPage(title: "Feed", subtitle: "\(items.count) items · \(page) page\(page == 1 ? "" : "s")", items: items, config: DemoTheme.page) {
            DemoRowView(item: $0)
        }
        .basicPageIsLoading(isRefreshing)
        .basicPageFooter {
            // The paging footnote — progress while fetching, the end-of-list
            // announcement when the VM is exhausted. Scrolls with the
            // content like a real section of the list.
            if let footer = footerState {
                HStack(spacing: 8) {
                    if isFetching {
                        ProgressView()
                            .controlSize(.small)
                            .tint(DemoTheme.progressTint)
                    }
                    Text(footer)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        }
        .basicPageRefresh {
            // A real VM would refetch page 1 — the demo redraws its first
            // window after a visible delay. Errors would be handled HERE
            // (the spinner ends by itself either way).
            isRefreshing = true
            try? await Task.sleep(for: .seconds(1.2))
            items = (1...10).map { demoItem(at: $0, page: 1, note: "Page 1 · refreshed") }
            page = 1
            exhausted = false
            isRefreshing = false
        }
        .basicPageLoadMore(mode: .pagesAhead(2)) {
            await fetchNextPage()
        }
    }

    private var footerState: String? {
        if isFetching { return "Loading more…" }
        if exhausted { return "End of list — \(items.count) items across \(page) pages" }
        return nil
    }

    /// The VM side of the contract: `inFlight` blocks concurrent fires (the
    /// probe/sentinel/gate collapse duplicates but a fire may still land
    /// while a fetch runs), `exhausted` stops the chain — both guards live
    /// HERE, the engine keeps none of them.
    private func fetchNextPage() async {
        guard !isFetching, !exhausted else { return }
        isFetching = true
        try? await Task.sleep(for: .seconds(0.6))   // the fake network
        page += 1
        items += (1...8).map { demoItem(at: $0, page: page, note: "Page \(page)") }
        if page >= Self.maxPages { exhausted = true }
        isFetching = false
    }
}
