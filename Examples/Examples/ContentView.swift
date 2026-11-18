import SwiftUI
import BasicList

// MARK: - The hub — the demo catalog, built ON the package itself
//
// The hub list is a `BasicListView` (the engine, dogfooded): rows via
// `onRowTap` → programmatic navigation, not NavigationLink — the same
// "data in, events out" contract the demos teach.

struct ContentView: View {
    @State private var path: [DemoKind] = []

    init() {
        // Demo launch routing — `simctl launch ... Examples -datePager`
        // jumps straight to one demo (handy for screenshots and manual
        // testing); no argument → the hub.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-datePager") {
            _path = State(initialValue: [.datePager])
        } else if arguments.contains("-flat") {
            _path = State(initialValue: [.flat])
        } else if arguments.contains("-sectioned") {
            _path = State(initialValue: [.sectioned])
        } else if arguments.contains("-empty") {
            _path = State(initialValue: [.empty])
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            BasicListView(items: DemoKind.allCases, config: DemoTheme.list) { entry in
                HubRowView(entry: entry)
            }
            .basicListHeader {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BasicList Examples")
                        .font(.system(.title, design: .rounded).weight(.bold))
                    Text("Every demo exercises one layer of the package — page scaffold, engine, date pager.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onRowTap { path.append($0) }
            .background(DemoTheme.canvas)
            .navigationTitle("Examples")
            .navigationDestination(for: DemoKind.self) { $0.destination }
        }
    }
}

/// Hub row — same render language as the demo rows (glyph + title + note),
/// full-area tap comes from the engine's `onRowTap` + VoiceOver button trait.
private struct HubRowView: View {
    let entry: DemoKind

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(entry.tint)
                .frame(width: 36, height: 36)
                .background(entry.tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(entry.subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .basicListRowStyle()
    }
}
